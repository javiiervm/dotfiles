import QtQuick
import Quickshell.Io
import "." as Local

// Tarjeta tipo "neofetch" minimal: WM, usuario, uptime, batería.
// Lee el JSON que produce scripts/fetch.sh (ajusta la ruta si lo colocas
// en otro sitio, p.ej. ~/.config/quickshell/scripts/fetch.sh).
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
        command: ["bash", Qt.resolvedUrl("../scripts/fetch.sh").toString().replace("file://", "")]
        stdout: SplitParser {
            onRead: data => {
                try {
                    const j = JSON.parse(data)
                    root.wm = j.wm
                    root.user = j.user
                    root.uptime = j.uptime
                    root.battery = j.battery
                    root.charging = j.charging
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 30 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: fetchProc.running = true
    }

    content: Row {
        anchors.fill: parent
        spacing: 14

        // Logo simple: un hexágono hecho con Canvas, sustituye por tu
        // logo SVG de distro si prefieres (Image { source: "distro.svg" })
        Canvas {
            width: 48
            height: 48
            anchors.verticalCenter: parent.verticalCenter
            onPaint: {
                const ctx = getContext("2d")
                ctx.strokeStyle = "#eef4fb"
                ctx.lineWidth = 3
                ctx.beginPath()
                for (let i = 0; i < 6; i++) {
                    const angle = Math.PI / 3 * i - Math.PI / 2
                    const x = width / 2 + (width / 2 - 4) * Math.cos(angle)
                    const y = height / 2 + (height / 2 - 4) * Math.sin(angle)
                    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
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
                color: "#eef4fb"; font.pixelSize: 13; font.family: "JetBrains Mono Nerd Font"
            }
            Text {
                text: "USER : " + root.user
                color: "#eef4fb"; font.pixelSize: 13; font.family: "JetBrains Mono Nerd Font"
            }
            Text {
                text: "UP   : " + root.uptime
                color: "#eef4fb"; font.pixelSize: 13; font.family: "JetBrains Mono Nerd Font"
            }
            Text {
                text: "BATT : " + (root.charging ? "(+) " : "") + root.battery + "%"
                color: "#eef4fb"; font.pixelSize: 13; font.family: "JetBrains Mono Nerd Font"
            }

            // Fila de dots — puramente decorativa aquí (uno resaltado),
            // en Caelestia representa workspaces; conéctala a
            // Hyprland.workspaces si quieres ese comportamiento real.
            Row {
                spacing: 6
                topPadding: 4
                Repeater {
                    model: 8
                    Rectangle {
                        width: 10; height: 10; radius: 5
                        color: index === 1 ? "#c8f04a" : "#3a4356"
                    }
                }
            }
        }
    }
}
