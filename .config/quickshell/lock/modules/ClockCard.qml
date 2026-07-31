import QtQuick

// Reloj grande estilo "02:46 PM" + fecha "WEDNESDAY · 1 JUL"
// Sin tarjeta/fondo propio: se ve mejor flotando directamente sobre el wallpaper,
// igual que en la referencia.
Column {
    spacing: 4

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
        spacing: 6
        anchors.horizontalCenter: parent.horizontalCenter

        Text {
            text: Qt.formatTime(clock.date, "hh:mm")
            font.pixelSize: 76
            font.weight: Font.Black
            font.family: "JetBrains Mono Nerd Font"
            color: "#7ee6ff"   // cian, igual que el "02:46" de la captura
        }
        Text {
            text: Qt.formatTime(clock.date, "AP")
            font.pixelSize: 22
            font.weight: Font.Bold
            font.family: "JetBrains Mono Nerd Font"
            color: "#e8f4ff"
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.formatDate(clock.date, "dddd").toUpperCase() + "  ·  " + Qt.formatDate(clock.date, "d MMM").toUpperCase()
        font.pixelSize: 14
        font.family: "JetBrains Mono Nerd Font"
        font.letterSpacing: 1
        color: "#9fb3c8"
    }
}
