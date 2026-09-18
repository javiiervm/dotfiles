import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: service

    property bool panelOpen: false
    property bool backendReady: false
    property bool busy: false
    property bool awaitingFirstChunk: false

    property string activeModel: ""
    property string lastError: ""
    property int currentAssistantIndex: -1

    // Persisted visual theme for user bubbles + send button.
    property int gradientIndex: 0
    property int pendingGradientSave: -1

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

    readonly property string gradientStatePath:
        Quickshell.env("HOME")
        + "/.config/quickshell/state/xavion-gradient"

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

    ListModel {
        id: messageModel
    }

    function setGradient(index): void {
        var value = Math.max(
            0,
            Math.min(
                gradientPresets.length - 1,
                Number(index)
            )
        )

        if (isNaN(value))
            return

        value = Math.round(value)

        if (gradientIndex === value)
            return

        gradientIndex = value
        persistGradient()
    }

    function persistGradient(): void {
        pendingGradientSave = gradientIndex

        if (!gradientSave.running)
            flushGradientSave()
    }

    function flushGradientSave(): void {
        if (pendingGradientSave < 0)
            return

        var value = pendingGradientSave
        pendingGradientSave = -1

        gradientSave.command = [
            "bash",
            "-c",
            "mkdir -p \"$HOME/.config/quickshell/state\" && "
            + "printf '%s\\n' '" + value + "' "
            + "> \"$HOME/.config/quickshell/state/xavion-gradient\""
        ]

        gradientSave.running = true
    }

    function ensureBackend(): void {
        if (!bridge.running)
            bridge.running = true
    }

    function togglePanel(): void {
        panelOpen = !panelOpen

        if (panelOpen)
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

        // Do not create Xavion's message yet. While the backend is preparing
        // the first token, the panel shows the animated typing indicator.
        currentAssistantIndex = -1
        awaitingFirstChunk = true
        busy = true

        if (!sendCommand({
            type: "chat",
            message: content,
            intent_mode: "auto",
            tone_mode: "casual"
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

            // First streamed token: remove the typing indicator and only now
            // create Xavion's visible response (with the streaming cursor).
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
            }

            if (currentAssistantIndex < 0) {
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

    Process {
        id: gradientLoad

        running: true

        command: [
            "bash",
            "-c",
            "file=\"$HOME/.config/quickshell/state/xavion-gradient\"; "
            + "if [ -r \"$file\" ]; then cat \"$file\"; else echo 0; fi"
        ]

        stdout: SplitParser {
            onRead: function(data) {
                var value = parseInt(String(data).trim())

                if (
                    !isNaN(value)
                    && value >= 0
                    && value < service.gradientPresets.length
                ) {
                    service.gradientIndex = value
                }
            }
        }
    }

    Process {
        id: gradientSave

        onRunningChanged: {
            if (!running && service.pendingGradientSave >= 0)
                service.flushGradientSave()
        }
    }

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
                    console.warn("Xavion backend:", message)
            }
        }

        onExited: function(exitCode, exitStatus) {
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
