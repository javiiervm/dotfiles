import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "modules" as Modules
import "modules" // Importa el qmldir local para acceder a Theme

WlSessionLock {
    id: lock
    locked: true

    WlSessionLockSurface {
        id: surface

        // Imagen base oculta
        Image {
            id: wall
            anchors.fill: parent
            source: "file://" + Quickshell.env("HOME") + "/.cache/hyprlock/current_wallpaper.png"
            fillMode: Image.PreserveAspectCrop
            visible: false 
        }

        // Desenfoque del entorno
        MultiEffect {
            anchors.fill: wall
            source: wall
            blurEnabled: true
            blur: 0.45
        }

        // Capa de oscurecimiento global
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: 0.3 
        }

        // --- DASHBOARD CENTRAL (El "Macro-Contenedor") ---
        Rectangle {
            anchors.centerIn: parent
            width: dashboardLayout.implicitWidth + 80
            height: dashboardLayout.implicitHeight + 80
            radius: 32
            color: Qt.alpha(Theme.bg0, 0.65) // Fondo oscuro translúcido
            border.width: 1
            border.color: Qt.alpha(Theme.white, 0.1)

            Row {
                id: dashboardLayout
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
                    spacing: 40 // Aumentado para dar aire al nuevo reloj gigante
                    anchors.verticalCenter: parent.verticalCenter
                    width: 300

                    Modules.ClockCard {
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    // Avatar
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 120; height: 120; radius: 60
                        color: Theme.bgGlass
                        border.width: 1
                        border.color: Qt.alpha(Theme.white, 0.15)

                        Text {
                            anchors.centerIn: parent
                            text: ""
                            font.family: Theme.fontIcons
                            font.pixelSize: 54
                            color: Theme.blue
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
                        Repeater {
                            model: [
                                { icon: "󰖩", text: "WLAN" },
                                { icon: "󰂄", text: "BATT" },
                                { icon: "󰋋", text: "VOL" }
                            ]
                            delegate: Rectangle {
                                width: 80; height: 75; radius: 18 // Un poco más anchos para encajar mejor
                                color: Theme.bgGlass
                                border.width: 1
                                border.color: Qt.alpha(Theme.white, 0.15)
                                
                                Column {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text { 
                                        text: modelData.icon
                                        color: Theme.blue
                                        font.pixelSize: 24
                                        font.family: Theme.fontIcons
                                        anchors.horizontalCenter: parent.horizontalCenter 
                                    }
                                    Text { 
                                        text: modelData.text
                                        color: Theme.white
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        font.family: Theme.fontMain
                                        anchors.horizontalCenter: parent.horizontalCenter 
                                    }
                                }
                            }
                        }
                    }

                    Modules.NotificationsCard {}
                }
            }
        }
    }
}