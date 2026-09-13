import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import "components"

Rectangle {
    id: root

    width: 2560
    height: 1600

    color: "#050505"

    // ============================================================
    // CONFIG
    // ============================================================

    readonly property real uiScale: {
        var configured = config.realValue("scale")

        return configured > 0
            ? configured
            : 1.25
    }

    readonly property string loginUser: {
        var configured =
            config.stringValue("userName")

        if (configured.length > 0)
            return configured

        if (
            userModel.lastUser
            && userModel.lastUser.length > 0
        )
            return userModel.lastUser

        return "javier"
    }

    readonly property int sessionIndex:
        sessionModel.lastIndex >= 0
            ? sessionModel.lastIndex
            : 0

    property string statusMessage: ""
    property color statusColor: "#ccffffff"

    function attemptLogin(password) {
        if (!password || password.length === 0)
            return

        statusMessage = ""

        sddm.login(
            loginUser,
            password,
            sessionIndex
        )
    }

    // ============================================================
    // WALLPAPER + BLUR
    // ============================================================

    Item {
        id: wallpaperLayer

        anchors.fill:
            parent

        clip: true

        Image {
            id: wall

            anchors.fill:
                parent

            anchors.margins:
                -80 * root.uiScale

            source:
                config.stringValue(
                    "wallpaper"
                )

            fillMode:
                Image.PreserveAspectCrop

            visible: false
        }

        MultiEffect {
            anchors.fill:
                wall

            source:
                wall

            blurEnabled: true
            blur: 1.0
            blurMax: 64
        }
    }

    // ============================================================
    // DARK OVERLAY
    // ============================================================

    Rectangle {
        anchors.fill:
            parent

        color:
            "black"

        opacity:
            0.32
    }

    // ============================================================
    // CENTRAL LOGIN STACK
    // ============================================================

    Item {
        id: authStack

        width:
            420 * root.uiScale

        height:
            clockCard.implicitHeight
            + 30 * root.uiScale
            + loginArea.height

        anchors.horizontalCenter:
            parent.horizontalCenter

        anchors.verticalCenter:
            parent.verticalCenter

        anchors.verticalCenterOffset:
            10 * root.uiScale

        // ========================================================
        // CLOCK
        // ========================================================

        ClockCard {
            id: clockCard

            uiScale:
                root.uiScale

            anchors.horizontalCenter:
                parent.horizontalCenter

            anchors.top:
                parent.top
        }

        // ========================================================
        // LOGIN AREA
        // ========================================================

        Item {
            id: loginArea

            width:
                360 * root.uiScale

            height:
                290 * root.uiScale

            anchors.horizontalCenter:
                parent.horizontalCenter

            anchors.top:
                clockCard.bottom

            anchors.topMargin:
                30 * root.uiScale

            // ====================================================
            // AVATAR
            // ====================================================

            Rectangle {
                id: avatar

                width:
                    120 * root.uiScale

                height:
                    120 * root.uiScale

                radius:
                    width / 2

                anchors.horizontalCenter:
                    parent.horizontalCenter

                anchors.top:
                    parent.top

                color:
                    "#991e1e24"

                border.width:
                    1

                border.color:
                    "#26ffffff"

                Image {
                    id: avatarImg

                    anchors.fill:
                        parent

                    anchors.margins:
                        4 * root.uiScale

                    source:
                        config.stringValue(
                            "avatar"
                        )

                    fillMode:
                        Image.PreserveAspectCrop

                    visible:
                        false
                }

                Rectangle {
                    id: avatarMask

                    anchors.fill:
                        avatarImg

                    radius:
                        width / 2

                    visible:
                        false
                }

                OpacityMask {
                    anchors.fill:
                        avatarImg

                    source:
                        avatarImg

                    maskSource:
                        avatarMask

                    visible:
                        avatarImg.status
                            === Image.Ready
                }

                Text {
                    anchors.centerIn:
                        parent

                    visible:
                        avatarImg.status
                            !== Image.Ready

                    text:
                        "J"

                    color:
                        "#ffffff"

                    font.family:
                        "Adwaita Sans"

                    font.pixelSize:
                        48 * root.uiScale

                    font.weight:
                        Font.DemiBold
                }
            }

            // ====================================================
            // PASSWORD
            // ====================================================

            PasswordField {
                id: passField

                uiScale:
                    root.uiScale

                anchors.horizontalCenter:
                    parent.horizontalCenter

                anchors.top:
                    avatar.bottom

                anchors.topMargin:
                    26 * root.uiScale

                onSubmitted:
                    function(password) {
                        root.attemptLogin(
                            password
                        )
                    }

                onEdited: {
                    if (
                        root.statusMessage.length
                            > 0
                    ) {
                        root.statusMessage = ""
                    }
                }
            }

            // ====================================================
            // BATTERY
            // ====================================================

            BatteryIndicator {
                id: batteryIndicator

                uiScale:
                    root.uiScale

                deviceName:
                    "BAT0"

                anchors.horizontalCenter:
                    parent.horizontalCenter

                anchors.top:
                    passField.bottom

                anchors.topMargin:
                    16 * root.uiScale
            }

            // ====================================================
            // STATUS / LOGIN ERROR
            // ====================================================

            Text {
                anchors.horizontalCenter:
                    parent.horizontalCenter

                anchors.top:
                    batteryIndicator.bottom

                anchors.topMargin:
                    12 * root.uiScale

                text:
                    root.statusMessage

                color:
                    root.statusColor

                visible:
                    text.length > 0

                font.family:
                    "Adwaita Sans"

                font.pixelSize:
                    11 * root.uiScale

                font.weight:
                    Font.Medium
            }
        }
    }

    // ============================================================
    // POWER CONTROLS
    // ============================================================

    Row {
        anchors.right:
            parent.right

        anchors.bottom:
            parent.bottom

        anchors.rightMargin:
            34 * root.uiScale

        anchors.bottomMargin:
            32 * root.uiScale

        spacing:
            12 * root.uiScale

        // --------------------------------------------------------
        // RESTART
        // --------------------------------------------------------

        PowerButton {
            uiScale:
                root.uiScale

            symbol:
                "↻"

            accentColor:
                "#61afef"

            tooltip:
                "Restart"

            onClicked:
                sddm.reboot()
        }

        // --------------------------------------------------------
        // POWER OFF
        // --------------------------------------------------------

        PowerButton {
            uiScale:
                root.uiScale

            symbol:
                "⏻"

            accentColor:
                "#e08c75"

            tooltip:
                "Power off"

            iconYOffset:
                2.5

            onClicked:
                sddm.powerOff()
        }
    }

    // ============================================================
    // AUTHENTICATION FEEDBACK
    // ============================================================

    Connections {
        target:
            sddm

        function onLoginSucceeded() {
            root.statusMessage = ""
        }

        function onLoginFailed() {
            root.statusMessage =
                "Incorrect password"

            root.statusColor =
                "#e08c75"

            passField.clearAndFocus()
        }

        function onInformationMessage(message) {
            root.statusMessage =
                message

            root.statusColor =
                "#ccffffff"
        }
    }

    // ============================================================
    // INITIAL FOCUS
    // ============================================================

    Component.onCompleted:
        passField.forceInputFocus()
}
