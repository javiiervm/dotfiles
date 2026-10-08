import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Standalone, on-demand Quickshell panel launched from the existing Launcher.
// The entire process terminates on Close or Escape: no resident helper.
ShellRoot {
    id: root

    property var values: ({})
    property bool busy: true
    property bool dirty: false
    property bool failed: false
    property string statusMessage: "Reading your current configuration..."
    property int currentTab: 0

    // One-shot snapshot of the ACTUAL ../Theme.qml and ../Glass.qml properties.
    // The backend reads the originals on launch, so this independent config
    // does not attempt to import QML singletons outside its config boundary.
    // These harmless fallback colors are replaced as soon as read completes.
    property var paletteTheme: ({
        white: "#ffffff", bg0: "#050505", blue: "#61afef", red: "#e08c75",
        yellow: "#e5c07b", grey1: "#828997",
        fontMain: "Adwaita Sans", fontIcons: "CaskaydiaCove Nerd Font Propo"
    })
    property var paletteGlass: ({
        tint: "#101013", opacity: 0.38, blurEnabled: true, borderOpacity: 0.2,
        borderWidth: 1, highlightOpacity: 0.10,
        radius: 16, radiusSmall: 10, radiusLarge: 24
    })

    // An unfinished color/number while typing must never reach QColor/Qt.alpha.
    function boundedAlpha(value, fallback) {
        if (value === undefined || value === null || String(value).trim() === "")
            return fallback
        var n = Number(value)
        return isFinite(n) && n >= 0 && n <= 1 ? n : fallback
    }
    readonly property color glassBackground: Qt.alpha(
        /^#[0-9a-fA-F]{6}$/.test(String(root.values.glass_tint)) ? root.values.glass_tint : root.paletteGlass.tint,
        boundedAlpha(root.values.glass_opacity, root.paletteGlass.opacity)
    )
    readonly property color glassBorderColor: Qt.alpha(root.paletteTheme.white,
        boundedAlpha(root.values.glass_border, root.paletteGlass.borderOpacity))
    readonly property color glassHighlightColor: Qt.alpha(root.paletteTheme.white,
        root.paletteGlass.highlightOpacity)


    readonly property var primaryScreen: {
        const screens = Quickshell.screens
        for (var i = 0; i < screens.length; ++i)
            if (screens[i].name === "eDP-1") return screens[i]
        for (var j = 0; j < screens.length; ++j)
            if (screens[j].name === "HDMI-A-1") return screens[j]
        return screens.length > 0 ? screens[0] : null
    }

    readonly property var hyprFields: [
        {key: "hypr_blur_enabled", title: "Window blur", description: "Blur the background behind translucent application windows.", kind: "toggle"},
        {key: "hypr_blur_size", title: "Blur size", description: "Kernel size (1–12). Lower values usually reduce GPU work.", kind: "number"},
        {key: "hypr_blur_passes", title: "Blur passes", description: "Number of blur passes (1–5). More passes cost more GPU time.", kind: "number"},
        {key: "hypr_active_opacity", title: "Focused window opacity", description: "1 = opaque, 0.35 = translucent. Currently 0.85 in your repo.", kind: "number"},
        {key: "hypr_inactive_opacity", title: "Unfocused window opacity", description: "Transparency for windows without focus (0.35–1).", kind: "number"},
        {key: "hypr_rounding", title: "Window corner radius", description: "Rounded window corners, in pixels (0–30).", kind: "number"},
        {key: "hypr_gaps_in", title: "Inner window gap", description: "Space between tiled windows (0–30 pixels).", kind: "number"},
        {key: "hypr_border_size", title: "Window border width", description: "Border thickness (0–8 pixels).", kind: "number"},
        {key: "hypr_animations", title: "Window animations", description: "Enable or disable Hyprland animations globally.", kind: "toggle"}
    ]

    readonly property var quickFields: [
        {key: "glass_tint", title: "Glass tint", description: "Base tint used by your Quickshell glass surfaces (#RRGGBB).", kind: "color"},
        {key: "glass_opacity", title: "Glass opacity", description: "Transparency of glass surfaces, 0.05–1. Higher is more opaque.", kind: "number"},
        {key: "glass_blur", title: "Quickshell background blur", description: "Toggle the BackgroundEffect blur region on supported surfaces.", kind: "toggle"},
        {key: "glass_border", title: "Glass border opacity", description: "Opacity of white borders around glass elements (0–1).", kind: "number"},
        {key: "glass_radius", title: "Glass corner radius", description: "Default radius used by shared glass components (0–32).", kind: "number"},
        {key: "theme_accent", title: "Accent color", description: "Change Theme.qml blue, used for accents and highlights (#RRGGBB).", kind: "color"},
        {key: "theme_background", title: "Base background color", description: "Change Theme.qml bg0, used across the shell (#RRGGBB).", kind: "color"}
    ]

    function setValue(key, value) {
        var copy = Object.assign({}, root.values)
        copy[key] = value
        root.values = copy
        root.dirty = true
        root.failed = false
        root.statusMessage = "Unsaved changes"
    }

    function loadSettings() {
        if (loadProc.running || saveProc.running) return
        root.busy = true
        root.statusMessage = "Reading your current configuration..."
        loadProc.running = true
    }

    function applySettings() {
        if (root.busy || !root.dirty) return
        root.busy = true
        root.failed = false
        root.statusMessage = "Applying changes..."
        saveProc.command = ["python3", "/home/javier/.config/quickshell/settings/settings_backend.py", "apply", JSON.stringify(root.values)]
        saveProc.running = true
    }

    Process {
        id: loadProc
        command: ["python3", "/home/javier/.config/quickshell/settings/settings_backend.py", "read"]
        running: true
        stdout: SplitParser {
            onRead: (line) => {
                try {
                    var response = JSON.parse(line)
                    if (response.ok) {
                        root.values = response.values
                        if (response.appearance) {
                            root.paletteTheme = response.appearance.theme
                            root.paletteGlass = response.appearance.glass
                        }
                        root.dirty = false
                        root.failed = false
                        root.statusMessage = "Ready. Changes are written only when you press Apply."
                    } else {
                        root.failed = true
                        root.statusMessage = response.error || "Could not read your config files."
                    }
                } catch (error) {
                    root.failed = true
                    root.statusMessage = "Invalid response from settings backend."
                }
            }
        }
        onExited: (code) => {
            root.busy = false
            if (code !== 0 && !root.failed) {
                root.failed = true
                root.statusMessage = "Could not load settings. Check the backend file path."
            }
        }
    }

    Process {
        id: saveProc
        stdout: SplitParser {
            onRead: (line) => {
                try {
                    var response = JSON.parse(line)
                    if (response.ok) {
                        // Keep the preview in sync immediately after a valid save.
                        var t = Object.assign({}, root.paletteTheme)
                        t.blue = root.values.theme_accent
                        t.bg0 = root.values.theme_background
                        root.paletteTheme = t
                        var g = Object.assign({}, root.paletteGlass)
                        g.tint = root.values.glass_tint
                        g.opacity = root.values.glass_opacity
                        g.blurEnabled = root.values.glass_blur
                        g.borderOpacity = root.values.glass_border
                        g.radius = root.values.glass_radius
                        root.paletteGlass = g
                        root.dirty = false
                        root.failed = response.warning !== ""
                        root.statusMessage = response.warning || (response.changed.length
                            ? "Saved! Your desktop configuration has been updated."
                            : "Everything is already up to date.")
                    } else {
                        root.failed = true
                        root.statusMessage = response.error || "Could not save settings."
                    }
                } catch (error) {
                    root.failed = true
                    root.statusMessage = "Invalid response while saving."
                }
            }
        }
        onExited: (code) => {
            root.busy = false
            if (code !== 0 && !root.failed && root.dirty) {
                root.failed = true
                root.statusMessage = "Save failed; configuration may be unchanged."
            }
        }
    }

    PanelWindow {
        id: window
        screen: root.primaryScreen
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        visible: true
        WlrLayershell.layer: WlrLayershell.Overlay
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.keyboardFocus: WlrLayershell.OnDemand
        BackgroundEffect.blurRegion: (root.values.glass_blur === undefined ? root.paletteGlass.blurEnabled : root.values.glass_blur) ? glassBlurRegion : null

        Region { id: glassBlurRegion; item: panelCard; radius: panelCard.radius }

        FocusScope {
            id: baseFocus
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: Qt.quit()

            Rectangle {
                anchors.fill: parent
                // Dim bright applications beneath the glass, without changing
                // Glass.opacity itself; the actual card uses the shared values.
                color: Qt.alpha(root.paletteGlass.tint, 0.30)
                MouseArea { anchors.fill: parent; onClicked: Qt.quit() }
            }

            Rectangle {
                id: panelCard
                // Same material bindings as components/GlassSurface.qml,
                // without importing a QML component outside this standalone config.
                color: root.glassBackground
                radius: root.paletteGlass.radiusLarge
                border.width: root.paletteGlass.borderWidth
                border.color: root.glassBorderColor

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: panelCard.radius / 2
                    anchors.rightMargin: panelCard.radius / 2
                    height: 1
                    color: root.glassHighlightColor
                }
                width: Math.min(752, parent.width - 36)
                height: Math.min(700, parent.height - 36)
                anchors.centerIn: parent
                clip: true

                MouseArea { anchors.fill: parent }

                Column {
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 14

                    Row {
                        width: parent.width
                        height: 52
                        spacing: 12

                        Rectangle {
                            width: 45
                            height: 45
                            radius: 14
                            color: Qt.alpha(root.paletteTheme.white, 0.08)
                            border.color: Qt.alpha(root.paletteTheme.white, 0.15)
                            Text {
                                anchors.centerIn: parent
                                text: "󰒓"
                                color: root.paletteTheme.white
                                font.family: root.paletteTheme.fontIcons
                                font.pixelSize: 25
                            }
                        }
                        Column {
                            width: parent.width - 102
                            spacing: 3
                            Text {
                                text: "Dotfiles Settings"
                                color: root.paletteTheme.white
                                font.family: root.paletteTheme.fontMain
                                font.pixelSize: 23
                                font.bold: true
                            }
                            Text {
                                text: "Hyprland + Quickshell  ·  Local configuration"
                                color: Qt.alpha(root.paletteTheme.white, 0.55)
                                font.pixelSize: 11
                                font.family: root.paletteTheme.fontMain
                            }
                        }
                        Rectangle {
                            width: 34
                            height: 34
                            radius: 10
                            color: Qt.alpha(root.paletteTheme.white, closeArea.containsMouse ? 0.20 : 0.08)
                            anchors.verticalCenter: parent.verticalCenter
                            Text { anchors.centerIn: parent; text: "×"; color: root.paletteTheme.white; font.pixelSize: 23; font.family: root.paletteTheme.fontMain }
                            MouseArea {
                                id: closeArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Qt.quit()
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        height: 42
                        spacing: 9
                        Repeater {
                            model: ["Hyprland", "Quickshell"]
                            delegate: Rectangle {
                                required property int index
                                required property string modelData
                                width: (panelCard.width - 48 - 9) / 2
                                height: 40
                                radius: 11
                                color: root.currentTab === index ? Qt.alpha(root.paletteTheme.white, 0.17) : Qt.alpha(root.paletteTheme.white, 0.065)
                                border.width: 1
                                border.color: root.currentTab === index ? Qt.alpha(root.paletteTheme.white, 0.35) : Qt.alpha(root.paletteTheme.white, 0.12)
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: root.currentTab === index ? root.paletteTheme.white : Qt.alpha(root.paletteTheme.white, 0.60)
                                    font.family: root.paletteTheme.fontMain
                                    font.pixelSize: 14
                                    font.bold: root.currentTab === index
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.currentTab = index
                                }
                            }
                        }
                    }

                    Flickable {
                        id: listScroll
                        width: parent.width
                        height: Math.max(95, panelCard.height - 245)
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        contentHeight: settingsColumn.height
                        onContentHeightChanged: contentY = 0

                        Column {
                            id: settingsColumn
                            width: listScroll.width - 10
                            spacing: 9

                            Repeater {
                                model: root.currentTab === 0 ? root.hyprFields : root.quickFields
                                delegate: SettingsRow {
                                    required property var modelData
                                    width: settingsColumn.width
                                    spec: modelData
                                    enabled: !root.busy
                                    values: root.values
                                    paletteTheme: root.paletteTheme
                                    paletteGlass: root.paletteGlass
                                    onValueEdited: (settingKey, newValue) => root.setValue(settingKey, newValue)
                                }
                            }
                            Item { width: 1; height: 1 }
                        }
                    }

                    Row {
                        width: parent.width
                        height: 46
                        spacing: 12

                        Rectangle {
                            width: 132
                            height: 42
                            radius: 11
                            color: Qt.alpha(root.paletteTheme.white, discardArea.containsMouse ? 0.17 : 0.075)
                            border.color: Qt.alpha(root.paletteTheme.white, 0.16)
                            Text {
                                anchors.centerIn: parent
                                text: "Discard edits"
                                color: root.paletteTheme.white
                                font.family: root.paletteTheme.fontMain
                                font.pixelSize: 13
                            }
                            MouseArea {
                                id: discardArea
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                enabled: !root.busy
                                hoverEnabled: true
                                onClicked: root.loadSettings()
                            }
                        }

                        Item { width: parent.width - 132 - 172 - 24; height: 1 }

                        Rectangle {
                            width: 172
                            height: 42
                            radius: 11
                            color: root.busy || !root.dirty ? Qt.alpha(root.paletteTheme.white, 0.13) : (applyArea.containsMouse ? Qt.lighter(root.paletteTheme.blue, 1.15) : root.paletteTheme.blue)
                            Text {
                                anchors.centerIn: parent
                                text: root.busy ? "Working..." : "Apply changes"
                                color: root.busy || !root.dirty ? Qt.alpha(root.paletteTheme.white, 0.55) : root.paletteTheme.bg0
                                font.family: root.paletteTheme.fontMain
                                font.pixelSize: 14
                                font.bold: true
                            }
                            MouseArea {
                                id: applyArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: !root.busy && root.dirty
                                onClicked: root.applySettings()
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        text: root.statusMessage
                        color: root.failed ? root.paletteTheme.red : (root.dirty ? root.paletteTheme.yellow : Qt.alpha(root.paletteTheme.white, 0.57))
                        font.family: root.paletteTheme.fontMain
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                    }
                }
            }
        }
    }
}
