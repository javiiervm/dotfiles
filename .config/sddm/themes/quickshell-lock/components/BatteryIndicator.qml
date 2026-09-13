import QtQuick

Item {
    id: root

    property real uiScale: 1.25
    property string deviceName: "BAT0"

    property int percentage: -1
    property string batteryStatus: ""

    readonly property bool charging:
        batteryStatus === "Charging"
        || batteryStatus === "Full"

    readonly property bool lowBattery:
        percentage >= 0
        && percentage < 21

    width: 46 * uiScale
    height: 24 * uiScale

    visible: percentage >= 0

    // ============================================================
    // READ BATTERY DATA
    // ============================================================

    function readFile(path, callback) {
        var xhr = new XMLHttpRequest()

        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.responseText) {
                    callback(
                        xhr.responseText
                            .toString()
                            .trim()
                    )
                }
            }
        }

        xhr.open(
            "GET",
            "file://" + path
        )

        xhr.send()
    }

    function refresh() {
        var base =
            "/sys/class/power_supply/"
            + root.deviceName

        readFile(
            base + "/capacity",
            function(value) {
                var parsed = parseInt(value)

                if (!isNaN(parsed)) {
                    root.percentage =
                        Math.max(
                            0,
                            Math.min(100, parsed)
                        )
                }
            }
        )

        readFile(
            base + "/status",
            function(value) {
                if (value.length > 0)
                    root.batteryStatus = value
            }
        )
    }

    Component.onCompleted:
        refresh()

    Timer {
        interval: 30000
        running: true
        repeat: true

        onTriggered:
            root.refresh()
    }

    // ============================================================
    // GRADIENTS
    // ============================================================

    Gradient {
        id: normalBatteryGradient

        orientation:
            Gradient.Vertical

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

        orientation:
            Gradient.Vertical

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

        orientation:
            Gradient.Vertical

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

    // ============================================================
    // BATTERY ICON
    // ============================================================

    Item {
        width: 46 * root.uiScale
        height: 20 * root.uiScale

        anchors.centerIn:
            parent

        Rectangle {
            id: batteryBody

            width: 41 * root.uiScale
            height: 20 * root.uiScale

            anchors.left:
                parent.left

            anchors.verticalCenter:
                parent.verticalCenter

            radius:
                6 * root.uiScale

            color:
                "#6bffffff"

            border.width:
                1 * root.uiScale

            border.color:
                "#8cffffff"

            // ====================================================
            // FILL
            // ====================================================

            Item {
                id: fillClip

                anchors.left:
                    parent.left

                anchors.top:
                    parent.top

                anchors.bottom:
                    parent.bottom

                anchors.margins:
                    2 * root.uiScale

                width:
                    Math.max(
                        0,
                        (batteryBody.width
                            - 4 * root.uiScale)
                        * root.percentage
                        / 100.0
                    )

                clip: true

                Behavior on width {
                    NumberAnimation {
                        duration: 300
                        easing.type:
                            Easing.OutQuint
                    }
                }

                Rectangle {
                    width:
                        batteryBody.width
                        - 4 * root.uiScale

                    height:
                        batteryBody.height
                        - 4 * root.uiScale

                    radius:
                        4 * root.uiScale

                    gradient:
                        root.charging
                            ? chargingBatteryGradient
                            : (
                                root.lowBattery
                                    ? lowBatteryGradient
                                    : normalBatteryGradient
                            )
                }
            }

            // ====================================================
            // PERCENTAGE
            // ====================================================

            Text {
                anchors.fill:
                    parent

                y:
                    0.5 * root.uiScale

                text:
                    root.percentage >= 0
                        ? root.percentage
                        : ""

                color:
                    "#050505"

                font.family:
                    "Adwaita Sans"

                font.pixelSize:
                    12 * root.uiScale

                font.bold: true

                horizontalAlignment:
                    Text.AlignHCenter

                verticalAlignment:
                    Text.AlignVCenter
            }
        }

        // ========================================================
        // TERMINAL
        // ========================================================

        Rectangle {
            width:
                3 * root.uiScale

            height:
                8 * root.uiScale

            anchors.left:
                batteryBody.right

            anchors.leftMargin:
                1 * root.uiScale

            anchors.verticalCenter:
                parent.verticalCenter

            radius:
                1.5 * root.uiScale

            color:
                "#8cffffff"
        }
    }
}
