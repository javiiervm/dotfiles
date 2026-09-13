import QtQuick

Item {
    id: root

    property real uiScale: 1.25

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

            var days = [
                "SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY",
                "THURSDAY", "FRIDAY", "SATURDAY"
            ]
            var months = [
                "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
                "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"
            ]

            root.dateStr =
                days[d.getDay()] + "  ·  " +
                d.getDate() + " " + months[d.getMonth()]
        }
    }

    Row {
        id: mainRow
        spacing: 8 * root.uiScale

        Item {
            id: hoursBox
            width: hRow.width
            height: 116 * root.uiScale

            Row {
                id: hRow
                spacing: -6 * root.uiScale

                Text {
                    text: root.h1
                    font.family: "Adwaita Sans"
                    font.pixelSize: 110 * root.uiScale
                    font.weight: Font.Bold
                    color: "#ffffff"
                    y: 6 * root.uiScale
                }

                Text {
                    text: root.h2
                    font.family: "Adwaita Sans"
                    font.pixelSize: 110 * root.uiScale
                    font.weight: Font.Bold
                    color: "#ffffff"
                }
            }
        }

        Item {
            width: mRow.width
            height: hoursBox.height

            Row {
                id: mRow
                spacing: -3 * root.uiScale

                Text {
                    text: root.m1
                    font.family: "Adwaita Sans"
                    font.pixelSize: 70 * root.uiScale
                    font.weight: Font.Bold
                    color: "#d9ffffff"
                }

                Text {
                    text: root.m2
                    font.family: "Adwaita Sans"
                    font.pixelSize: 70 * root.uiScale
                    font.weight: Font.Bold
                    color: "#d9ffffff"
                    y: 5 * root.uiScale
                }
            }

            Text {
                text: root.ampm
                font.family: "Adwaita Sans"
                font.pixelSize: 22 * root.uiScale
                font.weight: Font.Bold
                color: "#61afef"
                anchors.bottom: parent.bottom
                anchors.right: mRow.right
            }
        }
    }

    Text {
        id: dateText
        text: root.dateStr
        font.family: "Adwaita Sans"
        font.pixelSize: 12 * root.uiScale
        font.weight: Font.Bold
        font.letterSpacing: 2
        color: "#ccffffff"
        anchors.top: mainRow.bottom
        anchors.topMargin: 12 * root.uiScale
        anchors.horizontalCenter: parent.horizontalCenter
    }
}
