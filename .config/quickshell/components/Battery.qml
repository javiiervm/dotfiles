import QtQuick
import QtQuick.Layouts
import ".."

Rectangle {
    id: batteryRoot
    property int percentage: 0
    property bool charging: false
    
    Layout.preferredHeight: 20; Layout.preferredWidth: 34; Layout.alignment: Qt.AlignVCenter
    radius: height / 2; color: Theme.grey1 
    
    readonly property color fillColor: charging ? "#2ecc71" : (percentage < 21 ? '#f13857' : Theme.fg)
    property real fillWidth: width * (Math.max(0, Math.min(percentage, 100)) / 100.0)
    Behavior on fillWidth { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }

    Item {
        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
        width: batteryRoot.fillWidth; clip: true 
        
        Rectangle {
            width: batteryRoot.width; height: batteryRoot.height; radius: batteryRoot.radius
            color: batteryRoot.fillColor
            Behavior on color { ColorAnimation { duration: 100 } }
        }
    }

    RowLayout {
        anchors.centerIn: parent; spacing: 1
        Text { text: "󱐋"; color: Theme.bg0; font.family: Theme.fontIcons; font.pixelSize: 12; visible: charging }
        Text { text: percentage; color: Theme.bg0; font.family: Theme.fontMain; font.pixelSize: 12; font.bold: true }
    }
}