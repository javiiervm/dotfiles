import QtQuick
import "." as Local
import "../../"

Rectangle {
    id: root
    width: 260 * Theme.scale
    height: 42 * Theme.scale
    radius: 21 * Theme.scale
    color: Qt.alpha(Theme.white, 0.08)
    border.color: input.activeFocus ? Theme.blue : Qt.alpha(Theme.white, 0.15)
    border.width: 1

    Behavior on border.color { ColorAnimation { duration: 150 } }

    signal unlocked()

    // Campo de entrada de texto
    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 16 * Theme.scale
        anchors.rightMargin: 16 * Theme.scale
        verticalAlignment: TextInput.AlignVCenter
        horizontalAlignment: TextInput.AlignHCenter // Centra los puntos de la contraseña
        echoMode: TextInput.Password
        passwordCharacter: "•"
        color: Theme.white
        font.family: Theme.fontMain
        font.pixelSize: 13 * Theme.scale
        focus: true
        clip: true

        onAccepted: {
            // Invoca la señal de desbloqueo al pulsar Enter
            root.unlocked()
        }
    }

    // Texto de ayuda (Placeholder)
    Text {
        anchors.fill: parent
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter // Centra el texto "Enter your password"
        text: "Enter your password"
        font.family: Theme.fontMain
        font.pixelSize: 13 * Theme.scale
        color: Qt.alpha(Theme.white, 0.4)
        visible: input.text.length === 0
    }
}