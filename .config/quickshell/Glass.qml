import QtQuick

pragma Singleton

QtObject {
    /*
     * =====================================================
     *                  LIQUID GLASS
     * =====================================================
     *
     * Este archivo controla exclusivamente el aspecto
     * de las superficies Quickshell.
     */

    // ─────────────────────────────────────────────────────
    // Base material
    // ─────────────────────────────────────────────────────

    readonly property color tint: '#101013'

    // 0 = transparente
    // 1 = opaco
    readonly property real opacity: 0.38

    readonly property color background:
        Qt.alpha(tint, opacity)


    // ─────────────────────────────────────────────────────
    // Background blur
    // ─────────────────────────────────────────────────────

    readonly property bool blurEnabled: true


    // ─────────────────────────────────────────────────────
    // Colour treatment
    // ─────────────────────────────────────────────────────

    // Para efectos QML internos / futuros shaders
    readonly property real saturation: 0.15
    readonly property real brightness: 0.02
    readonly property real contrast: 0.03


    // ─────────────────────────────────────────────────────
    // Border
    // ─────────────────────────────────────────────────────

    readonly property real borderOpacity: 0.2
    readonly property real borderWidth: 1.0

    readonly property color borderColor:
        Qt.alpha("#ffffff", borderOpacity)


    // ─────────────────────────────────────────────────────
    // Highlight
    // ─────────────────────────────────────────────────────

    readonly property real highlightOpacity: 0.10

    readonly property color highlightColor:
        Qt.alpha("#ffffff", highlightOpacity)


    // ─────────────────────────────────────────────────────
    // Shadow
    // ─────────────────────────────────────────────────────

    readonly property real shadowOpacity: 0.30
    readonly property real shadowBlur: 0.65
    readonly property real shadowRadius: 24

    readonly property color shadowColor:
        Qt.alpha("#000000", shadowOpacity)


    // ─────────────────────────────────────────────────────
    // Geometry
    // ─────────────────────────────────────────────────────

    readonly property int radiusSmall: 10
    readonly property int radius: 16
    readonly property int radiusLarge: 24
}