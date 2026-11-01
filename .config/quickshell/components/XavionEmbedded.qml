
import QtQuick
import QtQuick.Layouts
import ".."

// Xavion is an actual Launcher view, not a separate window or glass card.
// Launcher.qml already owns the GlassSurface, blur, rounded edges and animations.
Item {
    id: root

    required property var service
    signal requestBack()

    focus: visible
    property bool settingsOpen: false
    property var queuedMessages: []

    readonly property color accent: service.gradientMid
    readonly property color accentSoft: Qt.alpha(service.gradientMid, 0.38)
    readonly property color controlBackground: Qt.alpha(Theme.white, 0.075)
    readonly property color controlBorder: Qt.alpha(Theme.white, 0.13)
    readonly property color controlBackgroundStrong: Qt.alpha(Theme.white, 0.10)
    readonly property string currentModelLabel: {
        if (service.activeModel && service.activeModel.length > 0)
            return service.activeModel
        if (service.selectedModel && service.selectedModel.length > 0)
            return service.selectedModel
        return service.backendReady ? "Ready" : "Starting Xavion..."
    }

    Keys.onEscapePressed: function(event) {
        back()
        event.accepted = true
    }

    function back() {
        if (settingsOpen) {
            settingsOpen = false
            Qt.callLater(focusInput)
        } else {
            requestBack()
        }
    }

    function focusInput() {
        if (visible && !settingsOpen && service.backendReady && !service.busy)
            composerInput.forceActiveFocus()
    }

    function sendMessage() {
        const content = composerInput.text.trim()
        if (!content.length || !service.backendReady || service.busy)
            return
        if (service.sendMessage(content)) {
            composerInput.text = ""
            Qt.callLater(function() { messageList.positionViewAtEnd() })
        }
    }

    // Enter from the Launcher's search field lands here, including while
    // Xavion's Python bridge is still starting. Keep prompts in order.
    function sendFromLauncher(message) {
        const content = String(message === undefined || message === null ? "" : message).trim()
        if (!content.length) return
        const pending = queuedMessages.slice()
        pending.push(content)
        queuedMessages = pending
        service.ensureBackend()
        flushQueuedMessage()
    }

    function flushQueuedMessage() {
        if (!queuedMessages.length || !service.backendReady || service.busy)
            return
        if (service.sendMessage(queuedMessages[0]))
            queuedMessages = queuedMessages.slice(1)
    }

    onVisibleChanged: {
        if (visible) {
            service.ensureBackend()
            Qt.callLater(focusInput)
        } else {
            settingsOpen = false
        }
    }

    // The parent Launcher supplies the ONLY background. No opaque red panel,
    // independent corner radius, extra borders or duplicated glow effects.
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Launcher-style header: title and current model at left, actions at right.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: 20
                color: backArea.containsMouse ? Qt.alpha(Theme.white, 0.15) : root.controlBackground
                border.width: 1
                border.color: root.controlBorder

                Text {
                    anchors.centerIn: parent
                    text: ""
                    font.family: Theme.fontIcons
                    font.pixelSize: 16
                    color: Theme.white
                }
                MouseArea {
                    id: backArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.back()
                }
            }

            ColumnLayout {
                spacing: 1
                Text {
                    text: "Xavion"
                    color: Theme.white
                    font.family: Theme.fontMain
                    font.pixelSize: 16
                    font.bold: true
                }
                Text {
                    text: root.currentModelLabel
                    color: Theme.grey1
                    font.family: Theme.fontMain
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                visible: !root.settingsOpen
                Layout.preferredWidth: visible ? Math.max(105, newChatLabel.implicitWidth + 30) : 0
                Layout.preferredHeight: 40
                radius: 13
                color: newChatArea.containsMouse ? Qt.alpha(Theme.white, 0.15) : root.controlBackground
                border.width: 1
                border.color: root.controlBorder

                Text {
                    id: newChatLabel
                    anchors.centerIn: parent
                    text: "New chat"
                    color: Theme.white
                    font.family: Theme.fontMain
                    font.pixelSize: 12
                    font.bold: true
                }
                MouseArea {
                    id: newChatArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.service.newConversation()
                }
            }

            Rectangle {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: 13
                color: settingsArea.containsMouse || root.settingsOpen
                       ? Qt.alpha(Theme.white, 0.16) : root.controlBackground
                border.width: 1
                border.color: root.settingsOpen ? Qt.alpha(Theme.white, 0.20) : root.controlBorder
                Text {
                    anchors.centerIn: parent
                    text: "󰒓"
                    font.family: Theme.fontIcons
                    font.pixelSize: 17
                    color: Theme.white
                }
                MouseArea {
                    id: settingsArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.settingsOpen = !root.settingsOpen
                        if (root.settingsOpen && root.service.backendReady)
                            root.service.refreshModels()
                        else
                            Qt.callLater(root.focusInput)
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 12
            Layout.bottomMargin: 8
            Layout.preferredHeight: 1
            color: Qt.alpha(Theme.white, 0.10)
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Chat view: messages float directly on the Launcher's glass.
            ListView {
                id: messageList
                anchors.fill: parent
                anchors.topMargin: 9
                anchors.bottomMargin: 7
                visible: !root.settingsOpen
                clip: true
                spacing: 11
                model: root.service.messages
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: messageDelegate
                    required property string role
                    required property string text
                    required property bool streaming
                    readonly property bool fromUser: role === "user"

                    width: messageList.width
                    height: fromUser ? userBubble.height + 10 : assistantRow.height + 10

                    // Measure the text without constraining it to the bubble width.
                    // TextEdit.implicitWidth is unsuitable here because the edit's
                    // explicit width depends on the bubble itself.
                    Text {
                        id: userWidthProbe
                        visible: false
                        text: messageDelegate.fromUser ? messageDelegate.text : ""
                        font.family: Theme.fontMain
                        font.pixelSize: 13
                        textFormat: Text.PlainText
                    }

                    Rectangle {
                        id: userBubble
                        visible: messageDelegate.fromUser
                        anchors.right: parent.right
                        // Fit short messages to their actual text; cap long ones
                        // so they wrap normally instead of stretching the chat.
                        width: Math.min(messageList.width * 0.78,
                                        Math.max(50, userWidthProbe.implicitWidth + 30))
                        height: userText.implicitHeight + 24
                        radius: 18
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: root.service.gradientStart }
                            GradientStop { position: 0.52; color: root.service.gradientMid }
                            GradientStop { position: 1; color: root.service.gradientEnd }
                        }
                        TextEdit {
                            id: userText
                            x: 15
                            y: 11
                            width: parent.width - 30
                            text: messageDelegate.fromUser ? messageDelegate.text : ""
                            color: Theme.white
                            font.family: Theme.fontMain
                            font.pixelSize: 13
                            wrapMode: TextEdit.Wrap
                            textFormat: TextEdit.PlainText
                            readOnly: true
                            selectByMouse: true
                            selectionColor: Qt.alpha(Theme.white, 0.25)
                        }
                    }

                    Row {
                        id: assistantRow
                        visible: !messageDelegate.fromUser
                        spacing: 11
                        width: parent.width
                        height: Math.max(30, assistantText.implicitHeight + 6)

                        Image {
                            width: 29
                            height: 29
                            source: "../assets/xavion/chat.png"
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                        }

                        TextEdit {
                            id: assistantText
                            width: Math.max(0, assistantRow.width - 40)
                            text: messageDelegate.fromUser ? "" : messageDelegate.text
                                  + (messageDelegate.streaming ? " ▌" : "")
                            color: Qt.alpha(Theme.white, 0.92)
                            font.family: Theme.fontMain
                            font.pixelSize: 13
                            wrapMode: TextEdit.Wrap
                            textFormat: TextEdit.MarkdownText
                            readOnly: true
                            selectByMouse: true
                            selectionColor: root.accentSoft
                        }
                    }
                }

                footer: Item {
                    width: messageList.width
                    height: root.service.awaitingFirstChunk ? 36 : 0
                    visible: root.service.awaitingFirstChunk
                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 42
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 7
                        Text {
                            visible: root.service.thinking
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Thinking"
                            color: Theme.grey1
                            font.family: Theme.fontMain
                            font.pixelSize: 12
                        }
                        Repeater {
                            model: 3
                            Rectangle {
                                required property int index
                                width: 6
                                height: 6
                                radius: 3
                                color: root.accent
                                SequentialAnimation on opacity {
                                    running: root.service.awaitingFirstChunk
                                    loops: Animation.Infinite
                                    PauseAnimation { duration: index * 130 }
                                    NumberAnimation { from: 0.3; to: 1; duration: 230 }
                                    NumberAnimation { from: 1; to: 0.3; duration: 230 }
                                }
                            }
                        }
                    }
                }

                onCountChanged: Qt.callLater(function() { messageList.positionViewAtEnd() })
            }

            // Clean Launcher-style empty state: the avatar is the only artwork.
            Column {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -10
                visible: !root.settingsOpen && root.service.messages.count === 0
                spacing: 12

                Image {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 78
                    height: 78
                    source: "../assets/xavion/chat.png"
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Ask Xavion anything"
                    color: Theme.white
                    font.family: Theme.fontMain
                    font.pixelSize: 19
                    font.bold: true
                }
                Text {
                    visible: root.service.lastError.length > 0
                    width: Math.min(360, root.width - 44)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: root.service.lastError
                    color: Theme.red
                    font.family: Theme.fontMain
                    font.pixelSize: 11
                }
            }

            Flickable {
                visible: root.settingsOpen
                anchors.fill: parent
                clip: true
                contentWidth: width
                contentHeight: settingsContent.implicitHeight + 22
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: settingsContent
                    width: parent.width
                    y: 7
                    spacing: 15

                    Text {
                        text: "Appearance"
                        color: Theme.white
                        font.family: Theme.fontMain
                        font.pixelSize: 15
                        font.bold: true
                    }
                    Text {
                        text: "Accent colors for Xavion messages and controls"
                        color: Theme.grey1
                        font.family: Theme.fontMain
                        font.pixelSize: 12
                    }

                    Row {
                        spacing: 10
                        Repeater {
                            model: root.service.gradientPresets.length
                            Rectangle {
                                required property int index
                                readonly property var preset: root.service.gradientPresets[index]
                                width: 45
                                height: 45
                                radius: 14
                                color: root.controlBackground
                                border.width: root.service.gradientIndex === index ? 2 : 1
                                border.color: root.service.gradientIndex === index
                                              ? root.accent : root.controlBorder
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 27
                                    height: 27
                                    radius: 9
                                    gradient: Gradient {
                                        GradientStop { position: 0; color: preset.start }
                                        GradientStop { position: 0.5; color: preset.mid }
                                        GradientStop { position: 1; color: preset.end }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.service.setGradient(index)
                                }
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Qt.alpha(Theme.white, 0.10) }
                    Text {
                        text: "Response tone"
                        color: Theme.white
                        font.family: Theme.fontMain
                        font.pixelSize: 15
                        font.bold: true
                    }
                    Flow {
                        width: parent.width
                        spacing: 9
                        Repeater {
                            model: root.service.toneOptions
                            Rectangle {
                                required property var modelData
                                width: toneLabel.implicitWidth + 29
                                height: 38
                                radius: 12
                                color: root.service.toneMode === modelData.value
                                       ? Qt.alpha(Theme.white, 0.16) : root.controlBackground
                                border.width: 1
                                border.color: root.service.toneMode === modelData.value
                                              ? root.accentSoft : root.controlBorder
                                Text {
                                    id: toneLabel
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: root.service.toneMode === modelData.value
                                           ? Theme.white : Qt.alpha(Theme.white, 0.75)
                                    font.family: Theme.fontMain
                                    font.pixelSize: 12
                                    font.bold: root.service.toneMode === modelData.value
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.service.setTone(modelData.value)
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: root.service.reasoningSupported
                        width: parent.width; height: 1
                        color: Qt.alpha(Theme.white, 0.10)
                    }
                    Text {
                        visible: root.service.reasoningSupported
                        text: "Reasoning"
                        color: Theme.white
                        font.family: Theme.fontMain
                        font.pixelSize: 15
                        font.bold: true
                    }
                    Flow {
                        visible: root.service.reasoningSupported
                        width: parent.width
                        spacing: 9
                        Repeater {
                            model: root.service.reasoningOptions
                            Rectangle {
                                required property var modelData
                                width: reasoningLabel.implicitWidth + 29
                                height: 38
                                radius: 12
                                opacity: modelData.enabled ? 1 : 0.4
                                color: root.service.reasoningMode === modelData.value
                                       ? Qt.alpha(Theme.white, 0.16) : root.controlBackground
                                border.width: 1
                                border.color: root.service.reasoningMode === modelData.value
                                              ? root.accentSoft : root.controlBorder
                                Text {
                                    id: reasoningLabel
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: Theme.white
                                    font.family: Theme.fontMain
                                    font.pixelSize: 12
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: modelData.enabled
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.service.setReasoning(modelData.value)
                                }
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Qt.alpha(Theme.white, 0.10) }
                    Row {
                        width: parent.width
                        height: 26
                        spacing: 12
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Local model"
                            color: Theme.white
                            font.family: Theme.fontMain
                            font.pixelSize: 15
                            font.bold: true
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰑐"
                            color: Theme.grey1
                            font.family: Theme.fontIcons
                            font.pixelSize: 17
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.service.refreshModels()
                            }
                        }
                    }
                    Text {
                        visible: root.service.availableModels.length === 0
                        text: root.service.backendReady ? "No local models found" : "Starting Xavion..."
                        color: Theme.grey1
                        font.family: Theme.fontMain
                        font.pixelSize: 12
                    }
                    Repeater {
                        model: root.service.availableModels
                        Rectangle {
                            required property string modelData
                            readonly property bool selected: modelData === root.service.selectedModel
                                || (root.service.selectedModel.length === 0
                                    && modelData === root.service.activeModel)
                            width: settingsContent.width
                            height: 43
                            radius: 13
                            color: selected ? Qt.alpha(Theme.white, 0.16) : root.controlBackground
                            border.width: 1
                            border.color: selected ? root.accentSoft : root.controlBorder
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData
                                color: Theme.white
                                font.family: Theme.fontMain
                                font.pixelSize: 12
                            }
                            Text {
                                visible: parent.selected
                                anchors.right: parent.right
                                anchors.rightMargin: 15
                                anchors.verticalCenter: parent.verticalCenter
                                text: ""
                                color: root.accent
                                font.family: Theme.fontIcons
                                font.pixelSize: 14
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.service.setModel(modelData)
                            }
                        }
                    }
                }
            }
        }

        // Neutral, Launcher-themed message composer (not the search bar).
        Item {
            visible: !root.settingsOpen
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 74 : 0

            Rectangle {
                id: composerBar
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 7
                width: Math.min(parent.width, 540)
                height: 44
                radius: height / 2
                color: root.controlBackgroundStrong
                border.width: 1
                border.color: composerInput.activeFocus
                              ? Qt.alpha(Theme.white, 0.22) : root.controlBorder

                TextInput {
                    id: composerInput
                    anchors.left: parent.left
                    anchors.leftMargin: 18
                    anchors.right: sendButton.left
                    anchors.rightMargin: 11
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    verticalAlignment: TextInput.AlignVCenter
                    enabled: root.service.backendReady && !root.service.busy
                    clip: true
                    color: Theme.white
                    selectionColor: Qt.alpha(Theme.blue, 0.45)
                    selectedTextColor: Theme.white
                    font.family: Theme.fontMain
                    font.pixelSize: 14
                    onAccepted: root.sendMessage()
                    Keys.onEscapePressed: function(event) {
                        root.back()
                        event.accepted = true
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: composerInput.text.length === 0
                        text: root.service.busy ? "Xavion is responding..."
                              : root.service.backendReady ? "Ask anything..." : "Starting Xavion..."
                        color: Theme.grey1
                        opacity: 0.85
                        font.family: Theme.fontMain
                        font.pixelSize: 14
                    }
                }

                Rectangle {
                    id: sendButton
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32
                    height: 32
                    radius: 16
                    readonly property bool canSend: root.service.backendReady
                                                    && !root.service.busy
                                                    && composerInput.text.trim().length > 0
                    color: canSend ? Qt.alpha(Theme.white, 0.14) : Qt.alpha(Theme.white, 0.06)
                    border.width: 1
                    border.color: canSend ? Qt.alpha(Theme.white, 0.18) : root.controlBorder
                    Text {
                        anchors.centerIn: parent
                        text: "󰁝"
                        color: sendButton.canSend ? Theme.white : Theme.grey1
                        font.family: Theme.fontIcons
                        font.pixelSize: 16
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: sendButton.canSend
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.sendMessage()
                    }
                }
            }

            Text {
                anchors.top: composerBar.bottom
                anchors.topMargin: 7
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Enter to send  ·  Esc to return"
                color: Qt.alpha(Theme.white, 0.36)
                font.family: Theme.fontMain
                font.pixelSize: 10
            }
        }
    }

    Connections {
        target: root.service
        function onStreamUpdated() {
            Qt.callLater(function() { messageList.positionViewAtEnd() })
        }
        function onBackendReadyChanged() {
            root.flushQueuedMessage()
            Qt.callLater(root.focusInput)
        }
        function onBusyChanged() {
            if (!root.service.busy) {
                root.flushQueuedMessage()
                Qt.callLater(root.focusInput)
            }
        }
    }
}
