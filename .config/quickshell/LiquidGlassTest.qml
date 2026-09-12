import QtQuick
import Quickshell
import Quickshell.Wayland

import "."
import "components"

ShellRoot {
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

        GlassSurface {
            anchors.fill: parent

            glassRadius: 24

            // Menos capa oscura del tema antiguo
            glassOpacity: 0.23

            showBorder: true

            // Quitamos el highlight QML para dejar que
            // el propio HyprGlass haga el borde óptico.
            showHighlight: false

            clip: true

            Column {
                anchors.centerIn: parent
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

                    text: "Quickshell theme preview"

                    // Un poco más legible que Theme.grey1
                    color: Qt.alpha(Theme.white, 0.58)

                    font.family: Theme.fontMain
                    font.pixelSize: 12
                }
            }
        }
    }
}