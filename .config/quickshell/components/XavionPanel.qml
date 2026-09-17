import QtQuick
import QtQuick.Layouts

import Quickshell
import Quickshell.Wayland

import ".."

PanelWindow {
    id: panel

    required property var service

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
        })
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

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                spacing: 10

                Image {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30

                    source: "../assets/xavion/idle.png"
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        text: "Xavion"
                        color: Theme.white
                        font.family: Theme.fontMain
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Text {
                        text: service.statusText

                        color: service.busy
                            ? Theme.orange
                            : service.backendReady
                                ? Theme.green
                                : Theme.grey1

                        font.family: Theme.fontMain
                        font.pixelSize: 10
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                Item {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28

                    Text {
                        anchors.centerIn: parent
                        text: "󰅖"

                        color: closeMouse.containsMouse
                            ? Theme.white
                            : Theme.grey1

                        font.family: Theme.fontIcons
                        font.pixelSize: 14
                    }

                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: service.closePanel()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Qt.alpha(Theme.white, 0.08)
            }

            Item {
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
                        height: bubble.height + 6

                        Rectangle {
                            id: bubble

                            anchors.right:
                                messageDelegate.fromUser
                                ? parent.right
                                : undefined

                            anchors.left:
                                messageDelegate.fromUser
                                ? undefined
                                : parent.left

                            width:
                                messageDelegate.fromUser
                                ? messageList.width * 0.72
                                : messageList.width * 0.88

                            height: messageText.implicitHeight + 18
                            radius: 14

                            color:
                                messageDelegate.fromUser
                                ? Qt.alpha(Theme.blue, 0.15)
                                : Qt.alpha(Theme.white, 0.055)

                            border.width: 1

                            border.color:
                                messageDelegate.fromUser
                                ? Qt.alpha(Theme.blue, 0.26)
                                : Qt.alpha(Theme.white, 0.08)

                            Text {
                                id: messageText

                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top
                                    margins: 9
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
                                textFormat: Text.PlainText
                            }
                        }
                    }

                    onCountChanged: {
                        Qt.callLater(function() {
                            messageList.positionViewAtEnd()
                        })
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 10

                    visible:
                        service.messages.count === 0

                    Image {
                        anchors.horizontalCenter: parent.horizontalCenter

                        width: 54
                        height: 54

                        source: "../assets/xavion/idle.png"
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter

                        text: service.backendRunning
                            ? (
                                service.backendReady
                                ? "Ask Xavion anything"
                                : "Starting Xavion…"
                            )
                            : "Ask Xavion anything"

                        color: Theme.grey1
                        font.family: Theme.fontMain
                        font.pixelSize: 12
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter

                        visible: service.lastError.length > 0
                        width: Math.min(320, implicitWidth)
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap

                        text: service.lastError
                        color: Theme.red
                        font.family: Theme.fontMain
                        font.pixelSize: 10
                    }
                }

                Rectangle {
                    anchors.right: parent.right

                    width: 3

                    height: Math.max(
                        24,
                        messageList.height
                        * messageList.visibleArea.heightRatio
                    )

                    y:
                        messageList.visibleArea.yPosition
                        * (parent.height - height)

                    radius: width / 2

                    visible:
                        messageList.contentHeight
                        > messageList.height

                    color: Qt.alpha(Theme.white, 0.22)
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Qt.alpha(Theme.white, 0.08)
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 42

                radius: 13
                color: Qt.alpha(Theme.bg1, 0.72)

                border.width: 1

                border.color:
                    input.activeFocus
                    ? Qt.alpha(Theme.orange, 0.55)
                    : Qt.alpha(Theme.white, 0.10)

                Text {
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                        leftMargin: 13
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
                        leftMargin: 13
                        rightMargin: 8
                    }

                    enabled:
                        service.backendReady
                        && !service.busy

                    color: Theme.white
                    selectionColor: Qt.alpha(Theme.blue, 0.45)
                    selectedTextColor: Theme.white

                    font.family: Theme.fontMain
                    font.pixelSize: 12

                    verticalAlignment: TextInput.AlignVCenter
                    clip: true

                    onAccepted: panel.submitMessage()

                    Keys.onEscapePressed: function(event) {
                        service.closePanel()
                        event.accepted = true
                    }
                }

                Item {
                    id: sendButton

                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        rightMargin: 6
                    }

                    width: 30
                    height: 30

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2

                        color:
                            sendMouse.containsMouse
                            && input.text.trim().length > 0
                            && service.backendReady
                            && !service.busy
                            ? Qt.alpha(Theme.orange, 0.25)
                            : Qt.alpha(Theme.white, 0.06)

                        border.width: 1
                        border.color: Qt.alpha(Theme.white, 0.10)
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "󰒊"

                        color:
                            input.text.trim().length > 0
                            && service.backendReady
                            && !service.busy
                            ? Theme.white
                            : Theme.grey1

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
                            ? Qt.PointingHandCursor
                            : Qt.ArrowCursor

                        onClicked: panel.submitMessage()
                    }
                }
            }
        }
    }

    Connections {
        target: XavionService

        function onStreamUpdated() {
            Qt.callLater(function() {
                messageList.positionViewAtEnd()
            })
        }

        function onBackendReadyChanged() {
            if (
                panel.visible
                && service.backendReady
            ) {
                Qt.callLater(function() {
                    input.forceActiveFocus()
                })
            }
        }
    }
}
