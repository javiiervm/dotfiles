import QtQuick
import QtQuick.Layouts
import ".."

Rectangle {
    id: batteryRoot

    property int percentage: 0
    property bool charging: false

    Layout.preferredWidth: 31
    Layout.preferredHeight: 18
    Layout.alignment: Qt.AlignVCenter

    radius: height / 2
    color: Theme.grey1

    readonly property bool lowBattery: percentage < 21

    property real fillWidth:
        width * (Math.max(0, Math.min(percentage, 100)) / 100.0)

    Behavior on fillWidth {
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutQuint
        }
    }

    /*
     * GRADIENTE NORMAL
     */
    Gradient {
        id: normalGradient

        orientation: Gradient.Vertical

        GradientStop {
            position: 0.0
            color: "#ffffff"
        }

        GradientStop {
            position: 0.5
            color: '#c4c4c4'
        }

        GradientStop {
            position: 1.0
            color: '#bebebe'
        }
    }

    /*
     * GRADIENTE CARGANDO
     */
    Gradient {
        id: chargingGradient

        orientation: Gradient.Vertical

        GradientStop {
            position: 0.0
            color: '#65efe8'
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

    /*
     * GRADIENTE BATERÍA BAJA
     */
    Gradient {
        id: lowBatteryGradient

        orientation: Gradient.Vertical

        GradientStop {
            position: 0.0
            color: '#ff9d60'
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

    /*
     * RELLENO
     *
     * Esta es exactamente la misma geometría del icono original:
     *
     * - empieza en el borde izquierdo
     * - ocupa toda la altura
     * - tiene exactamente el mismo radio que el fondo
     * - únicamente se recorta según el porcentaje
     */
    Item {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        width: batteryRoot.fillWidth

        clip: true

        Rectangle {
            width: batteryRoot.width
            height: batteryRoot.height

            radius: batteryRoot.radius

            gradient: batteryRoot.charging
                ? chargingGradient
                : (
                    batteryRoot.lowBattery
                        ? lowBatteryGradient
                        : normalGradient
                )
        }
    }

    /*
     * PORCENTAJE
     */
    RowLayout {
        anchors.centerIn: parent
        spacing: 1

        Text {
            text: percentage

            color: Theme.bg0

            font.family: Theme.fontMain
            font.pixelSize: 11
            font.bold: true

            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}