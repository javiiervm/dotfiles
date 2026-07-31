import QtQuick
import Quickshell.Io
import "." as Local
import "../../"

Local.Card {
    id: root
    implicitWidth: 260
    implicitHeight: 170

    property string wm: "—"
    property string user: "—"
    property string uptime: "—"
    property int battery: 0
    property bool charging: false

    Process {
        id: fetchProc
        command: ["bash", Qt.resolvedUrl("../scripts/fetch.sh").toString().replace("file://", "")] //[cite: 19]
        stdout: SplitParser {
            onRead: data => {
                try {
                    const j = JSON.parse(data)
                    root.wm = j.wm
                    root.user = j.user
                    root.uptime = j.uptime
                    root.battery = j.battery
                    root.charging = j.charging //[cite: 19]
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 30 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: fetchProc.running = true //[cite: 19]
    }

    content: Row {
        anchors.fill: parent
        spacing: 14

        Canvas {
            width: 48
            height: 48
            anchors.verticalCenter: parent.verticalCenter
            onPaint: {
                const ctx = getContext("2d")
                ctx.strokeStyle = Theme.blue
                ctx.lineWidth = 3
                ctx.beginPath()
                for (let i = 0; i < 6; i++) {
                    const angle = Math.PI / 3 * i - Math.PI / 2
                    const x = width / 2 + (width / 2 - 4) * Math.cos(angle)
                    const y = height / 2 + (height / 2 - 4) * Math.sin(angle)
                    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y) //[cite: 19]
                }
                ctx.closePath()
                ctx.stroke()
            }
        }

        Column {
            spacing: 6
            anchors.verticalCenter: parent.verticalCenter

            Text {
                text: "WM   : " + root.wm
                color: Theme.white; font.pixelSize: 13; font.family: Theme.fontMain
            }
            Text {
                text: "USER : " + root.user
                color: Theme.white; font.pixelSize: 13; font.family: Theme.fontMain
            }
            Text {
                text: "UP   : " + root.uptime
                color: Theme.white; font.pixelSize: 13; font.family: Theme.fontMain
            }
            Text {
                text: "BATT : " + (root.charging ? "(+) " : "") + root.battery + "%"
                color: Theme.white; font.pixelSize: 13; font.family: Theme.fontMain
            }

            Row {
                spacing: 6
                topPadding: 4
                Repeater {
                    model: 8
                    Rectangle {
                        width: 10; height: 10; radius: 5
                        color: index === 1 ? Theme.blue : Qt.alpha(Theme.white, 0.2) //[cite: 19]
                    }
                }
            }
        }
    }
}
