import QtQuick
import QtQuick.Layouts
import ".."

Rectangle {
    property bool showContainer: true
    property bool dnd: false
    property int count: 0
    property bool hasUnread: false // AÑADIDO

    color: "transparent"
    width: 26; height: 26
    Text {
        anchors.centerIn: parent
        // AÑADIDO: Evaluamos hasUnread en lugar de count > 0
        text: dnd ? (hasUnread ? "󰂠" : "󰪓") : (hasUnread ? "󱅫" : "󰂜")
        color: hasUnread ? Theme.white : Theme.grey1
        font.family: Theme.fontIcons; font.pixelSize: 18
    }
}