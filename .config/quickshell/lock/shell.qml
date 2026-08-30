import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.UPower
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
            blurMax: 64
        }

        // ============================================================
        // DARK OVERLAY
        // ============================================================

        Rectangle {
            anchors.fill: parent

            color: "black"
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
            height: 290 * Theme.scale

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

            // ========================================================
            // BATTERY
            // ========================================================

            Row {
                id: batteryIndicator

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: passField.bottom
                anchors.topMargin: 16 * Theme.scale

                spacing: 8 * Theme.scale

                visible: UPower.displayDevice.ready

                readonly property real percentage:
                    Math.max(
                        0,
                        Math.min(
                            100,
                            UPower.displayDevice.percentage * 100
                        )
                    )

                readonly property bool charging:
                    UPower.displayDevice.state
                        === UPowerDeviceState.Charging
                    || UPower.displayDevice.state
                        === UPowerDeviceState.PendingCharge

                readonly property bool lowBattery:
                    percentage <= 20

                // ----------------------------------------------------
                // BATTERY ICON
                // ----------------------------------------------------

                Item {
                    width: 34 * Theme.scale
                    height: 17 * Theme.scale

                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        id: batteryBody

                        width: 30 * Theme.scale
                        height: 17 * Theme.scale

                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter

                        radius: 5 * Theme.scale

                        color: Qt.alpha(
                            Theme.white,
                            0.18
                        )

                        border.width: 1 * Theme.scale
                        border.color: Qt.alpha(
                            Theme.white,
                            0.50
                        )

                        // Battery fill clip
                        Item {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom

                            anchors.margins: 2 * Theme.scale

                            width: Math.max(
                                0,
                                (parent.width - 4 * Theme.scale)
                                    * batteryIndicator.percentage
                                    / 100
                            )

                            clip: true

                            Rectangle {
                                width:
                                    batteryBody.width
                                    - 4 * Theme.scale

                                height:
                                    batteryBody.height
                                    - 4 * Theme.scale

                                radius: 3 * Theme.scale

                                color:
                                    batteryIndicator.charging
                                        ? "#2ecc71"
                                        : (
                                            batteryIndicator.lowBattery
                                                ? "#f13857"
                                                : Theme.white
                                        )
                            }
                        }
                    }

                    // Battery terminal
                    Rectangle {
                        width: 2 * Theme.scale
                        height: 7 * Theme.scale

                        anchors.left: batteryBody.right
                        anchors.leftMargin: 1 * Theme.scale
                        anchors.verticalCenter: parent.verticalCenter

                        radius: width / 2

                        color: Qt.alpha(
                            Theme.white,
                            0.55
                        )
                    }
                }

                // ----------------------------------------------------
                // PERCENTAGE
                // ----------------------------------------------------

                Text {
                    anchors.verticalCenter: parent.verticalCenter

                    text:
                        Math.round(
                            batteryIndicator.percentage
                        ) + "%"

                    color:
                        batteryIndicator.charging
                            ? "#65efe8"
                            : (
                                batteryIndicator.lowBattery
                                    ? "#ff8b9c"
                                    : Theme.white
                            )

                    font.family: Theme.fontMain
                    font.pixelSize: 14 * Theme.scale
                    font.weight: Font.Medium
                }
            }
        }

        // ============================================================
        // MEDIA PLAYER
        // ============================================================

        Modules.MediaPlayerCard {
            id: mediaCard

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom

            anchors.bottomMargin: 54 * Theme.scale
        }
    }
}