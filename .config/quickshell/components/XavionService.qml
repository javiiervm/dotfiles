import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: service

    property bool panelOpen: false
    property bool backendReady: false
    property bool busy: false

    property string activeModel: ""
    property string lastError: ""
    property int currentAssistantIndex: -1

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

        messageModel.append({
            role: "assistant",
            text: "",
            streaming: true
        })

        currentAssistantIndex = messageModel.count - 1
        busy = true

        if (!sendCommand({
            type: "chat",
            message: content,
            intent_mode: "auto",
            tone_mode: "casual"
        })) {
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
            lastError = ""

            if (event.model !== undefined)
                activeModel = String(event.model)

            break

        case "start":
            busy = true
            break

        case "chunk":
            if (
                currentAssistantIndex >= 0
                && currentAssistantIndex < messageModel.count
            ) {
                var currentText =
                    messageModel.get(currentAssistantIndex).text

                var chunk =
                    event.text !== undefined
                    ? String(event.text)
                    : ""

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

            currentAssistantIndex = -1
            busy = false
            streamUpdated()
            break

        case "new_done":
            messageModel.clear()
            currentAssistantIndex = -1
            busy = false
            lastError = ""
            streamUpdated()
            break

        case "reset_done":
            messageModel.clear()
            currentAssistantIndex = -1
            busy = false
            streamUpdated()
            break
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
