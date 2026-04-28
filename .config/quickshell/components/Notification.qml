import QtQuick
import QtQuick.Layouts
import ".."

Rectangle {
    property bool showContainer: true
    property bool dnd: false
    property int count: 0
    color: "transparent"
    width: 26; height: 26
    Text {
        anchors.centerIn: parent
        text: dnd ? (count > 0 ? "󰂠" : "󰪓") : (count > 0 ? "󱅫" : "󰂜")
        color: count > 0 ? Theme.white : Theme.grey1
        font.family: Theme.fontIcons; font.pixelSize: 18
    }
}