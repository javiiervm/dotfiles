import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: service

    property bool panelOpen: false
    property bool backendReady: false
    property bool busy: false
    property bool awaitingFirstChunk: false
    property bool settingsLoaded: false

    property string activeModel: ""
    property string lastError: ""
    property int currentAssistantIndex: -1

    // ============================================================
    // PERSISTED SETTINGS
    // ============================================================

    property int gradientIndex: 0

    // These values mirror the options exposed by Xavion dev.
    property string toneMode: "adaptive"
    property string intentMode: "auto"

    // Empty means "use the backend default" until settings are loaded.
    property string selectedModel: ""

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
        }
    ]

    readonly property color gradientStart:
        gradientPresets[gradientIndex].start

    readonly property color gradientMid:
        gradientPresets[gradientIndex].mid

    readonly property color gradientEnd:
        gradientPresets[gradientIndex].end

    property alias messages: messageModel

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
        if (busy)
            return "Thinking…"

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

    function sendMessage(message): bool {
        var content = String(message).trim()

        if (content.length === 0)
            return false

        if (!backendReady || busy)
            return false

        lastError = ""

        messageModel.append({
            role: "user",
            text: content,
            streaming: false
        })

        currentAssistantIndex = -1
        awaitingFirstChunk = true
        busy = true

        if (!sendCommand({
            type: "chat",
            message: content,
            intent_mode: intentMode,
            tone_mode: toneMode
        })) {
            awaitingFirstChunk = false
            busy = false
            return false
        }

        streamUpdated()
        return true
    }

    function newConversation(): void {
        if (!backendReady || busy)
            return

        sendCommand({
            type: "new"
        })
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
            lastError = ""

            if (event.model !== undefined)
                activeModel = String(event.model)

            if (event.models !== undefined)
                availableModels = event.models

            applyModelPreference()
            break

        case "models":
            if (event.models !== undefined)
                availableModels = event.models

            if (event.active_model !== undefined)
                activeModel = String(event.active_model)

            applyModelPreference()
            break

        case "model_changed":
            if (event.model !== undefined) {
                activeModel = String(event.model)
                selectedModel = activeModel
            }

            if (event.models !== undefined)
                availableModels = event.models

            break

        case "start":
            busy = true
            awaitingFirstChunk = true
            break

        case "chunk":
            var chunk =
                event.text !== undefined
                ? String(event.text)
                : ""

            if (chunk.length === 0)
                break

            if (currentAssistantIndex < 0) {
                messageModel.append({
                    role: "assistant",
                    text: "",
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
            busy = false

            streamUpdated()
            responseFinished()
            break

        case "error":
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
                    streaming: false
                })
            }

            currentAssistantIndex = -1
            awaitingFirstChunk = false
            busy = false
            streamUpdated()
            break

        case "new_done":
            messageModel.clear()
            currentAssistantIndex = -1
            awaitingFirstChunk = false
            busy = false
            lastError = ""
            streamUpdated()
            break

        case "reset_done":
            messageModel.clear()
            currentAssistantIndex = -1
            awaitingFirstChunk = false
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

                if (key === "gradient") {
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
            service.backendReady = false
            service.awaitingFirstChunk = false
            service.busy = false

            if (service.panelOpen) {
                service.lastError =
                    "Xavion backend stopped (exit "
                    + exitCode
                    + ")"
            }
        }
    }
}
