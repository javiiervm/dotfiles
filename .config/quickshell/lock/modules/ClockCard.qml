import QtQuick
import "." as Local
import "../../"

Item {
    id: root
    implicitWidth: mainRow.width
    implicitHeight: dateText.y + dateText.height

    property string h1: "1"
    property string h2: "5"
    property string m1: "4"
    property string m2: "3"
    property string ampm: "PM"
    property string dateStr: "FRIDAY  ·  31 JUL"

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            var d = new Date()
            var hours = d.getHours()
            var mins = d.getMinutes()
            
            root.ampm = hours >= 12 ? "PM" : "AM"
            hours = hours % 12
            hours = hours ? hours : 12
            
            var hStr = (hours < 10 ? "0" : "") + hours
            var mStr = (mins < 10 ? "0" : "") + mins
            
            root.h1 = hStr.charAt(0)
            root.h2 = hStr.charAt(1)
            root.m1 = mStr.charAt(0)
            root.m2 = mStr.charAt(1)

            var days = ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"]
            var months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
            root.dateStr = days[d.getDay()] + "  ·  " + d.getDate() + " " + months[d.getMonth()]
        }
    }

    Row {
        id: mainRow
        spacing: 8 * Theme.scale // Separación entre bloque de horas y de minutos ligeramente más reducida

        // --- SECCIÓN HORA ---
        Item {
            id: hoursBox
            width: hRow.width
            height: 116 * Theme.scale 

            Row {
                id: hRow
                spacing: -6 * Theme.scale // Junta más entre sí las cifras de las horas

                Text {
                    text: root.h1
                    font.family: Theme.fontMain
                    font.pixelSize: 110 * Theme.scale
                    font.weight: Font.Bold
                    color: Theme.white
                    y: 6 * Theme.scale 
                }

                Text {
                    text: root.h2
                    font.family: Theme.fontMain
                    font.pixelSize: 110 * Theme.scale
                    font.weight: Font.Bold
                    color: Theme.white
                    y: 0
                }
            }
        }

        // --- SECCIÓN MINUTOS Y AM/PM ---
        Item {
            id: minutesBox
            width: mRow.width
            height: hoursBox.height

            // Minutos
            Row {
                id: mRow
                spacing: -3 * Theme.scale // Junta más entre sí las cifras de los minutos

                Text {
                    text: root.m1
                    font.family: Theme.fontMain
                    font.pixelSize: 70 * Theme.scale
                    font.weight: Font.Bold
                    color: Qt.alpha(Theme.white, 0.85)
                    y: 0
                }

                Text {
                    text: root.m2
                    font.family: Theme.fontMain
                    font.pixelSize: 70 * Theme.scale
                    font.weight: Font.Bold
                    color: Qt.alpha(Theme.white, 0.85)
                    y: 5 * Theme.scale 
                }
            }

            // AM / PM
            Text {
                id: amPmText
                text: root.ampm
                font.family: Theme.fontMain
                font.pixelSize: 22 * Theme.scale
                font.weight: Font.Bold
                color: Theme.blue
                anchors.bottom: parent.bottom
                anchors.right: mRow.right
            }
        }
    }

    // Fecha
    Text {
        id: dateText
        text: root.dateStr
        font.family: Theme.fontMain
        font.pixelSize: 12 * Theme.scale
        font.weight: Font.Bold
        font.letterSpacing: 2
        color: Qt.alpha(Theme.white, 0.8)
        anchors.top: mainRow.bottom
        anchors.topMargin: 12 * Theme.scale
        anchors.horizontalCenter: parent.horizontalCenter
    }
}