import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
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
            blur: 1
        }

        // Capa de oscurecimiento global
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: 0.4
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
                spacing: 36

                // --- COLUMNA IZQUIERDA ---
                Column {
                    id: leftColumn
                    spacing: 20
                    anchors.top: parent.top
                    Modules.WeatherCard {}
                    Modules.SystemInfoCard {}
                    Modules.MediaPlayerCard {}
                }

                // --- COLUMNA CENTRAL ---
                Item {
                    anchors.top: parent.top
                    width: 340
                    height: leftColumn.height

                    // Reloj desplazado hacia abajo para equilibrar aire superior
                    Modules.ClockCard {
                        id: clockCard
                        anchors.top: parent.top
                        anchors.topMargin: 28 * Theme.scale
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    // Avatar con tu imagen personalizada de Greninja
                    Rectangle {
                        id: avatar
                        width: 120 * Theme.scale; height: 120 * Theme.scale; radius: width / 2
                        color: Theme.bgGlass
                        border.width: 1
                        border.color: Qt.alpha(Theme.white, 0.15)
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: passField.top
                        anchors.bottomMargin: 24 * Theme.scale

                        // 1. Imagen personalizada
                        Image {
                            id: avatarImg
                            anchors.fill: parent
                            anchors.margins: 4 * Theme.scale
                            source: "file:///home/javier/Pictures/Greninja-Blue.jpeg"
                            fillMode: Image.PreserveAspectCrop
                            visible: false
                        }

                        // 2. Máscara circular
                        Rectangle {
                            id: avatarMask
                            anchors.fill: avatarImg
                            radius: width / 2
                            visible: false
                        }

                        // 3. Recorte circular aplicado
                        OpacityMask {
                            anchors.fill: avatarImg
                            source: avatarImg
                            maskSource: avatarMask
                        }
                    }

                    // Campo de contraseña
                    Modules.PasswordField {
                        id: passField
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        onUnlocked: {
                            lock.locked = false
                            Qt.quit() 
                        }
                    }
                }

                // --- COLUMNA DERECHA ---
                Column {
                    spacing: 20
                    anchors.top: parent.top

                    Modules.StatusIcons {
                        id: statusCard
                    }

                    Modules.NotificationsCard {
                        implicitHeight: leftColumn.height - statusCard.implicitHeight - powerCard.implicitHeight - 40
                    }

                    Modules.PowerButtons {
                        id: powerCard
                    }
                }
            }
        }
    }
}