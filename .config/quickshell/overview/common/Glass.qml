import QtQuick
import Quickshell
import Quickshell.Io

pragma Singleton

QtObject {
    // Overview runs as an independent Quickshell config. Read the source
    // material from the main dotfiles instead of maintaining a stale copy.
    // FileView is event-driven (filesystem notifications, no polling/daemon).
    property FileView sharedGlassFile: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/Glass.qml"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }

    function readShared(type, name, fallback) {
        var source = sharedGlassFile.text()
        var rx = new RegExp("^\\s*readonly\\s+property\\s+" + type
                            + "\\s+" + name + "\\s*:\\s*([^\\r\\n]+)", "m")
        var found = source.match(rx)
        if (!found)
            return fallback

        var literal = found[1].trim()
        if (type === "color") {
            var colorMatch = literal.match(/^['"](#[0-9a-fA-F]{6})['"]/)
            return colorMatch ? colorMatch[1] : fallback
        }
        if (type === "bool")
            return literal === "true" ? true : literal === "false" ? false : fallback
        var numberMatch = literal.match(/^[-+]?(?:[0-9]+(?:[.][0-9]*)?|[.][0-9]+)/)
        var number = numberMatch ? Number(numberMatch[0]) : NaN
        return isFinite(number) ? number : fallback
    }
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

    readonly property color tint: readShared('color', 'tint', '#101013')

    // 0 = transparente
    // 1 = opaco
    readonly property real opacity: readShared('real', 'opacity', 0.38)

    readonly property color background:
        Qt.alpha(tint, opacity)


    // ─────────────────────────────────────────────────────
    // Background blur
    // ─────────────────────────────────────────────────────

    readonly property bool blurEnabled: readShared('bool', 'blurEnabled', true)


    // ─────────────────────────────────────────────────────
    // Colour treatment
    // ─────────────────────────────────────────────────────

    // Para efectos QML internos / futuros shaders
    readonly property real saturation: readShared('real', 'saturation', 0.15)
    readonly property real brightness: readShared('real', 'brightness', 0.02)
    readonly property real contrast: readShared('real', 'contrast', 0.03)


    // ─────────────────────────────────────────────────────
    // Border
    // ─────────────────────────────────────────────────────

    readonly property real borderOpacity: readShared('real', 'borderOpacity', 0.2)
    readonly property real borderWidth: readShared('real', 'borderWidth', 1.0)

    readonly property color borderColor:
        Qt.alpha("#ffffff", borderOpacity)


    // ─────────────────────────────────────────────────────
    // Highlight
    // ─────────────────────────────────────────────────────

    readonly property real highlightOpacity: readShared('real', 'highlightOpacity', 0.10)

    readonly property color highlightColor:
        Qt.alpha("#ffffff", highlightOpacity)


    // ─────────────────────────────────────────────────────
    // Shadow
    // ─────────────────────────────────────────────────────

    readonly property real shadowOpacity: readShared('real', 'shadowOpacity', 0.30)
    readonly property real shadowBlur: readShared('real', 'shadowBlur', 0.65)
    readonly property real shadowRadius: readShared('real', 'shadowRadius', 24)

    readonly property color shadowColor:
        Qt.alpha("#000000", shadowOpacity)


    // ─────────────────────────────────────────────────────
    // Geometry
    // ─────────────────────────────────────────────────────

    readonly property int radiusSmall: readShared('int', 'radiusSmall', 10)
    readonly property int radius: readShared('int', 'radius', 16)
    readonly property int radiusLarge: readShared('int', 'radiusLarge', 24)
}