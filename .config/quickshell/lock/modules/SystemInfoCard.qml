import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "." as Local
import "../../"

Local.Card {
    id: root
    implicitWidth: 260 * Theme.scale
    implicitHeight: 160 * Theme.scale // Volvemos a la altura original

    property string wm: "Hyprland"
    property string user: "javier"
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

    // --- CONTENEDOR PRINCIPAL CENTRADO ---
    Column {
        anchors.centerIn: parent
        spacing: 14 * Theme.scale

        RowLayout {
            spacing: 18 * Theme.scale
            
            // --- LOGO HEXAGONAL (CachyOS / Hyprland style) ---
            Item {
                Layout.preferredWidth: 55 * Theme.scale
                Layout.preferredHeight: 55 * Theme.scale
                Layout.alignment: Qt.AlignVCenter

                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        
                        const cx = width / 2;
                        const cy = height / 2;
                        const r = Math.min(width, height) / 2 - (3 * Theme.scale); // Radio con padding
                        
                        ctx.beginPath();
                        // Dibujar un hexágono regular
                        for (let i = 0; i < 6; i++) {
                            // Desfase de PI/6 para que los lados queden rectos en vertical
                            const angle = (Math.PI / 3) * i + (Math.PI / 6); 
                            const x = cx + r * Math.cos(angle);
                            const y = cy + r * Math.sin(angle);
                            if (i === 0) ctx.moveTo(x, y);
                            else ctx.lineTo(x, y);
                        }
                        ctx.closePath();
                        
                        ctx.lineWidth = 3.5 * Theme.scale;
                        ctx.strokeStyle = Theme.blue; // Azul acorde a tu captura
                        ctx.stroke();
                    }
                }
            }

            // --- TEXTOS ---
            ColumnLayout {
                spacing: 4 * Theme.scale
                Layout.alignment: Qt.AlignVCenter

                Text { text: "WM   : " + root.wm; color: Theme.white; font.pixelSize: 11 * Theme.scale; font.family: Theme.fontMain; font.weight: Font.DemiBold }
                Text { text: "USER : " + root.user; color: Theme.white; font.pixelSize: 11 * Theme.scale; font.family: Theme.fontMain; font.weight: Font.DemiBold }
                Text { text: "UP   : " + root.uptime; color: Theme.white; font.pixelSize: 11 * Theme.scale; font.family: Theme.fontMain; font.weight: Font.DemiBold }
                Text { text: "BATT : " + (root.charging ? "(+) " : "") + root.battery + "%"; color: Theme.white; font.pixelSize: 11 * Theme.scale; font.family: Theme.fontMain; font.weight: Font.DemiBold }
            }
        }

        // --- INDICADORES INFERIORES (Workspaces / Dots) ---
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6 * Theme.scale
            
            Repeater {
                model: 8
                Rectangle {
                    width: 10 * Theme.scale
                    height: 10 * Theme.scale
                    radius: 5 * Theme.scale
                    // Usamos Theme.blue para que haga juego con el hexágono
                    color: index === 1 ? Theme.blue : Qt.alpha(Theme.white, 0.25)
                }
            }
        }
    }
}