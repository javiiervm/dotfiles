import QtQuick
import QtQuick.Effects
import ".."

Rectangle {
    id: root

    property color glassTint: Glass.tint
    property real glassOpacity: Glass.opacity
    property real glassRadius: Glass.radius

    property bool showBorder: true
    property bool showHighlight: true

    // The material is controlled by Glass.opacity even when a caller overrides
    // glassOpacity for hover, selection or an alert. Existing values were tuned
    // against 0.38, the original global opacity. Preserve their relative look.
    // Zero stays zero (important for Xavion's custom masked background).
    readonly property real effectiveGlassOpacity: {
        if (glassOpacity <= 0)
            return 0
        if (Math.abs(glassOpacity - Glass.opacity) < 0.000001)
            return Math.max(0, Math.min(1, Glass.opacity))
        return Math.max(0, Math.min(1, glassOpacity * Glass.opacity / 0.38))
    }

    color: Qt.alpha(glassTint, effectiveGlassOpacity)
    radius: glassRadius

    border.width: showBorder ? Glass.borderWidth : 0
    border.color: Glass.borderColor

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
