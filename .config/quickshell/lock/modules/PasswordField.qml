import QtQuick
import Quickshell.Services.Pam
import "../../"

Item {
    id: root
    implicitWidth: 260
    implicitHeight: 46

    signal unlocked()

    property bool authenticating: false
    property string errorText: ""

    PamContext {
        id: pam

        onPamMessage: {
            if (responseRequired) {
                pam.respond(field.text)
            }
        }

        onCompleted: result => {
            root.authenticating = false
            if (result === PamResult.Success) {
                root.errorText = ""
                root.unlocked()
            } else {
                root.errorText = "Incorrect password" //[cite: 15]
                field.text = ""
                shake.start()
            }
        }

        onError: error => {
            root.authenticating = false
            root.errorText = "PAM Error: " + PamError.toString(error)
            field.text = ""
        }
    }

    Rectangle {
        id: box
        anchors.fill: parent
        radius: 23
        color: Qt.alpha(Theme.bg0, 0.4)
        border.width: 1
        border.color: Qt.alpha(Theme.white, 0.2)

        SequentialAnimation {
            id: shake
            NumberAnimation { target: box; property: "anchors.horizontalCenterOffset"; to: -8; duration: 40 }
            NumberAnimation { target: box; property: "anchors.horizontalCenterOffset"; to: 8; duration: 40 }
            NumberAnimation { target: box; property: "anchors.horizontalCenterOffset"; to: 0; duration: 40 }
        }

        Row {
            anchors.fill: parent
            anchors.margins: 4
            spacing: 8

            Text {
                text: ""
                color: Theme.white
                font.pixelSize: 16
                font.family: Theme.fontIcons
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: 8
            }

            TextInput {
                id: field
                width: parent.width - 70
                anchors.verticalCenter: parent.verticalCenter
                echoMode: TextInput.Password
                color: Theme.white
                font.pixelSize: 14
                font.family: Theme.fontMain
                focus: true
                enabled: !root.authenticating //[cite: 15]

                Text {
                    text: root.errorText !== "" ? root.errorText : "Enter your password" //[cite: 15]
                    color: root.errorText !== "" ? Theme.red : Theme.grey1
                    font.pixelSize: 13
                    font.family: Theme.fontMain
                    visible: field.text.length === 0
                }

                onAccepted: {
                    if (text.length === 0 || root.authenticating) return
                    root.authenticating = true
                    root.errorText = ""
                    pam.start()
                }
            }
        }
    }
}