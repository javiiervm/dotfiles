import QtQuick
import QtQuick.Layouts
import ".."

Item {
    id: batteryRoot

    property int percentage: 0
    property bool charging: false

    readonly property bool lowBattery: percentage < 21
    readonly property real clampedPercentage:
        Math.max(0, Math.min(percentage, 100))

    Layout.preferredWidth: 35
    Layout.preferredHeight: 18
    Layout.alignment: Qt.AlignVCenter

    implicitWidth: 35
    implicitHeight: 18

    Gradient {
        id: normalGradient
        orientation: Gradient.Vertical

        GradientStop { position: 0.0; color: "#ffffff" }
        GradientStop { position: 0.5; color: "#c4c4c4" }
        GradientStop { position: 1.0; color: "#bebebe" }
    }

    Gradient {
        id: chargingGradient
        orientation: Gradient.Vertical

        GradientStop { position: 0.0; color: "#65efe8" }
        GradientStop { position: 0.5; color: "#2ecc71" }
        GradientStop { position: 1.0; color: "#22aa5e" }
    }

    Gradient {
        id: lowBatteryGradient
        orientation: Gradient.Vertical

        GradientStop { position: 0.0; color: "#ff9d60" }
        GradientStop { position: 0.5; color: "#f13857" }
        GradientStop { position: 1.0; color: "#d12543" }
    }

    Item {
        id: batteryIcon

        width: 35
        height: 16
        anchors.centerIn: parent

        Rectangle {
            id: batteryBody

            width: 31
            height: 16

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            radius: 4.5
            color: Qt.alpha(Theme.white, 0.42)

            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.55)

            Item {
                id: fillClip

                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: 2

                width: Math.max(
                    0,
                    (batteryBody.width - 4)
                        * batteryRoot.clampedPercentage / 100.0
                )

                clip: true

                Behavior on width {
                    NumberAnimation {
                        duration: 300
                        easing.type: Easing.OutQuint
                    }
                }

                Rectangle {
                    width: batteryBody.width - 4
                    height: batteryBody.height - 4
                    radius: 2.5

                    gradient: batteryRoot.charging
                        ? chargingGradient
                        : (
                            batteryRoot.lowBattery
                                ? lowBatteryGradient
                                : normalGradient
                        )
                }
            }

            Text {
                width: parent.width
                height: parent.height
                x: 0
                y: 0.5

                text: batteryRoot.percentage

                color: Theme.bg0
                font.family: Theme.fontMain
                font.pixelSize: 10
                font.bold: true

                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        Rectangle {
            width: 2
            height: 7

            anchors.left: batteryBody.right
            anchors.leftMargin: 1
            anchors.verticalCenter: parent.verticalCenter

            radius: 1
            color: Qt.alpha(Theme.white, 0.55)
        }
    }
}
