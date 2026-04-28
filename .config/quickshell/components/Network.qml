import QtQuick
import QtQuick.Layouts
import ".."

Rectangle {
    property bool showContainer: true
    property string ssid: ""
    
    color: showContainer ? Theme.bg1 : "transparent"
    border.color: showContainer ? Theme.bg2 : "transparent"
    border.width: 1
    radius: 15
    
    Layout.preferredHeight: 28
    Layout.preferredWidth: netRow.implicitWidth + 20

    RowLayout {
        id: netRow
        anchors.centerIn: parent
        spacing: 6
        Text {
            text: ssid === "" ? "󰖪" : ""
            color: Theme.purple
            font.family: Theme.fontIcons; font.pixelSize: 14
        }
        Text {
            text: ssid === "" ? "Desconectado" : ssid
            color: Theme.fg
            font.family: Theme.fontMain; font.pixelSize: 12; font.bold: true
        }
    }
}