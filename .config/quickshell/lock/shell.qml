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
        // WALLPAPER + BLUR
        // ============================================================
        //
        // The blurred layer is deliberately rendered slightly larger
        // than the screen. This gives the blur real image pixels to
        // sample outside the visible area instead of sampling the edge
        // of the texture, which was producing the bright/white halo
        // around the lockscreen.
        //
        Item {
            id: wallpaperLayer

            anchors.fill: parent
            clip: true

            Image {
                id: wall

                anchors.fill: parent
                anchors.margins: -80 * Theme.scale

                source: "file://"
                        + Quickshell.env("HOME")
                        + "/.cache/hyprlock/current_wallpaper.png"

                fillMode: Image.PreserveAspectCrop

                // MultiEffect renders the final image.
                visible: false
            }

            MultiEffect {
                anchors.fill: wall
                source: wall

                blurEnabled: true
                blur: 1.0
                blurMax: 64
            }
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

            Item {
                id: batteryIndicator

                width: 46 * Theme.scale
                height: 24 * Theme.scale

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: passField.bottom
                anchors.topMargin: 16 * Theme.scale

                visible: UPower.displayDevice.ready

                readonly property real percentage:
                    Math.max(
                        0,
                        Math.min(
                            100,
                            UPower.displayDevice.percentage * 100
                        )
                    )

                readonly property int roundedPercentage:
                    Math.round(percentage)

                readonly property bool charging:
                    UPower.displayDevice.state
                        === UPowerDeviceState.Charging
                    || UPower.displayDevice.state
                        === UPowerDeviceState.PendingCharge

                readonly property bool lowBattery:
                    percentage < 21

                // ----------------------------------------------------
                // FILL GRADIENTS
                // ----------------------------------------------------

                Gradient {
                    id: normalBatteryGradient
                    orientation: Gradient.Vertical

                    GradientStop {
                        position: 0.0
                        color: "#ffffff"
                    }

                    GradientStop {
                        position: 0.5
                        color: "#c4c4c4"
                    }

                    GradientStop {
                        position: 1.0
                        color: "#bebebe"
                    }
                }

                Gradient {
                    id: chargingBatteryGradient
                    orientation: Gradient.Vertical

                    GradientStop {
                        position: 0.0
                        color: "#65efe8"
                    }

                    GradientStop {
                        position: 0.5
                        color: "#2ecc71"
                    }

                    GradientStop {
                        position: 1.0
                        color: "#22aa5e"
                    }
                }

                Gradient {
                    id: lowBatteryGradient
                    orientation: Gradient.Vertical

                    GradientStop {
                        position: 0.0
                        color: "#ff9d60"
                    }

                    GradientStop {
                        position: 0.5
                        color: "#f13857"
                    }

                    GradientStop {
                        position: 1.0
                        color: "#d12543"
                    }
                }

                // ----------------------------------------------------
                // BATTERY ICON
                // ----------------------------------------------------

                Item {
                    id: batteryIcon

                    width: 46 * Theme.scale
                    height: 20 * Theme.scale
                    anchors.centerIn: parent

                    Rectangle {
                        id: batteryBody

                        width: 41 * Theme.scale
                        height: 20 * Theme.scale

                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter

                        radius: 6 * Theme.scale

                        // Same light, flat empty background as the bar icon.
                        color: Qt.alpha(Theme.white, 0.42)

                        border.width: 1 * Theme.scale
                        border.color: Qt.rgba(1, 1, 1, 0.55)

                        Item {
                            id: fillClip

                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.margins: 2 * Theme.scale

                            width: Math.max(
                                0,
                                (batteryBody.width - 4 * Theme.scale)
                                    * batteryIndicator.percentage / 100.0
                            )

                            clip: true

                            Behavior on width {
                                NumberAnimation {
                                    duration: 300
                                    easing.type: Easing.OutQuint
                                }
                            }

                            Rectangle {
                                width: batteryBody.width - 4 * Theme.scale
                                height: batteryBody.height - 4 * Theme.scale
                                radius: 4 * Theme.scale

                                gradient: batteryIndicator.charging
                                    ? chargingBatteryGradient
                                    : (
                                        batteryIndicator.lowBattery
                                            ? lowBatteryGradient
                                            : normalBatteryGradient
                                    )
                            }
                        }

                        // Percentage inside the battery body.
                        Text {
                            width: parent.width
                            height: parent.height
                            x: 0
                            y: 0.5 * Theme.scale

                            text: batteryIndicator.roundedPercentage

                            color: Theme.bg0
                            font.family: Theme.fontMain
                            font.pixelSize: 12 * Theme.scale
                            font.bold: true

                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    // Battery terminal.
                    Rectangle {
                        width: 3 * Theme.scale
                        height: 8 * Theme.scale

                        anchors.left: batteryBody.right
                        anchors.leftMargin: 1 * Theme.scale
                        anchors.verticalCenter: parent.verticalCenter

                        radius: 1.5 * Theme.scale
                        color: Qt.alpha(Theme.white, 0.55)
                    }
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