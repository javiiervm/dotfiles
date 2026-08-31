import QtQuick
import QtQuick.Effects
import "."

Rectangle {
    id: root

    property color glassTint: Glass.tint
    property real glassOpacity: Glass.opacity

    property real glassRadius: Glass.radius

    property bool showBorder: true
    property bool showHighlight: true

    color: Qt.alpha(glassTint, glassOpacity)

    radius: glassRadius

    border.width: showBorder ? Glass.borderWidth : 0
    border.color: Glass.borderColor


    // Highlight superior muy sutil.
    // Esto ayuda bastante a acercarse al material de macOS.

    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top

            leftMargin: root.radius / 2
            rightMargin: root.radius / 2
        }

        height: 1

        visible: root.showHighlight

        color: Glass.highlightColor
    }
}