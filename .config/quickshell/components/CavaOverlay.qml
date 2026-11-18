import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// One audio analyzer shared by every monitor. The caller controls the
// power-profile gate through `allowed`.
Scope {
    id: overlay

    property bool allowed: false
    property bool audioActive: false
    property bool pendingColorRefresh: false

    // 40 bars instead of 80: approximately twice the width.
    readonly property int barCount: 40

    ListModel {
        id: spectrum
        Component.onCompleted: {
            for (var i = 0; i < overlay.barCount; ++i)
                append({ "barHeight": 0, "barColor": "#8dacc5" })
        }
    }

    // Wait a little before hiding, so brief pauses between audio samples
    // do not cause the entire overlay to flicker.
    Timer {
        id: silenceTimer
        interval: 650
        repeat: false
        onTriggered: overlay.audioActive = false
    }

    onAllowedChanged: {
        if (!allowed) {
            audioActive = false
            silenceTimer.stop()
            pendingColorRefresh = false
            colorRefreshDebounce.stop()
            colorProc.running = false
        } else {
            Qt.callLater(refreshColor)
        }
    }

    // CAVA is fully stopped in power-saver; it is not merely hidden.
    // 'pulse' reads the monitor of the default PipeWire/PulseAudio sink.
    Process {
        id: cavaProc
        running: overlay.allowed
        command: [
            "bash", "-c",
            "config=\"${XDG_RUNTIME_DIR:-/tmp}/qs-cava-overlay-${UID}.conf\"\n" +
            "cat > \"$config\" <<'CAVA_CONFIG'\n" +
            "[general]\n" +
            "bars = 40\n" +
            "framerate = 45\n" +
            "[input]\n" +
            "method = pulse\n" +
            "source = auto\n" +
            "[output]\n" +
            "method = raw\n" +
            "raw_target = /dev/stdout\n" +
            "data_format = ascii\n" +
            "ascii_max_range = 100\n" +
            "[smoothing]\n" +
            "noise_reduction = 75\n" +
            "monstercat = 1\n" +
            "CAVA_CONFIG\n" +
            "exec cava -p \"$config\""
        ]

        stdout: SplitParser {
            onRead: function(line) {
                if (!overlay.allowed)
                    return

                var values = line.trim().split(";")
                if (values.length < overlay.barCount)
                    return

                var peak = 0
                for (var i = 0; i < overlay.barCount; ++i) {
                    var v = parseInt(values[i], 10)
                    v = isNaN(v) ? 0 : Math.max(0, Math.min(100, v))
                    peak = Math.max(peak, v)
                    if (spectrum.get(i).barHeight !== v)
                        spectrum.setProperty(i, "barHeight", v)
                }

                // CAVA captures the actual audio signal, not just the
                // existence of a Spotify/browser media session.
                if (peak >= 3) {
                    overlay.audioActive = true
                    silenceTimer.restart()
                }
            }
        }
    }

    // React to both wallpaper changes and pywal palette updates.
    // Watch the directories, not individual files: pywal may replace
    // colors.json atomically, which can invalidate a per-file watcher.
    // inotifywait blocks until something changes (no polling).
    // It runs only in balanced/performance and is exec'd directly so
    // stopping the Quickshell Process also stops the watcher.
    Process {
        id: wallpaperChangeWatcher
        running: overlay.allowed
        command: [
            "bash", "-c",
            "cache=\"$HOME/.cache\"\n" +
            "if [ -d \"$cache/wal\" ]; then\n" +
            "  exec inotifywait -m -q -e close_write,create,moved_to --format '%w%f' \"$cache\" \"$cache/wal\"\n" +
            "fi\n" +
            "exec inotifywait -m -q -e close_write,create,moved_to --format '%w%f' \"$cache\"\n"
        ]
        stdout: SplitParser {
            onRead: function(line) {
                var path = line.trim()
                if (path.endsWith("/qs_wall_path") || path.endsWith("/wal/colors.json"))
                    colorRefreshDebounce.restart()
            }
        }
    }

    // The wallpaper selector writes its pointer both before and after
    // regenerating pywal. Coalesce those events and read the final state.
    Timer {
        id: colorRefreshDebounce
        interval: 180
        repeat: false
        onTriggered: overlay.refreshColor()
    }

    function refreshColor() {
        if (!allowed)
            return
        if (colorProc.running) {
            pendingColorRefresh = true
            return
        }
        // Python reads the pointer directly from disk on each invocation.
        // No stale QML FileView cache and no extra shell process per update.
        colorProc.command = [
            "python3",
            Quickshell.shellPath("scripts/cava_wallpaper_color.py"),
            String(overlay.barCount)
        ]
        colorProc.running = true
    }

    Process {
        id: colorProc
        stdout: SplitParser {
            onRead: function(line) {
                // Each bar gets the same wallpaper-derived hue, with
                // individual lightness adapted to the area behind it.
                var colors = line.trim().split(";")
                if (colors.length !== overlay.barCount)
                    return

                for (var i = 0; i < overlay.barCount; ++i) {
                    if (/^#[0-9a-fA-F]{6}$/.test(colors[i])
                        && spectrum.get(i).barColor !== colors[i]) {
                        spectrum.setProperty(i, "barColor", colors[i])
                    }
                }
            }
        }
        onRunningChanged: {
            if (!running && overlay.pendingColorRefresh && overlay.allowed) {
                overlay.pendingColorRefresh = false
                Qt.callLater(overlay.refreshColor)
            }
        }
    }

    // Visual instances only: every monitor shares the same audio analyzer.
    // awww-daemon (configured in hyprland.lua) is in Background.
    // Bottom is ABOVE the wallpaper and BELOW application windows and the
    // Top/Overlay layers used by Quickshell (dock, island, menus, etc.).
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: visualPanel
            required property var modelData
            screen: modelData
            anchors { bottom: true; left: true; right: true }
            margins { bottom: 0; left: 0; right: 0 }

            // One third of the logical screen height at maximum signal.
            implicitHeight: Math.max(1, Math.round(modelData.height / 3))
            exclusiveZone: 0
            color: "transparent"
            visible: overlay.allowed && overlay.audioActive

            WlrLayershell.layer: WlrLayer.Bottom
            mask: Region {}

            RowLayout {
                anchors.fill: parent
                spacing: 4

                Repeater {
                    model: spectrum

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignBottom

                        // Give lower audio peaks more visual presence, without
                        // letting any bar exceed one third of the screen.
                        implicitHeight: Math.max(2, Math.min(
                            visualPanel.implicitHeight,
                            Math.round(visualPanel.implicitHeight
                                       * Math.sqrt(Math.max(0, barHeight) / 100)
                                       * 1.12)
                        ))

                        radius: 4
                        color: barColor
                        opacity: 0.96

                        Behavior on implicitHeight {
                            NumberAnimation {
                                duration: 80
                                easing.type: Easing.OutCubic
                            }
                        }
                        Behavior on color {
                            ColorAnimation { duration: 500 }
                        }
                    }
                }
            }
        }
    }
}
