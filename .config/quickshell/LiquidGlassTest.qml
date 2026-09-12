import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

import "."
import "components"

ShellRoot {
    id: root

    /*
     * ============================================================
     * GLASS MODE
     * ============================================================
     *
     * liquid  -> HyprGlass real Liquid Glass
     * classic -> GlassSurface + blur clásico de Hyprland
     *
     * El estado persistente se guarda en:
     *
     * ~/.config/quickshell/state/glass-mode
     */

    property bool liquidGlassEnabled: true
    property bool glassModeLoaded: false


    // ============================================================
    // PERSISTENT STATE READER
    // ============================================================

    Process {
        id: glassModeReader

        running: true

        command: [
            "bash",
            "-c",
            "mkdir -p ~/.config/quickshell/state; " +
            "cat ~/.config/quickshell/state/glass-mode 2>/dev/null || echo liquid"
        ]

        stdout: SplitParser {
            onRead: function(data) {
                var mode = data.trim()

                root.liquidGlassEnabled = (mode !== "classic")
                root.glassModeLoaded = true
            }
        }
    }


    // ============================================================
    // PERSISTENT STATE WRITER
    // ============================================================

    Process {
        id: glassModeWriter

        stdout: SplitParser {
            onRead: function(data) {
                var mode = data.trim()

                if (mode === "liquid")
                    root.liquidGlassEnabled = true
                else if (mode === "classic")
                    root.liquidGlassEnabled = false
            }
        }

        onRunningChanged: {
            if (!running && root.glassModeLoaded) {
                if (!hyprReloadProc.running)
                    hyprReloadProc.running = true
            }
        }
    }


    // ============================================================
    // HYPRLAND RELOAD
    // ============================================================

    Process {
        id: hyprReloadProc

        command: [
            "hyprctl",
            "reload"
        ]
    }


    // ============================================================
    // TOGGLE FUNCTION
    // ============================================================

    function toggleGlassMode() {
        if (!root.glassModeLoaded || glassModeWriter.running)
            return

        var newMode =
            root.liquidGlassEnabled
            ? "classic"
            : "liquid"

        // Actualización inmediata de la parte QML.
        root.liquidGlassEnabled = (newMode === "liquid")

        // Persistimos el cambio.
        glassModeWriter.command = [
            "bash",
            "-c",
            "mkdir -p ~/.config/quickshell/state && " +
            "printf '%s\\n' '" + newMode + "' " +
            "> ~/.config/quickshell/state/glass-mode && " +
            "printf '%s\\n' '" + newMode + "'"
        ]

        glassModeWriter.running = true
    }


    // ============================================================
    // TEST WINDOW
    // ============================================================

    PanelWindow {
        id: testWindow

        screen: Quickshell.screens[0]

        implicitWidth: 520
        implicitHeight: 320

        exclusiveZone: 0

        color: "transparent"

        WlrLayershell.layer: WlrLayershell.Overlay
        WlrLayershell.namespace: "liquid-glass-test"

        anchors {
            top: true
            left: true
        }

        margins {
            top: Math.round((screen.height - implicitHeight) / 2)
            left: Math.round((screen.width - implicitWidth) / 2)
        }


        // ========================================================
        // GLASS SURFACE
        // ========================================================

        GlassSurface {
            anchors.fill: parent

            glassRadius: 24

            /*
             * Classic:
             *   comportamiento visual original de GlassSurface.
             *
             * Liquid:
             *   dejamos una capa mucho más ligera para que
             *   HyprGlass sea quien genere realmente el material.
             */
            glassOpacity:
                root.liquidGlassEnabled
                ? 0.23
                : Glass.opacity

            showBorder: true

            /*
             * En modo clásico conservamos el highlight superior
             * original de GlassSurface.
             *
             * En Liquid Glass lo desactivamos porque HyprGlass
             * genera su propia iluminación óptica mediante Fresnel.
             */
            showHighlight:
                !root.liquidGlassEnabled

            clip: true


            // ====================================================
            // CONTENT
            // ====================================================

            Column {
                anchors.centerIn: parent

                spacing: 18


                // ------------------------------------------------
                // TITLE
                // ------------------------------------------------

                Column {
                    anchors.horizontalCenter: parent.horizontalCenter

                    spacing: 8

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter

                        text: "LIQUID GLASS TEST"

                        color: Theme.white

                        font.family: Theme.fontMain
                        font.pixelSize: 24
                        font.bold: true
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter

                        text:
                            root.liquidGlassEnabled
                            ? "HyprGlass Liquid Glass"
                            : "Classic Quickshell Glass"

                        color: Qt.alpha(Theme.white, 0.58)

                        font.family: Theme.fontMain
                        font.pixelSize: 12
                    }
                }


                // ------------------------------------------------
                // GLASS MODE TOGGLE
                // ------------------------------------------------

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter

                    spacing: 12


                    // Classic label
                    Text {
                        anchors.verticalCenter: parent.verticalCenter

                        text: "Classic"

                        color:
                            !root.liquidGlassEnabled
                            ? Theme.white
                            : Qt.alpha(Theme.white, 0.45)

                        font.family: Theme.fontMain
                        font.pixelSize: 12
                        font.bold: !root.liquidGlassEnabled
                    }


                    // Toggle
                    Rectangle {
                        id: glassToggle

                        width: 46
                        height: 26

                        radius: height / 2

                        color:
                            root.liquidGlassEnabled
                            ? Qt.rgba(0.22, 0.62, 1.0, 0.85)
                            : Qt.alpha(Theme.white, 0.16)

                        border.width: 1

                        border.color:
                            root.liquidGlassEnabled
                            ? Qt.alpha(Theme.white, 0.22)
                            : Qt.alpha(Theme.white, 0.16)


                        Rectangle {
                            width: 20
                            height: 20

                            radius: width / 2

                            anchors.verticalCenter: parent.verticalCenter

                            x:
                                root.liquidGlassEnabled
                                ? parent.width - width - 3
                                : 3

                            color: Theme.white

                            Behavior on x {
                                NumberAnimation {
                                    duration: 160
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }


                        MouseArea {
                            anchors.fill: parent

                            enabled:
                                root.glassModeLoaded &&
                                !glassModeWriter.running

                            cursorShape:
                                enabled
                                ? Qt.PointingHandCursor
                                : Qt.ArrowCursor

                            onClicked:
                                root.toggleGlassMode()
                        }
                    }


                    // Liquid Glass label
                    Text {
                        anchors.verticalCenter: parent.verticalCenter

                        text: "Liquid Glass"

                        color:
                            root.liquidGlassEnabled
                            ? Theme.white
                            : Qt.alpha(Theme.white, 0.45)

                        font.family: Theme.fontMain
                        font.pixelSize: 12
                        font.bold: root.liquidGlassEnabled
                    }
                }
            }
        }
    }
}