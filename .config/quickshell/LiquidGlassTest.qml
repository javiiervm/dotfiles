import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

import "."
import "components"

ShellRoot {
    id: root

    /*
     * ============================================================
     * LIQUID GLASS TEST
     * ============================================================
     *
     * Esta ventana sigue funcionando como sandbox visual, pero ya
     * no mantiene un estado de Glass independiente.
     *
     * El modo global lo controla:
     *
     *     GlassMode
     *
     * classic
     *     GlassSurface + blur normal de Hyprland.
     *
     * liquid
     *     GlassSurface ligero + HyprGlass real.
     *
     * Cambiar el toggle aquí cambia el modo GLOBAL, igual que el
     * botón que añadiremos al Notification Center.
     */


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

        WlrLayershell.layer:
            WlrLayershell.Overlay

        WlrLayershell.namespace:
            "liquid-glass-test"


        anchors {
            top: true
            left: true
        }


        margins {
            top:
                Math.round(
                    (screen.height - implicitHeight)
                    / 2
                )

            left:
                Math.round(
                    (screen.width - implicitWidth)
                    / 2
                )
        }


        // ========================================================
        // CLASSIC BACKDROP BLUR
        // ========================================================
        //
        // En modo Classic conservamos explícitamente el blur normal
        // que ya utilizaban los componentes Quickshell.
        //
        // En modo Liquid esta región desaparece por completo:
        // HyprGlass pasa a ser el encargado del backdrop.
        // ========================================================

        BackgroundEffect.blurRegion:
            Glass.blurEnabled
            && GlassMode.classic
            ? testBlurRegion
            : null


        Region {
            id: testBlurRegion

            item: testGlass

            radius:
                testGlass.radius
        }


        // ========================================================
        // GLASS SURFACE
        // ========================================================

        GlassSurface {
            id: testGlass

            anchors.fill: parent

            glassRadius: 24


            /*
             * Classic:
             *
             *     comportamiento original de GlassSurface.
             *
             * Liquid:
             *
             *     GlassSurface solamente mantiene una capa QML
             *     ligera. HyprGlass genera el material óptico real.
             */

            glassOpacity:
                GlassMode.liquid
                ? GlassMode.liquidQmlOpacity
                : Glass.opacity


            showBorder: true


            /*
             * El highlight QML pertenece al aspecto clásico.
             *
             * Liquid Glass utiliza la iluminación óptica de
             * HyprGlass mediante Fresnel.
             */

            showHighlight:
                GlassMode.classic


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
                    anchors.horizontalCenter:
                        parent.horizontalCenter

                    spacing: 8


                    Text {
                        anchors.horizontalCenter:
                            parent.horizontalCenter

                        text:
                            "LIQUID GLASS TEST"

                        color:
                            Theme.white

                        font.family:
                            Theme.fontMain

                        font.pixelSize:
                            24

                        font.bold:
                            true
                    }


                    Text {
                        anchors.horizontalCenter:
                            parent.horizontalCenter

                        text:
                            GlassMode.liquid
                            ? "HyprGlass Liquid Glass"
                            : "Classic Quickshell Glass"

                        color:
                            Qt.alpha(
                                Theme.white,
                                0.58
                            )

                        font.family:
                            Theme.fontMain

                        font.pixelSize:
                            12
                    }
                }


                // ------------------------------------------------
                // GLOBAL GLASS MODE TOGGLE
                // ------------------------------------------------

                Row {
                    anchors.horizontalCenter:
                        parent.horizontalCenter

                    spacing: 12


                    // --------------------------------------------
                    // Classic label
                    // --------------------------------------------

                    Text {
                        anchors.verticalCenter:
                            parent.verticalCenter

                        text:
                            "Classic"

                        color:
                            GlassMode.classic
                            ? Theme.white
                            : Qt.alpha(
                                  Theme.white,
                                  0.45
                              )

                        font.family:
                            Theme.fontMain

                        font.pixelSize:
                            12

                        font.bold:
                            GlassMode.classic
                    }


                    // --------------------------------------------
                    // Toggle
                    // --------------------------------------------

                    Rectangle {
                        id: glassToggle

                        width: 46
                        height: 26

                        radius:
                            height / 2


                        color:
                            GlassMode.liquid
                            ? Qt.rgba(
                                  0.22,
                                  0.62,
                                  1.0,
                                  0.85
                              )
                            : Qt.alpha(
                                  Theme.white,
                                  0.16
                              )


                        border.width:
                            1


                        border.color:
                            GlassMode.liquid
                            ? Qt.alpha(
                                  Theme.white,
                                  0.22
                              )
                            : Qt.alpha(
                                  Theme.white,
                                  0.16
                              )


                        Rectangle {
                            width: 20
                            height: 20

                            radius:
                                width / 2

                            anchors.verticalCenter:
                                parent.verticalCenter


                            x:
                                GlassMode.liquid
                                ? parent.width
                                  - width
                                  - 3
                                : 3


                            color:
                                Theme.white


                            Behavior on x {
                                NumberAnimation {
                                    duration:
                                        160

                                    easing.type:
                                        Easing.OutCubic
                                }
                            }
                        }


                        MouseArea {
                            anchors.fill:
                                parent


                            enabled:
                                GlassMode.loaded


                            hoverEnabled:
                                enabled


                            cursorShape:
                                enabled
                                ? Qt.PointingHandCursor
                                : Qt.ArrowCursor


                            onClicked:
                                GlassMode.toggle()
                        }
                    }


                    // --------------------------------------------
                    // Liquid Glass label
                    // --------------------------------------------

                    Text {
                        anchors.verticalCenter:
                            parent.verticalCenter

                        text:
                            "Liquid Glass"


                        color:
                            GlassMode.liquid
                            ? Theme.white
                            : Qt.alpha(
                                  Theme.white,
                                  0.45
                              )


                        font.family:
                            Theme.fontMain

                        font.pixelSize:
                            12

                        font.bold:
                            GlassMode.liquid
                    }
                }
            }
        }
    }
}