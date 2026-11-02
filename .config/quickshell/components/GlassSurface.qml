import QtQuick
import QtQuick.Effects
import ".."

Rectangle {
    id: root

    // Keep the original public API. Existing components can
    // still override the tint, opacity, radius and borders.
    property color glassTint: Glass.tint
    property real glassOpacity: Glass.opacity
    property real glassRadius: Glass.radius

    property bool showBorder: true
    property bool showHighlight: true

    // Existing per-tile opacity values were calibrated for 0.38.
    // Preserve their relative strengths when the global material
    // opacity changes, without breaking explicitly transparent
    // surfaces (notably the custom-masked Xavion panel).
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

    // Soft vertical reflection over the translucent base.
    // Rounded rectangles avoid the square corners that a tiled
    // texture would introduce. This layer is static and requires
    // neither a shader nor a background render loop.
    Rectangle {
        id: acrylicLighting
        anchors.fill: parent
        radius: root.radius
        visible: root.effectiveGlassOpacity > 0
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Qt.alpha("#ffffff", Glass.sheenTopOpacity)
            }
            GradientStop {
                position: 0.36
                color: Qt.alpha("#ffffff", Glass.sheenMidOpacity)
            }
            GradientStop {
                position: 0.72
                color: "transparent"
            }
            GradientStop {
                position: 1.0
                color: Qt.alpha("#000000", Glass.sheenBottomOpacity)
            }
        }
    }

    // Thin, fully rounded inset rim rather than the former
    // straight 1px line. It also works on pill-shaped surfaces.
    Rectangle {
        id: innerHighlight
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, root.radius - 1)
        color: "transparent"
        border.width: 1
        border.color: Glass.highlightColor
        visible: root.showHighlight && root.effectiveGlassOpacity > 0
    }
}
