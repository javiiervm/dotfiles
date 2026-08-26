import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import "modules" as Modules
import "modules"

WlSessionLock {
    id: lock
    locked: true

    WlSessionLockSurface {
        id: surface

        // ============================================================
        // WALLPAPER
        // ============================================================

        Image {
            id: wall

            anchors.fill: parent

            source: "file://"
                    + Quickshell.env("HOME")
                    + "/.cache/hyprlock/current_wallpaper.png"

            fillMode: Image.PreserveAspectCrop

            // MultiEffect renderiza la imagen final.
            visible: false
        }

        // ============================================================
        // WALLPAPER BLUR
        // ============================================================

        MultiEffect {
            anchors.fill: parent

            source: wall

            blurEnabled: true

            // blur va de 0.0 a 1.0.
            // 1.0 = intensidad máxima.
            blur: 1.0

            // blurMax determina el radio/tamaño real del desenfoque.
            //
            // Si quieres MÁS blur, cambia este valor.
            // Por ejemplo:
            //
            // 32 -> suave
            // 48 -> medio
            // 64 -> fuerte
            // 80 -> muy fuerte
            //
            // Empiezo con 48 para mantener el wallpaper reconocible.
            blurMax: 64
        }

        // ============================================================
        // DARK OVERLAY
        // ============================================================

        Rectangle {
            anchors.fill: parent

            color: "black"

            // Controla únicamente cuánto se oscurece el fondo,
            // no cuánto se desenfoca.
            opacity: 0.32
        }

        // ============================================================
        // CLOCK
        // ============================================================

        Modules.ClockCard {
            id: clockCard

            anchors.horizontalCenter: parent.horizontalCenter

            anchors.top: parent.top
            anchors.topMargin: parent.height * 0.24
        }

        // ============================================================
        // LOGIN AREA
        // ============================================================

        Item {
            id: loginArea

            width: 360 * Theme.scale
            height: 245 * Theme.scale

            anchors.horizontalCenter: parent.horizontalCenter

            anchors.top: clockCard.bottom
            anchors.topMargin: 30 * Theme.scale

            // ========================================================
            // AVATAR
            // ========================================================

            Rectangle {
                id: avatar

                width: 120 * Theme.scale
                height: 120 * Theme.scale

                radius: width / 2

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top

                color: Theme.bgGlass

                border.width: 1
                border.color: Qt.alpha(
                    Theme.white,
                    0.15
                )

                // ----------------------------------------------------
                // AVATAR IMAGE
                // ----------------------------------------------------

                Image {
                    id: avatarImg

                    anchors.fill: parent
                    anchors.margins: 4 * Theme.scale

                    source:
                        "file:///home/javier/Pictures/Greninja-Blue.jpeg"

                    fillMode: Image.PreserveAspectCrop

                    visible: false
                }

                // ----------------------------------------------------
                // CIRCULAR MASK
                // ----------------------------------------------------

                Rectangle {
                    id: avatarMask

                    anchors.fill: avatarImg

                    radius: width / 2

                    visible: false
                }

                // ----------------------------------------------------
                // MASKED AVATAR
                // ----------------------------------------------------

                OpacityMask {
                    anchors.fill: avatarImg

                    source: avatarImg
                    maskSource: avatarMask
                }
            }

            // ========================================================
            // PASSWORD
            // ========================================================

            Modules.PasswordField {
                id: passField

                anchors.horizontalCenter: parent.horizontalCenter

                anchors.top: avatar.bottom
                anchors.topMargin: 26 * Theme.scale

                onUnlocked: {
                    lock.locked = false
                    Qt.quit()
                }
            }
        }

        // ============================================================
        // MEDIA PLAYER
        // ============================================================
        //
        // Centrado horizontalmente en la parte inferior de la pantalla.
        //
        // Antes:
        //
        // ┌──── media
        //
        // Ahora:
        //
        //                media
        //

        Modules.MediaPlayerCard {
            id: mediaCard

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom

            anchors.bottomMargin: 54 * Theme.scale
        }
    }
}