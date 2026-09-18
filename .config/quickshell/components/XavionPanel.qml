import QtQuick
import QtQuick.Layouts

import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

import ".."

PanelWindow {
    id: panel

    required property var service

    property bool settingsOpen: false

    function closePanel(): void {
        settingsOpen = false
        focusGrab.active = false
        service.closePanel()
    }

    implicitWidth: 390
    implicitHeight: 460

    anchors {
        top: true
        left: true
    }

    margins {
        top: 0
        left: 12
    }

    exclusiveZone: 0
    color: "transparent"

    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: WlrLayershell.OnDemand

    function submitMessage(): void {
        var message = input.text.trim()

        if (message.length === 0)
            return

        if (service.sendMessage(message))
            input.text = ""
    }

    Component.onCompleted: {
        service.ensureBackend()

        Qt.callLater(function() {
            input.forceActiveFocus()
            focusGrab.active = true
        })
    }

    HyprlandFocusGrab {
        id: focusGrab

        windows: [ panel ]

        onCleared: {
            if (service.panelOpen)
                panel.closePanel()
        }
    }

    BackgroundEffect.blurRegion:
        Glass.blurEnabled
        ? panelBlurRegion
        : null

    Region {
        id: panelBlurRegion
        item: panelGlass
        radius: panelGlass.radius
    }

    GlassSurface {
        id: panelGlass

        anchors.fill: parent

        glassRadius: 18
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            // ============================================================
            // HEADER
            // ============================================================

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                spacing: 8

                // New chat / Back.
                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32

                    radius: width / 2

                    color:
                        newChatMouse.containsMouse
                        ? Qt.alpha(Theme.white, 0.10)
                        : "transparent"

                    border.width: 1
                    border.color: Qt.alpha(Theme.white, 0.10)

                    Text {
                        anchors.centerIn: parent

                        // Pencil in chat view, back arrow in settings view.
                        text: panel.settingsOpen ? "󰁍" : "󰏫"

                        color:
                            newChatMouse.containsMouse
                            ? Theme.white
                            : Theme.grey1

                        font.family: Theme.fontIcons
                        font.pixelSize: panel.settingsOpen ? 15 : 14
                    }

                    MouseArea {
                        id: newChatMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        onClicked: {
                            if (panel.settingsOpen) {
                                panel.settingsOpen = false
                            } else {
                                service.newConversation()
                            }
                        }
                    }
                }

                // Settings.
                Rectangle {
                    visible: !panel.settingsOpen

                    Layout.preferredWidth: visible ? 32 : 0
                    Layout.preferredHeight: 32

                    radius: width / 2

                    color:
                        settingsMouse.containsMouse
                        ? Qt.alpha(Theme.white, 0.10)
                        : "transparent"

                    border.width: 1
                    border.color: Qt.alpha(Theme.white, 0.10)

                    Text {
                        anchors.centerIn: parent

                        text: "󰒓"

                        color:
                            settingsMouse.containsMouse
                            ? Theme.white
                            : Theme.grey1

                        font.family: Theme.fontIcons
                        font.pixelSize: 15
                    }

                    MouseArea {
                        id: settingsMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        onClicked:
                            panel.settingsOpen = true
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

            }

            // ============================================================
            // CHAT
            // ============================================================

            Item {
                visible: !panel.settingsOpen

                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: messageList

                    anchors.fill: parent
                    anchors.rightMargin: 6

                    clip: true
                    spacing: 6

                    model: service.messages
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Item {
                        id: messageDelegate

                        required property string role
                        required property string text
                        required property bool streaming

                        readonly property bool fromUser:
                            role === "user"

                        width: messageList.width

                        height:
                            fromUser
                            ? userBubble.height + 8
                            : assistantText.implicitHeight + 12

                        // ====================================================
                        // USER MESSAGE
                        // ====================================================

                        Rectangle {
                            id: userBubble

                            visible: messageDelegate.fromUser

                            anchors.right: parent.right

                            width: Math.min(
                                messageList.width * 0.78,
                                userText.implicitWidth + 24
                            )

                            height: userText.implicitHeight + 18

                            radius: 16

                            // Message-sent entrance animation:
                            // the bubble grows out from the right side of the chat,
                            // similar to modern messaging apps.
                            opacity: messageDelegate.fromUser ? 0 : 1
                            scale: messageDelegate.fromUser ? 0.72 : 1
                            transformOrigin: Item.BottomRight

                            property real entranceOffset: 18

                            transform: Translate {
                                x: userBubble.entranceOffset
                            }

                            gradient: Gradient {
                                orientation: Gradient.Horizontal

                                GradientStop {
                                    position: 0.0
                                    color: service.gradientStart
                                }

                                GradientStop {
                                    position: 0.52
                                    color: service.gradientMid
                                }

                                GradientStop {
                                    position: 1.0
                                    color: service.gradientEnd
                                }
                            }

                            Text {
                                id: userText

                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top

                                    leftMargin: 12
                                    rightMargin: 12
                                    topMargin: 9
                                }

                                text: messageDelegate.text

                                color: Theme.white

                                font.family: Theme.fontMain
                                font.pixelSize: 12

                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                            }
                        }

                        ParallelAnimation {
                            id: userBubbleAppear

                            NumberAnimation {
                                target: userBubble
                                property: "opacity"

                                from: 0
                                to: 1

                                duration: 170
                                easing.type: Easing.OutCubic
                            }

                            NumberAnimation {
                                target: userBubble
                                property: "scale"

                                from: 0.72
                                to: 1

                                duration: 220
                                easing.type: Easing.OutBack
                            }

                            NumberAnimation {
                                target: userBubble
                                property: "entranceOffset"

                                from: 18
                                to: 0

                                duration: 210
                                easing.type: Easing.OutCubic
                            }
                        }

                        Component.onCompleted: {
                            if (messageDelegate.fromUser) {
                                Qt.callLater(function() {
                                    userBubbleAppear.start()
                                })
                            }
                        }

                        // ====================================================
                        // XAVION MESSAGE
                        // ====================================================

                        Text {
                            id: assistantText

                            visible: !messageDelegate.fromUser

                            anchors {
                                left: parent.left
                                right: parent.right

                                leftMargin: 10
                                rightMargin: 20
                            }

                            text:
                                messageDelegate.text
                                + (
                                    messageDelegate.streaming
                                    ? " ▌"
                                    : ""
                                )

                            color: Theme.white

                            font.family: Theme.fontMain
                            font.pixelSize: 12

                            wrapMode: Text.Wrap
                            textFormat: Text.MarkdownText
                            linkColor: Theme.blue
                        }
                    }

                    footer: Item {
                        width: messageList.width
                        height: service.awaitingFirstChunk ? 34 : 0
                        visible: service.awaitingFirstChunk

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 5

                            Repeater {
                                model: 3

                                Rectangle {
                                    required property int index

                                    width: 6
                                    height: 6
                                    radius: 3

                                    color: Theme.grey1
                                    opacity: 0.35

                                    SequentialAnimation on opacity {
                                        running: service.awaitingFirstChunk
                                        loops: Animation.Infinite

                                        PauseAnimation {
                                            duration: index * 140
                                        }

                                        NumberAnimation {
                                            from: 0.35
                                            to: 1.0
                                            duration: 220
                                            easing.type: Easing.InOutQuad
                                        }

                                        NumberAnimation {
                                            from: 1.0
                                            to: 0.35
                                            duration: 220
                                            easing.type: Easing.InOutQuad
                                        }

                                        PauseAnimation {
                                            duration: (2 - index) * 140
                                        }
                                    }

                                    SequentialAnimation on y {
                                        running: service.awaitingFirstChunk
                                        loops: Animation.Infinite

                                        PauseAnimation {
                                            duration: index * 140
                                        }

                                        NumberAnimation {
                                            from: 0
                                            to: -3
                                            duration: 180
                                            easing.type: Easing.OutQuad
                                        }

                                        NumberAnimation {
                                            from: -3
                                            to: 0
                                            duration: 180
                                            easing.type: Easing.InQuad
                                        }

                                        PauseAnimation {
                                            duration: (2 - index) * 140
                                        }
                                    }
                                }
                            }
                        }
                    }

                    onCountChanged: {
                        Qt.callLater(function() {
                            messageList.positionViewAtEnd()
                        })
                    }
                }

                // ============================================================
                // EMPTY STATE
                // ============================================================

                Column {
                    anchors.centerIn: parent
                    spacing: 6

                    visible: service.messages.count === 0

                    Image {
                        anchors.horizontalCenter:
                            parent.horizontalCenter

                        width: 54
                        height: 54

                        source: "../assets/xavion/chat.png"

                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                    }

                    Text {
                        anchors.horizontalCenter:
                            parent.horizontalCenter

                        text: "Ask Xavion anything"

                        color: Theme.grey1
                        font.family: Theme.fontMain
                        font.pixelSize: 12
                    }

                    Text {
                        anchors.horizontalCenter:
                            parent.horizontalCenter

                        text: service.statusText

                        color:
                            service.busy
                            ? Theme.orange
                            : service.backendReady
                                ? Theme.green
                                : Theme.grey1

                        font.family: Theme.fontMain
                        font.pixelSize: 10
                    }

                    Text {
                        anchors.horizontalCenter:
                            parent.horizontalCenter

                        visible: service.lastError.length > 0

                        width: 320
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap

                        text: service.lastError

                        color: Theme.red
                        font.family: Theme.fontMain
                        font.pixelSize: 10
                    }
                }

            }

            // ============================================================
            // SETTINGS
            // ============================================================

            Item {
                visible: panel.settingsOpen

                Layout.fillWidth: true
                Layout.fillHeight: true

                Column {
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right

                        topMargin: 10
                        leftMargin: 8
                        rightMargin: 8
                    }

                    spacing: 14

                    Text {
                        text: "Settings"

                        color: Theme.white
                        font.family: Theme.fontMain
                        font.pixelSize: 16
                        font.bold: true
                    }

                    Column {
                        width: parent.width
                        spacing: 10

                        Text {
                            text: "Message theme"

                            color: Theme.white
                            font.family: Theme.fontMain
                            font.pixelSize: 12
                            font.bold: true
                        }

                        Text {
                            text: "Choose the gradient used for your messages and send button."

                            color: Theme.grey1
                            font.family: Theme.fontMain
                            font.pixelSize: 10
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter

                            spacing: 12

                            Repeater {
                                model: service.gradientPresets.length

                                Item {
                                    required property int index

                                    width: 44
                                    height: 44

                                    Rectangle {
                                        anchors.centerIn: parent

                                        width: 40
                                        height: 40
                                        radius: width / 2

                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal

                                            GradientStop {
                                                position: 0.0
                                                color:
                                                    service.gradientPresets[
                                                        index
                                                    ].start
                                            }

                                            GradientStop {
                                                position: 0.52
                                                color:
                                                    service.gradientPresets[
                                                        index
                                                    ].mid
                                            }

                                            GradientStop {
                                                position: 1.0
                                                color:
                                                    service.gradientPresets[
                                                        index
                                                    ].end
                                            }
                                        }

                                        border.width:
                                            service.gradientIndex === index
                                            ? 2
                                            : 1

                                        border.color:
                                            service.gradientIndex === index
                                            ? Theme.white
                                            : Qt.alpha(Theme.white, 0.18)
                                    }

                                    Rectangle {
                                        anchors.centerIn: parent

                                        width: 44
                                        height: 44
                                        radius: width / 2

                                        color: "transparent"

                                        border.width:
                                            service.gradientIndex === index
                                            ? 1
                                            : 0

                                        border.color:
                                            Qt.alpha(
                                                Theme.white,
                                                0.30
                                            )
                                    }

                                    MouseArea {
                                        anchors.fill: parent

                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor

                                        onClicked:
                                            service.setGradient(index)
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter

                            text:
                                service.gradientPresets[
                                    service.gradientIndex
                                ].name

                            color: Theme.grey1
                            font.family: Theme.fontMain
                            font.pixelSize: 10
                        }
                    }
                }
            }

            // ============================================================
            // INPUT
            // ============================================================

            Rectangle {
                visible: !panel.settingsOpen
                Layout.fillWidth: true
                Layout.preferredHeight: 36

                radius: height / 2

                color: Qt.alpha(
                    Theme.bg1,
                    0.72
                )

                border.width: 1

                border.color:
                    input.activeFocus
                    ? Qt.alpha(Theme.white, 0.18)
                    : Qt.alpha(Theme.white, 0.10)

                Text {
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                        leftMargin: 14
                    }

                    visible: input.text.length === 0

                    text:
                        service.backendReady
                        ? (
                            service.busy
                            ? "Xavion is thinking…"
                            : "Ask Xavion..."
                        )
                        : "Starting Xavion…"

                    color: Theme.grey1

                    font.family: Theme.fontMain
                    font.pixelSize: 12
                }

                TextInput {
                    id: input

                    anchors {
                        left: parent.left
                        right: sendButton.left

                        top: parent.top
                        bottom: parent.bottom

                        leftMargin: 14
                        rightMargin: 8
                    }

                    enabled:
                        service.backendReady
                        && !service.busy

                    color: Theme.white

                    selectionColor:
                        Qt.alpha(
                            Theme.blue,
                            0.45
                        )

                    selectedTextColor:
                        Theme.white

                    font.family: Theme.fontMain
                    font.pixelSize: 12

                    verticalAlignment:
                        TextInput.AlignVCenter

                    clip: true

                    onAccepted:
                        panel.submitMessage()

                    Keys.onEscapePressed: function(event) {
                        panel.closePanel()
                        event.accepted = true
                    }
                }

                Item {
                    id: sendButton

                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        rightMargin: 4
                    }

                    width: 28
                    height: 28

                    Rectangle {
                        anchors.fill: parent

                        radius: width / 2

                        opacity:
                            service.backendReady
                            && !service.busy
                            && input.text.trim().length > 0
                            ? 1.0
                            : 0.34

                        gradient: Gradient {
                            orientation: Gradient.Horizontal

                            GradientStop {
                                position: 0.0
                                color: service.gradientStart
                            }

                            GradientStop {
                                position: 0.52
                                color: service.gradientMid
                            }

                            GradientStop {
                                position: 1.0
                                color: service.gradientEnd
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: 1

                        text: "󰁝"

                        color: Theme.white

                        font.family: Theme.fontIcons
                        font.pixelSize: 15
                    }

                    MouseArea {
                        id: sendMouse

                        anchors.fill: parent
                        hoverEnabled: true

                        cursorShape:
                            service.backendReady
                            && !service.busy
                            && input.text.trim().length > 0
                            ? Qt.PointingHandCursor
                            : Qt.ArrowCursor

                        onClicked:
                            panel.submitMessage()
                    }
                }
            }
        }
    }

    Connections {
        target: service

        function onStreamUpdated() {
            Qt.callLater(function() {
                messageList.positionViewAtEnd()
            })
        }

        function onBackendReadyChanged() {
            if (service.backendReady) {
                Qt.callLater(function() {
                    input.forceActiveFocus()
                })
            }
        }

        function onAwaitingFirstChunkChanged() {
            if (service.awaitingFirstChunk) {
                Qt.callLater(function() {
                    messageList.positionViewAtEnd()
                })
            }
        }
    }
}
