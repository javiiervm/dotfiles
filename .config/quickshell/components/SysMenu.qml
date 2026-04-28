import QtQuick
import QtQuick.Layouts
import ".."

Rectangle {
    id: menuRoot
    property string title: ""
    property string info1: ""
    property string info2: ""
    property color accent: "#ffffff"
    property bool isOpen: false

    // ANCLAJE CORREGIDO: Pegado a la parte superior de su contenedor
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: 85

    color: "#F20D0D0D"
    radius: 15; border.color: "#1Affffff"; border.width: 1

    opacity: isOpen ? 1 : 0
    scale: isOpen ? 1 : 0.4
    transformOrigin: Item.Top

    Behavior on opacity { NumberAnimation { duration: 250 } }
    Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutBack; easing.amplitude: 1.2 } }

    ColumnLayout {
        anchors.fill: parent; anchors.margins: 15; spacing: 5
        Text { text: title; color: accent; font.bold: true; font.family: Theme.fontMain; font.pixelSize: 12; Layout.fillWidth: true }
        Rectangle { Layout.fillWidth: true; height: 1; color: "#1Affffff" }
        Text { text: info1; color: "#bbffffff"; font.family: Theme.fontMain; font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideRight }
        Text { text: info2; color: "#bbffffff"; font.family: Theme.fontMain; font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideRight }
    }
}