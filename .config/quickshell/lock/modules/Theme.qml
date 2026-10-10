import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

QtObject {
    // Lockscreen is another Quickshell configuration. Its palette is read
    // from the real Theme.qml and Glass.qml of the main desktop shell.
    // Filesystem events only: no interval timer or background process.
    property FileView themeSource: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/Theme.qml"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }

    property FileView glassSource: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/Glass.qml"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }

    function readColor(view, name, fallback) {
        var source = view.text()
        var rx = new RegExp("^\\s*readonly\\s+property\\s+color\\s+"
                           + name + "\\s*:\\s*['\"](#[0-9a-fA-F]{6})['\"]", "m")
        var found = source.match(rx)
        return found ? found[1] : fallback
    }

    function readString(name, fallback) {
        var source = themeSource.text()
        var rx = new RegExp("^\\s*readonly\\s+property\\s+string\\s+"
                           + name + "\\s*:\\s*['\"]([^'\"]+)['\"]", "m")
        var found = source.match(rx)
        return found ? found[1] : fallback
    }

    function readGlassOpacity() {
        var source = glassSource.text()
        var found = source.match(/^\s*readonly\s+property\s+real\s+opacity\s*:\s*([0-9]+(?:\.[0-9]+)?)/m)
        if (!found) return 0.38
        var value = Number(found[1])
        return isFinite(value) ? Math.max(0, Math.min(1, value)) : 0.38
    }

    readonly property color bg0: readColor(themeSource, "bg0", "#050505")
    readonly property color fg: readColor(themeSource, "fg", "#abb2bf")
    readonly property color blue: readColor(themeSource, "blue", "#61afef")
    readonly property color red: readColor(themeSource, "red", "#e08c75")
    readonly property color grey1: readColor(themeSource, "grey1", "#828997")
    readonly property color white: readColor(themeSource, "white", "#ffffff")
    readonly property color bgGlass: Qt.alpha(
        readColor(glassSource, "tint", "#101013"), readGlassOpacity())

    readonly property string fontMain: readString("fontMain", "Adwaita Sans")
    readonly property string fontIcons: readString("fontIcons", "CaskaydiaCove Nerd Font Propo")

    property real scale: 1.25
}
