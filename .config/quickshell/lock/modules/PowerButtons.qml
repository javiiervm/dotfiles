import QtQuick
import QtQuick.Layouts
import "." as Local
import "../../"

Item {
    id: root
    implicitWidth: 260 * Theme.scale
    implicitHeight: 48 * Theme.scale

    RowLayout {
        anchors.fill: parent
        spacing: 12 * Theme.scale

        // --- BOTÓN REINICIAR (Izquierda) ---
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 14 * Theme.scale
            color: resetMouse.containsMouse ? Qt.alpha(Theme.blue, 0.2) : Qt.alpha(Theme.white, 0.04)
            border.color: resetMouse.containsMouse ? Qt.alpha(Theme.blue, 0.5) : Qt.alpha(Theme.white, 0.08)
            border.width: 1

            Behavior on color { ColorAnimation { duration: 150 } }
            Behavior on border.color { ColorAnimation { duration: 150 } }

            Text {
                anchors.centerIn: parent
                text: "󰜉" // Icono de Reset / Reboot
                font.family: Theme.fontIcons
                font.pixelSize: 20 * Theme.scale
                color: resetMouse.containsMouse ? Theme.blue : Theme.white
            }

            MouseArea {
                id: resetMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    // Sin acción por ahora
                }
            }
        }

        // --- BOTÓN APAGAR (Derecha) ---
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 14 * Theme.scale
            color: powerMouse.containsMouse ? Qt.alpha(Theme.red, 0.2) : Qt.alpha(Theme.white, 0.04)
            border.color: powerMouse.containsMouse ? Qt.alpha(Theme.red, 0.5) : Qt.alpha(Theme.white, 0.08)
            border.width: 1

            Behavior on color { ColorAnimation { duration: 150 } }
            Behavior on border.color { ColorAnimation { duration: 150 } }

            Text {
                anchors.centerIn: parent
                text: "󰐥" // Icono de Power
                font.family: Theme.fontIcons
                font.pixelSize: 20 * Theme.scale
                color: powerMouse.containsMouse ? Theme.red : Theme.white
            }

            MouseArea {
                id: powerMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    // Sin acción por ahora
                }
            }
        }
    }
}