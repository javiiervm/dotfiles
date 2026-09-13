import QtQuick

Rectangle {
    id: root

    property real uiScale: 1.25
    property alias text: input.text

    signal submitted(string password)
    signal edited()

    width: 260 * uiScale
    height: 42 * uiScale
    radius: 21 * uiScale

    color: "#141e1e24"
    border.color: input.activeFocus ? "#61afef" : "#26ffffff"
    border.width: 1

    Behavior on border.color {
        ColorAnimation { duration: 150 }
    }

    function clearAndFocus() {
        input.text = ""
        input.forceActiveFocus()
    }

    function forceInputFocus() {
        input.forceActiveFocus()
    }

    TextInput {
        id: input

        anchors.fill: parent
        anchors.leftMargin: 16 * root.uiScale
        anchors.rightMargin: 16 * root.uiScale

        verticalAlignment: TextInput.AlignVCenter
        horizontalAlignment: TextInput.AlignHCenter

        echoMode: TextInput.Password
        passwordCharacter: "•"

        color: "#ffffff"
        selectionColor: "#61afef"
        selectedTextColor: "#050505"

        font.family: "Adwaita Sans"
        font.pixelSize: 13 * root.uiScale

        focus: true
        clip: true

        onTextChanged: root.edited()
        onAccepted: root.submitted(text)
    }

    Text {
        anchors.fill: parent
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignHCenter

        text: "Enter your password"
        font.family: "Adwaita Sans"
        font.pixelSize: 13 * root.uiScale
        color: "#66ffffff"

        visible: input.text.length === 0
    }
}
