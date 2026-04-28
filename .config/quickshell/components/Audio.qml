import QtQuick
import QtQuick.Layouts
import ".."

Rectangle {
    property bool showContainer: true
    property int volume: 0
    color: showContainer ? "#22ffffff" : "transparent"
    radius: 12; Layout.preferredHeight: 26; Layout.preferredWidth: row.implicitWidth + 16
    RowLayout {
        id: row; anchors.centerIn: parent; spacing: 6
        Text { text: ""; color: Theme.yellow; font.family: Theme.fontIcons; font.pixelSize: 14 }
        Text { text: volume + "%"; color: Theme.fg; font.family: Theme.fontMain; font.pixelSize: 12; font.bold: true }
    }
}