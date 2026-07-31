import QtQuick
import Quickshell
import Quickshell.Wayland
import "modules" as Modules

// Lanzar con: quickshell -c lock.qml
// (o copia esta carpeta a ~/.config/quickshell/lock/ e intégrala con tu
// configuración principal / atajo de bloqueo de Hyprland)

WlSessionLock {
    id: lock
    locked: true

    WlSessionLockSurface {
        id: surface

        Image {
            anchors.fill: parent
            source: "file://" + Quickshell.env("HOME") + "/.cache/hyprlock/current_wallpaper.png"
            fillMode: Image.PreserveAspectCrop
        }

        // Oscurece un poco el wallpaper para que las tarjetas resalten,
        // igual que el `brightness = 0.7` que ya usabas en hyprlock
        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: 0.25
        }

        Row {
            anchors.centerIn: parent
            spacing: 24

            // --- COLUMNA IZQUIERDA ---
            Column {
                spacing: 20
                anchors.verticalCenter: parent.verticalCenter
                Modules.WeatherCard {}
                Modules.SystemInfoCard {}
                Modules.MediaPlayerCard {}
            }

            // --- COLUMNA CENTRAL ---
            Column {
                spacing: 32
                anchors.verticalCenter: parent.verticalCenter
                width: 260

                Item { width: 1; height: 20 } // respiro superior

                Modules.ClockCard {
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                // Avatar/planeta decorativo central, como en la referencia.
                // Sustituye por tu propia imagen si tienes una.
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 140; height: 140; radius: 70
                    color: "#232a3d"
                    border.width: 1
                    border.color: "#ffffff1a"

                    Rectangle {
                        anchors.centerIn: parent
                        width: 80; height: 80; radius: 40
                        color: "#eef4fb"
                        rotation: -20
                        Rectangle {
                            anchors.centerIn: parent
                            width: 120; height: 14; radius: 7
                            color: "#232a3d"
                        }
                    }
                }

                Modules.PasswordField {
                    anchors.horizontalCenter: parent.horizontalCenter
                    onUnlocked: lock.locked = false
                }
            }

            // --- COLUMNA DERECHA ---
            Column {
                spacing: 20
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    spacing: 10
                    // Pills de estado rápido (temp/red/batería), decorativas
                    // por ahora — conéctalas a tus propios providers de datos
                    Repeater {
                        model: [
                            { icon: "", text: "100%" },
                            { icon: "", text: "41%" },
                            { icon: "", text: "16%" }
                        ]
                        delegate: Rectangle {
                            width: 60; height: 60; radius: 16
                            color: "#1a1f2eCC"
                            border.width: 1
                            border.color: "#ffffff1a"
                            Column {
                                anchors.centerIn: parent
                                spacing: 2
                                Text { text: modelData.icon; color: "#7ee6ff"; font.pixelSize: 16; anchors.horizontalCenter: parent.horizontalCenter }
                                Text { text: modelData.text; color: "#eef4fb"; font.pixelSize: 11; font.family: "JetBrains Mono Nerd Font"; anchors.horizontalCenter: parent.horizontalCenter }
                            }
                        }
                    }
                }

                Modules.NotificationsCard {}
            }
        }
    }
}
