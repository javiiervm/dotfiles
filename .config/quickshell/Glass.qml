import QtQuick

pragma Singleton

QtObject {
    /*
     * =====================================================
     *              WINDOWS-INSPIRED ACRYLIC
     * =====================================================
     *
     * Single material used by the Quickshell surfaces.
     * The real backdrop blur is provided by Quickshell's
     * BackgroundEffect + the Hyprland compositor.
     *
     * This singleton controls only the translucent tint,
     * fine lighting and edges. It deliberately leaves the
     * original component geometry and animations untouched.
     */

    // ─────────────────────────────────────────────────────
    // Base material: dark, slightly blue-tinted acrylic
    // ─────────────────────────────────────────────────────

    // Windows-style slate blue. Adjust this one value to
    // adapt the material to a different wallpaper palette.
    readonly property color tint: "#162c42"

    // 0 = transparent; 1 = opaque.
    // Moderate opacity allows the blurred wallpaper to show.
    readonly property real opacity: 0.56

    readonly property color background: Qt.alpha(tint, opacity)

    // ─────────────────────────────────────────────────────
    // Real background blur (owned by compositor / windows)
    // ─────────────────────────────────────────────────────

    readonly property bool blurEnabled: true

    // These parameters remain available to QML experiments.
    // The actual Hyprland blur strength is configured there.
    readonly property real saturation: 0.15
    readonly property real brightness: 0.02
    readonly property real contrast: 0.03

    // ─────────────────────────────────────────────────────
    // Acrylic lighting
    // ─────────────────────────────────────────────────────

    // Very soft, static illumination. No shaders or timers.
    readonly property real sheenTopOpacity: 0.075
    readonly property real sheenMidOpacity: 0.026
    readonly property real sheenBottomOpacity: 0.036

    // ─────────────────────────────────────────────────────
    // Border: thin frosted edge
    // ─────────────────────────────────────────────────────

    readonly property real borderOpacity: 0.24
    readonly property real borderWidth: 1.0
    readonly property color borderColor: Qt.alpha("#e6f4ff", borderOpacity)

    // ─────────────────────────────────────────────────────
    // Inner highlight, rounded to match the material
    // ─────────────────────────────────────────────────────

    readonly property real highlightOpacity: 0.085
    readonly property color highlightColor: Qt.alpha("#ffffff", highlightOpacity)

    // ─────────────────────────────────────────────────────
    // Shadow (retained for components which use it)
    // ─────────────────────────────────────────────────────

    readonly property real shadowOpacity: 0.30
    readonly property real shadowBlur: 0.65
    readonly property real shadowRadius: 24
    readonly property color shadowColor: Qt.alpha("#000000", shadowOpacity)

    // ─────────────────────────────────────────────────────
    // Original geometry
    // ─────────────────────────────────────────────────────

    readonly property int radiusSmall: 10
    readonly property int radius: 16
    readonly property int radiusLarge: 24
}
