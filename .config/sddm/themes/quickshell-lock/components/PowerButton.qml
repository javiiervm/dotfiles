import QtQuick

Rectangle {
    id: root

    property real uiScale: 1.25

    property string symbol: "⏻"
    property color accentColor: "#ffffff"
    property string tooltip: "Power"

    // Corrección óptica independiente para cada icono.
    property real iconXOffset: 0
    property real iconYOffset: 0

    signal clicked()

    width: 44 * uiScale
    height: width
    radius: width / 2

    color: mouse.containsMouse
        ? Qt.rgba(
            accentColor.r,
            accentColor.g,
            accentColor.b,
            0.20
        )
        : "#14ffffff"

    border.width: 1

    border.color: mouse.containsMouse
        ? Qt.rgba(
            accentColor.r,
            accentColor.g,
            accentColor.b,
            0.65
        )
        : "#26ffffff"

    scale: mouse.containsMouse
        ? 1.06
        : 1.0

    Behavior on color {
        ColorAnimation {
            duration: 140
        }
    }

    Behavior on border.color {
        ColorAnimation {
            duration: 140
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: 140
            easing.type: Easing.OutCubic
        }
    }

    // ============================================================
    // ICON
    // ============================================================

    Text {
        anchors.centerIn: parent

        anchors.horizontalCenterOffset:
            root.iconXOffset * root.uiScale

        anchors.verticalCenterOffset:
            root.iconYOffset * root.uiScale

        text: root.symbol

        color: mouse.containsMouse
            ? root.accentColor
            : "#e6ffffff"

        font.family: "Adwaita Sans"
        font.pixelSize: 21 * root.uiScale
        font.weight: Font.DemiBold
    }

    // ============================================================
    // CLICK / HOVER
    // ============================================================

    MouseArea {
        id: mouse

        anchors.fill: parent

        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onClicked: root.clicked()
    }

    // ============================================================
    // TOOLTIP
    // ============================================================

    Rectangle {
        visible: mouse.containsMouse

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.top
        anchors.bottomMargin: 9 * root.uiScale

        width: tooltipText.implicitWidth
            + 18 * root.uiScale

        height: 28 * root.uiScale
        radius: 14 * root.uiScale

        color: "#b31e1e24"

        border.width: 1
        border.color: "#26ffffff"

        Text {
            id: tooltipText

            anchors.centerIn: parent

            text: root.tooltip

            color: "#e6ffffff"

            font.family: "Adwaita Sans"
            font.pixelSize: 11 * root.uiScale
        }
    }
}
