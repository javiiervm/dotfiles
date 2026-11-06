import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: service

    property bool panelOpen: false
    property bool backendReady: false
    property bool busy: false
    property bool awaitingFirstChunk: false
    property bool thinking: false
    // Ephemeral model-generated reasoning. Visible only while it streams;
    // never added to conversation messages or persisted on disk.
    property string reasoningText: ""
    property bool reasoningTraceTruncated: false
    readonly property int maxReasoningCharacters: 24000

    function clearReasoningTrace(): void {
        reasoningText = ""
        reasoningTraceTruncated = false
    }
    property bool settingsLoaded: false

    property string activeModel: ""
    property string lastError: ""
    property int currentAssistantIndex: -1
    property int currentUserIndex: -1
    // Only actual reasoning_start/reasoning_end events control 'thinking'.
    // Image analysis takes priority in the UI; otherwise pending requests
    // without reasoning show the original three animated dots.
    property int pendingImageCount: 0

    // An AI Selection capture is a pending draft, NOT a chat message.
    // The separate overlay passes the image path over Quickshell IPC.
    property string selectionCapturePath: ""
    property bool selectionNewChatPending: false
    signal selectionImageReady(string imagePath)
    readonly property string pendingStatus:
        pendingImageCount > 1 ? "Analyzing images"
        : pendingImageCount === 1 ? "Analyzing image"
        : thinking ? "Thinking" : ""

    // Capabilities come from Ollama /api/show through Xavion's Python backend.
    // Do not guess from the model name.
    property var modelCapabilities: ({})
    readonly property bool visionSupported:
        backendReady
        && activeModel.length > 0
        && (selectedModel.length === 0 || selectedModel === activeModel)
        && modelCapabilities.available === true
        && modelCapabilities.vision === true


    // ============================================================
    // PERSISTED SETTINGS
    // ============================================================

    property int gradientIndex: 0
    // Stored separately so switching themes never discards the custom palette.
    property string customGradientStart: "#8B5CF6"
    property string customGradientMid: "#D946EF"
    property string customGradientEnd: "#FB7185"

    // These values mirror the options exposed by Xavion dev.
    property string toneMode: "adaptive"
    property string intentMode: "auto"

    // Empty means "use the backend default" until settings are loaded.
    property string selectedModel: ""

    // The persistent preference lives in Xavion's backend config.json.
    // Neither changing models nor restarting Quickshell resets the mode.
    property string reasoningMode: "off"
    property string activeReasoningMode: "off"
    property bool reasoningSupported: false
    property string pendingReasoningMode: ""
    property bool requestReasoningEnabled: false
    property string requestReasoningReason: ""

    property var availableModels: []

    readonly property var toneOptions: [
        { value: "adaptive", label: "Adaptive" },
        { value: "casual", label: "Casual" },
        { value: "formal", label: "Formal" },
        { value: "sarcastic", label: "Sarcastic" },
        { value: "concise", label: "Concise" }
    ]

    readonly property var intentOptions: [
        { value: "auto", label: "Auto" },
        { value: "default", label: "General" },
        { value: "math", label: "Math" },
        { value: "code", label: "Code" },
        { value: "translate", label: "Translate" }
    ]

    readonly property var reasoningOptions: [
        { value: "auto", label: "Auto", enabled: true },
        { value: "on", label: "On", enabled: true },
        { value: "off", label: "Off", enabled: true }
    ]

    readonly property var gradientPresets: [
        {
            name: "Xavion",
            start: "#F52765",
            mid: "#FF4A3D",
            end: "#FF8A18"
        },
        {
            name: "Sunset",
            start: "#FF5F6D",
            mid: "#FF8A5B",
            end: "#FFC371"
        },
        {
            name: "Violet",
            start: "#7C3AED",
            mid: "#A855F7",
            end: "#EC4899"
        },
        {
            name: "Ocean",
            start: "#2563EB",
            mid: "#0EA5E9",
            end: "#22D3EE"
        },
        {
            name: "Emerald",
            start: "#059669",
            mid: "#10B981",
            end: "#84CC16"
        },
        {
            name: "Midnight",
            start: "#4338CA",
            mid: "#6366F1",
            end: "#8B5CF6"
        },
        { name: "Rose Gold", start: "#9F365B", mid: "#C2416E", end: "#D66B66" },
        { name: "Cyberpunk", start: "#C026D3", mid: "#7C3AED", end: "#06B6D4" },
        { name: "Arctic", start: "#075985", mid: "#0369A1", end: "#0891B2" },
        { name: "Golden", start: "#92400E", mid: "#B45309", end: "#D97706" },
        { name: "Aurora", start: "#047857", mid: "#059669", end: "#16A34A" },
        { name: "Candy", start: "#9D174D", mid: "#BE185D", end: "#7C3AED" },
        { name: "Graphite", start: "#475569", mid: "#64748B", end: "#94A3B8" },
        {
            name: "Custom",
            start: customGradientStart,
            mid: customGradientMid,
            end: customGradientEnd
        }
    ]

    readonly property int customGradientIndex: gradientPresets.length - 1

    readonly property color gradientStart:
        gradientPresets[gradientIndex].start

    readonly property color gradientMid:
        gradientPresets[gradientIndex].mid

    readonly property color gradientEnd:
        gradientPresets[gradientIndex].end

    property alias messages: messageModel

    property var savedSessions: []
    property bool deletionPending: false
    signal sessionsUpdated()
    signal sessionLoaded()
    signal sessionsDeleted(var deleted, var failed)

    readonly property string configuredRoot:
        Quickshell.env("XAVION_ROOT")
        ? String(Quickshell.env("XAVION_ROOT"))
        : ""

    readonly property string xavionRoot:
        configuredRoot.length > 0
        ? configuredRoot
        : Quickshell.env("HOME") + "/Documents/Personal/Xavion-AI"

    readonly property string pythonExecutable:
        xavionRoot + "/.venv/bin/python"

    readonly property bool backendRunning:
        bridge.running

    readonly property string statusText: {
        if (thinking)
            return "Thinking…"

        if (busy)
            return "Responding…"

        if (backendReady)
            return activeModel.length > 0
                ? "Ready • " + activeModel
                : "Ready"

        if (backendRunning)
            return "Starting…"

        return "Offline"
    }

    signal streamUpdated()
    signal responseFinished()
    signal panelCloseRequested()

    ListModel {
        id: messageModel
    }

    // ============================================================
    // SETTINGS HELPERS
    // ============================================================

    function _hasModel(model): bool {
        for (var i = 0; i < availableModels.length; ++i) {
            if (String(availableModels[i]) === String(model))
                return true
        }

        return false
    }

    function _writeSetting(process, fileName, value): void {
        // Values are passed as $1 rather than interpolated into the shell
        // command, so model names and future values remain safely quoted.
        process.running = false

        process.command = [
            "bash",
            "-c",
            "mkdir -p \"$HOME/.config/quickshell/state\"; "
            + "printf '%s\\n' \"$1\" "
            + "> \"$HOME/.config/quickshell/state/" + fileName + "\"",
            "_",
            String(value)
        ]

        process.running = true
    }

    function setGradient(index): void {
        var value = Math.round(Number(index))

        if (
            isNaN(value)
            || value < 0
            || value >= gradientPresets.length
        ) {
            return
        }

        gradientIndex = value

        _writeSetting(
            gradientSave,
            "xavion-gradient",
            gradientIndex
        )
    }

    // Three editable gradient stops. Validate and persist every accepted change.
    function setCustomGradientStop(stop, colorValue): bool {
        var hex = String(colorValue).trim().toUpperCase()
        if (!/^#[0-9A-F]{6}$/.test(hex))
            return false
        if (stop === 0)
            customGradientStart = hex
        else if (stop === 1)
            customGradientMid = hex
        else if (stop === 2)
            customGradientEnd = hex
        else
            return false

        _writeSetting(customGradientSave, "xavion-custom-gradient",
            customGradientStart + "," + customGradientMid + "," + customGradientEnd)
        setGradient(customGradientIndex)
        return true
    }

    function setTone(value): void {
        var target = String(value)

        for (var i = 0; i < toneOptions.length; ++i) {
            if (toneOptions[i].value === target) {
                toneMode = target

                _writeSetting(
                    toneSave,
                    "xavion-tone",
                    toneMode
                )

                return
            }
        }
    }

    function setIntentMode(value): void {
        var target = String(value)

        for (var i = 0; i < intentOptions.length; ++i) {
            if (intentOptions[i].value === target) {
                intentMode = target

                _writeSetting(
                    intentSave,
                    "xavion-mode",
                    intentMode
                )

                return
            }
        }
    }

    function setReasoning(value): void {
        var target = String(value).toLowerCase()
        if (target !== "auto" && target !== "on" && target !== "off")
            return

        if (!backendReady || !reasoningSupported)
            return

        if (target === reasoningMode && pendingReasoningMode.length === 0)
            return

        // The Python engine persists the mode. Quickshell does not write a
        // second preference file that could override the backend on startup.
        if (sendCommand({ type: "set_reasoning", mode: target })) {
            pendingReasoningMode = target
            reasoningMode = target
        }
    }

    function setModel(value): void {
        var target = String(value)

        if (!_hasModel(target))
            return

        selectedModel = target

        _writeSetting(
            modelSave,
            "xavion-model",
            selectedModel
        )

        if (backendReady) {
            sendCommand({
                type: "set_model",
                model: selectedModel
            })
        }
    }

    function refreshModels(): void {
        if (backendReady) {
            sendCommand({
                type: "list_models"
            })
        }
    }

    function applyModelPreference(): void {
        if (!backendReady || !settingsLoaded)
            return

        if (selectedModel.length === 0) {
            selectedModel = activeModel
            return
        }

        if (_hasModel(selectedModel)) {
            if (selectedModel !== activeModel) {
                sendCommand({
                    type: "set_model",
                    model: selectedModel
                })
            }

            return
        }

        // A saved model disappeared from Ollama. Fall back to the current
        // backend model and persist that valid choice.
        selectedModel = activeModel

        _writeSetting(
            modelSave,
            "xavion-model",
            selectedModel
        )
    }

    // ============================================================
    // BACKEND / PANEL
    // ============================================================

    function ensureBackend(): void {
        if (!bridge.running)
            bridge.running = true
    }

    function togglePanel(): void {
        if (panelOpen) {
            panelCloseRequested()
            return
        }

        panelOpen = true
        ensureBackend()
    }

    function openPanel(): void {
        panelOpen = true
        ensureBackend()
    }

    function closePanel(): void {
        panelOpen = false
    }

    function sendCommand(command): bool {
        if (!bridge.running)
            return false

        bridge.write(JSON.stringify(command) + "\n")
        return true
    }

    // Stored attachments are validated and persisted by the Python core.
    // The bridge exposes image ID/MIME metadata, not binary image contents.
    function _savedImageUrls(attachments): var {
        var urls = []
        var items = Array.isArray(attachments) ? attachments : []
        for (var i = 0; i < items.length; ++i) {
            var item = items[i]
            var id = String(item.id || "")
            var mime = String(item.mime_type || "")
            if (!/^[0-9a-f]{32}$/.test(id))
                continue
            var extension = mime === "image/png" ? ".png"
                          : mime === "image/jpeg" ? ".jpg"
                          : mime === "image/webp" ? ".webp" : ""
            if (!extension.length)
                continue
            urls.push("file://" + xavionRoot + "/data/images/" + id + extension)
        }
        return urls
    }

    function _applyCapabilities(capabilities): void {
        modelCapabilities = (capabilities && typeof capabilities === "object")
            ? capabilities : ({})
    }

    // images is an array of {path: string, url: string}, supplied by the UI.
    // Other clients (launcher and sidebar) may continue to call sendMessage(text).
    function sendMessage(message, images): bool {
        var content = String(message === undefined || message === null ? "" : message).trim()
        var attachments = Array.isArray(images) ? images : []
        if (!content.length && attachments.length === 0)
            return false
        if (!backendReady || busy)
            return false
        if (attachments.length > 4) {
            lastError = "You can attach up to 4 images per message."
            return false
        }
        if (attachments.length && !visionSupported) {
            lastError = "The selected model does not support image input."
            return false
        }

        var sources = []
        var previews = []
        for (var i = 0; i < attachments.length; ++i) {
            var path = String(attachments[i].path || "")
            var url = String(attachments[i].url || "")
            if (!path.length || !url.length) {
                lastError = "Invalid image attachment."
                return false
            }
            sources.push({path: path})
            previews.push(url)
        }

        var command = {
            type: "chat",
            message: content,
            images: sources,
            intent_mode: intentMode,
            tone_mode: toneMode
        }
        lastError = ""
        if (!sendCommand(command))
            return false

        // This role is kept as JSON text for consistent ListModel behavior.
        messageModel.append({
            role: "user",
            text: content,
            imagesJson: JSON.stringify(previews),
            streaming: false
        })
        currentUserIndex = messageModel.count - 1
        pendingImageCount = attachments.length
        currentAssistantIndex = -1
        awaitingFirstChunk = true
        thinking = false
        clearReasoningTrace()
        busy = true
        streamUpdated()
        return true
    }

    function listSessions(): void {
        ensureBackend()
        if (backendReady && !busy)
            sendCommand({ type: "list_sessions" })
    }

    function loadSession(sessionId): void {
        if (!backendReady || busy)
            return
        sendCommand({ type: "load_session", session_id: String(sessionId) })
    }

    // One backend command deletes an entire selection after the UI has
    // obtained a single confirmation from the user.
    function deleteSessions(sessionIds): bool {
        if (!backendReady || busy || deletionPending || !Array.isArray(sessionIds))
            return false

        var uniqueIds = []
        for (var i = 0; i < sessionIds.length; ++i) {
            var id = String(sessionIds[i])
            if (id.length > 0 && uniqueIds.indexOf(id) === -1)
                uniqueIds.push(id)
        }
        if (uniqueIds.length === 0)
            return false

        lastError = ""
        deletionPending = true
        if (!sendCommand({ type: "delete_sessions", session_ids: uniqueIds })) {
            deletionPending = false
            return false
        }
        return true
    }

    function newConversation(): void {
        if (!backendReady || busy || deletionPending)
            return

        sendCommand({
            type: "new"
        })
    }

    // Called by shell.qml after AI Selection crops its frozen screenshot.
    // The backend may still be starting or responding to another message.
    // Keep the capture pending until we can safely create a new session.
    function acceptSelectionCapture(imagePath): void {
        var path = String(imagePath)
        if (!path.startsWith("/") || !/\.png$/i.test(path)) {
            lastError = "Invalid AI Selection screenshot path."
            return
        }
        selectionCapturePath = path
        lastError = ""
        ensureBackend()
        _startSelectionConversation()
    }

    function _startSelectionConversation(): void {
        if (!selectionCapturePath.length || selectionNewChatPending
                || !backendReady || busy || deletionPending)
            return

        // A saved model preference may still be switching after startup.
        if (selectedModel.length && selectedModel !== activeModel)
            return

        if (!visionSupported) {
            lastError = "Choose a vision-capable model to use Ask Xavion."
            selectionCapturePath = ""
            return
        }

        if (sendCommand({ type: "new" }))
            selectionNewChatPending = true
    }

    function handleBackendLine(data): void {
        var line = String(data).trim()

        if (line.length === 0)
            return

        var event

        try {
            event = JSON.parse(line)
        } catch (error) {
            console.warn(
                "XavionService: invalid backend response:",
                line
            )
            return
        }

        switch (event.type) {
        case "ready":
            backendReady = true
            busy = false
            awaitingFirstChunk = false
            thinking = false
            clearReasoningTrace()
            lastError = ""

            if (event.model !== undefined)
                activeModel = String(event.model)

            if (event.models !== undefined)
                availableModels = event.models

            _applyCapabilities(event.capabilities)

            if (event.reasoning_supported !== undefined)
                reasoningSupported = Boolean(event.reasoning_supported)

            if (event.reasoning_mode !== undefined) {
                activeReasoningMode = String(event.reasoning_mode)
                reasoningMode = activeReasoningMode
                pendingReasoningMode = ""
            }

            applyModelPreference()
            listSessions()
            _startSelectionConversation()
            break

        case "models":
            if (event.models !== undefined)
                availableModels = event.models

            if (event.active_model !== undefined)
                activeModel = String(event.active_model)

            _applyCapabilities(event.capabilities)

            if (event.reasoning_supported !== undefined)
                reasoningSupported = Boolean(event.reasoning_supported)

            if (event.reasoning_mode !== undefined) {
                activeReasoningMode = String(event.reasoning_mode)
                reasoningMode = activeReasoningMode
                pendingReasoningMode = ""
            }

            applyModelPreference()
            _startSelectionConversation()
            break

        case "model_changed":
            if (event.model !== undefined) {
                activeModel = String(event.model)
                selectedModel = activeModel
            }

            _applyCapabilities(event.capabilities)

            if (event.models !== undefined)
                availableModels = event.models

            if (event.reasoning_supported !== undefined)
                reasoningSupported = Boolean(event.reasoning_supported)
            else
                reasoningSupported = false

            if (event.reasoning_mode !== undefined) {
                activeReasoningMode = String(event.reasoning_mode)
                reasoningMode = activeReasoningMode
                pendingReasoningMode = ""
            }

            thinking = false
            _startSelectionConversation()
            break

        case "capabilities":
            _applyCapabilities(event.capabilities)
            break

        case "reasoning_changed":
            if (event.mode !== undefined) {
                activeReasoningMode = String(event.mode)
                reasoningMode = activeReasoningMode
            }
            pendingReasoningMode = ""

            if (event.supported !== undefined)
                reasoningSupported = Boolean(event.supported)

            break

        case "start":
            busy = true
            awaitingFirstChunk = true
            thinking = false
            clearReasoningTrace()
            requestReasoningEnabled = Boolean(event.reasoning_enabled)
            requestReasoningReason =
                event.reasoning_reason !== undefined
                ? String(event.reasoning_reason) : ""
            break

        case "reasoning_start":
            // Only the first *actual* thinking token enables the indicator.
            if (busy && awaitingFirstChunk)
                thinking = true
            break

        case "reasoning_chunk":
            // Display the model's actual streamed reasoning in the temporary
            // expandable viewer, never in the final message or saved history.
            if (busy && awaitingFirstChunk && event.text !== undefined) {
                var textPart = String(event.text)
                var remaining = maxReasoningCharacters - reasoningText.length
                if (remaining > 0)
                    reasoningText += textPart.slice(0, remaining)
                if (textPart.length > remaining)
                    reasoningTraceTruncated = true
            }
            break

        case "reasoning_end":
        case "response_start":
            thinking = false
            clearReasoningTrace()
            break

        case "chunk":
            var chunk =
                event.text !== undefined
                ? String(event.text)
                : ""

            if (chunk.length === 0)
                break

            // The first final-answer token closes the temporary viewer.
            thinking = false

            if (currentAssistantIndex < 0) {
                clearReasoningTrace()
                messageModel.append({
                    role: "assistant",
                    text: "",
                    imagesJson: "[]",
                    streaming: true
                })

                currentAssistantIndex = messageModel.count - 1
                awaitingFirstChunk = false
            }

            if (
                currentAssistantIndex >= 0
                && currentAssistantIndex < messageModel.count
            ) {
                var currentText =
                    messageModel.get(currentAssistantIndex).text

                messageModel.setProperty(
                    currentAssistantIndex,
                    "text",
                    currentText + chunk
                )

                streamUpdated()
            }

            break

        case "done":
            if (currentUserIndex >= 0 && currentUserIndex < messageModel.count
                && event.images !== undefined) {
                messageModel.setProperty(currentUserIndex, "imagesJson",
                    JSON.stringify(_savedImageUrls(event.images)))
            }
            currentUserIndex = -1
            pendingImageCount = 0
            if (
                currentAssistantIndex >= 0
                && currentAssistantIndex < messageModel.count
            ) {
                messageModel.setProperty(
                    currentAssistantIndex,
                    "streaming",
                    false
                )
            }

            currentAssistantIndex = -1
            awaitingFirstChunk = false
            thinking = false
            clearReasoningTrace()
            busy = false

            streamUpdated()
            responseFinished()
            _startSelectionConversation()
            break

        case "error":
            // Roll back only an unconfirmed reasoning toggle. The backend
            // remains the source of truth when it rejects a request.
            if (pendingReasoningMode.length > 0) {
                reasoningMode = activeReasoningMode
                pendingReasoningMode = ""
            }
            currentUserIndex = -1
            pendingImageCount = 0
            deletionPending = false
            lastError =
                event.message !== undefined
                ? String(event.message)
                : "Unknown Xavion error"

            if (
                currentAssistantIndex >= 0
                && currentAssistantIndex < messageModel.count
            ) {
                var previousText =
                    messageModel.get(currentAssistantIndex).text

                messageModel.setProperty(
                    currentAssistantIndex,
                    "text",
                    previousText.length > 0
                    ? previousText + "\n\n" + lastError
                    : "Error: " + lastError
                )

                messageModel.setProperty(
                    currentAssistantIndex,
                    "streaming",
                    false
                )
            } else if (busy) {
                messageModel.append({
                    role: "assistant",
                    text: "Error: " + lastError,
                    imagesJson: "[]",
                    streaming: false
                })
            }

            currentAssistantIndex = -1
            awaitingFirstChunk = false
            thinking = false
            clearReasoningTrace()
            busy = false
            if (selectionNewChatPending) {
                selectionNewChatPending = false
                selectionCapturePath = ""
            } else {
                _startSelectionConversation()
            }
            streamUpdated()
            break

        case "sessions":
            savedSessions = event.sessions || []
            sessionsUpdated()
            break

        case "sessions_deleted":
            deletionPending = false
            savedSessions = event.sessions || []
            if (event.active_reset) {
                pendingImageCount = 0
                messageModel.clear()
                currentAssistantIndex = -1
                awaitingFirstChunk = false
                thinking = false
                busy = false
                streamUpdated()
            }
            var deleted = event.deleted || []
            var failed = event.failed || []
            lastError = failed.length > 0
                ? "Could not delete " + failed.length + " conversation(s)."
                : ""
            sessionsUpdated()
            sessionsDeleted(deleted, failed)
            break

        case "session_loaded":
            pendingImageCount = 0
            messageModel.clear()
            var loaded = event.messages || []
            for (var i = 0; i < loaded.length; i++) {
                messageModel.append({
                    role: String(loaded[i].role),
                    text: String(loaded[i].text),
                    imagesJson: JSON.stringify(_savedImageUrls(loaded[i].images)),
                    streaming: false
                })
            }
            currentAssistantIndex = -1
            awaitingFirstChunk = false
            thinking = false
            clearReasoningTrace()
            busy = false
            lastError = ""
            if (event.model !== undefined)
                activeModel = String(event.model)
            _applyCapabilities(event.capabilities)
            if (event.reasoning_supported !== undefined)
                reasoningSupported = Boolean(event.reasoning_supported)
            if (event.reasoning_mode !== undefined) {
                activeReasoningMode = String(event.reasoning_mode)
                reasoningMode = activeReasoningMode
                pendingReasoningMode = ""
            }
            currentUserIndex = -1
            sessionLoaded()
            streamUpdated()
            break

        case "new_done":
            pendingImageCount = 0
            messageModel.clear()
            currentAssistantIndex = -1
            currentUserIndex = -1
            awaitingFirstChunk = false
            thinking = false
            clearReasoningTrace()
            busy = false
            lastError = ""
            streamUpdated()
            if (selectionNewChatPending) {
                selectionNewChatPending = false
                var capturedPath = selectionCapturePath
                selectionCapturePath = ""
                if (capturedPath.length)
                    selectionImageReady(capturedPath)
            }
            break

        case "reset_done":
            pendingImageCount = 0
            messageModel.clear()
            currentAssistantIndex = -1
            awaitingFirstChunk = false
            thinking = false
            clearReasoningTrace()
            busy = false
            streamUpdated()
            break
        }
    }

    // ============================================================
    // SETTINGS PERSISTENCE
    // ============================================================

    Process {
        id: settingsLoad

        running: true

        command: [
            "bash",
            "-c",
            "dir=\"$HOME/.config/quickshell/state\"; "
            + "readv() { "
            + "  file=\"$dir/$1\"; "
            + "  fallback=\"$2\"; "
            + "  if [ -r \"$file\" ]; then cat \"$file\"; else printf '%s' \"$fallback\"; fi; "
            + "}; "
            + "printf 'gradient|%s\\n' \"$(readv xavion-gradient 0)\"; "
            + "printf 'custom|%s\\n' \"$(readv xavion-custom-gradient '#8B5CF6,#D946EF,#FB7185')\"; "
            + "printf 'tone|%s\\n' \"$(readv xavion-tone adaptive)\"; "
            + "printf 'mode|%s\\n' \"$(readv xavion-mode auto)\"; "
            + "printf 'model|%s\\n' \"$(readv xavion-model '')\""
        ]

        stdout: SplitParser {
            onRead: function(data) {
                var line = String(data).trim()
                var separator = line.indexOf("|")

                if (separator < 0)
                    return

                var key = line.substring(0, separator)
                var value = line.substring(separator + 1)

                if (key === "custom") {
                    var colors = value.split(",")
                    if (colors.length === 3 && /^#[0-9a-fA-F]{6}$/.test(colors[0])
                        && /^#[0-9a-fA-F]{6}$/.test(colors[1])
                        && /^#[0-9a-fA-F]{6}$/.test(colors[2])) {
                        service.customGradientStart = colors[0]
                        service.customGradientMid = colors[1]
                        service.customGradientEnd = colors[2]
                    }
                } else if (key === "gradient") {
                    var index = parseInt(value)

                    if (
                        !isNaN(index)
                        && index >= 0
                        && index < service.gradientPresets.length
                    ) {
                        service.gradientIndex = index
                    }
                } else if (key === "tone") {
                    service.toneMode = value
                } else if (key === "mode") {
                    service.intentMode = value
                } else if (key === "model") {
                    service.selectedModel = value
                }
            }
        }

        onRunningChanged: {
            if (!running) {
                service.settingsLoaded = true
                service.applyModelPreference()
            }
        }
    }

    Process {
        id: gradientSave
    }

    Process {
        id: customGradientSave
    }

    Process {
        id: toneSave
    }

    Process {
        id: intentSave
    }

    Process {
        id: modelSave
    }

    // ============================================================
    // XAVION BRIDGE
    // ============================================================

    Process {
        id: bridge

        running: false
        stdinEnabled: true

        workingDirectory: service.xavionRoot

        command: [
            service.pythonExecutable,
            "-u",
            "-m",
            "xavion.interfaces.quickshell.bridge"
        ]

        stdout: SplitParser {
            onRead: function(data) {
                service.handleBackendLine(data)
            }
        }

        stderr: SplitParser {
            onRead: function(data) {
                var message = String(data).trim()

                if (message.length > 0)
                    console.warn(
                        "Xavion backend:",
                        message
                    )
            }
        }

        onExited: function(exitCode) {
            service.deletionPending = false
            service.backendReady = false
            service.awaitingFirstChunk = false
            service.thinking = false
            service.clearReasoningTrace()
            service.busy = false
            service.reasoningSupported = false
            service.pendingReasoningMode = ""
            service.requestReasoningEnabled = false
            service.requestReasoningReason = ""
            service.modelCapabilities = ({})
            service.currentUserIndex = -1
            service.pendingImageCount = 0
            service.selectionNewChatPending = false

            if (service.panelOpen) {
                service.lastError =
                    "Xavion backend stopped (exit "
                    + exitCode
                    + ")"
            }
        }
    }
}
