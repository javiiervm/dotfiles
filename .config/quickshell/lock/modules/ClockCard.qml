import QtQuick
import "../../"

Column {
    spacing: 12
    anchors.horizontalCenter: parent.horizontalCenter

    QtObject {
        id: clock
        property var date: new Date()
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: clock.date = new Date()
    }

    Row {
        spacing: 8
        anchors.horizontalCenter: parent.horizontalCenter

        // Horas
        Text {
            text: Qt.formatTime(clock.date, "hh")
            font.pixelSize: 140 
            font.family: "Bebas Neue"
            font.weight: Font.Bold // Forzamos el grosor
            color: Theme.white
            height: 140
            verticalAlignment: Text.AlignVCenter
        }

        // Minutos y AM/PM apilados
        Column {
            spacing: -12
            anchors.verticalCenter: parent.verticalCenter

            // Minutos
            Text {
                text: Qt.formatTime(clock.date, "mm")
                font.pixelSize: 75
                font.family: "Bebas Neue"
                font.weight: Font.Bold // Forzamos el grosor
                color: Theme.grey1
            }
            
            // AM / PM
            Text {
                text: Qt.formatTime(clock.date, "AP")
                font.pixelSize: 32
                font.family: "Bebas Neue"
                font.weight: Font.Bold // Forzamos el grosor
                color: Qt.alpha(Theme.grey1, 0.6) 
            }
        }
    }

    // Fecha inferior
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.formatDate(clock.date, "dddd").toUpperCase() + "  ·  " + Qt.formatDate(clock.date, "d MMM").toUpperCase()
        font.pixelSize: 13
        font.weight: Font.Bold
        font.family: Theme.fontMain
        font.letterSpacing: 2
        color: Theme.grey1 
    }
}