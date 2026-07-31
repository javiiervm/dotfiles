import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "." as Local
import "../../"

Item {
    id: root
    // Mismo ancho que las tarjetas izquierdas para mantener la cuadrícula alineada
    implicitWidth: 260 * Theme.scale 
    // Altura ideal para que las tres divisiones formen cuadrados perfectos
    implicitHeight: 76 * Theme.scale 

    property int cpuTemp: 0
    property int battery: 0
    property int volume: 0

    Process {
        id: statsProc
        // Lógica de ultra-bajo consumo heredada de tu isla dinámica
        command: [
            "bash", "-c",
            "ct=0; for f in /sys/class/hwmon/hwmon*/name; do " +
            "  read name < \"$f\" 2>/dev/null; " +
            "  if [ \"$name\" = \"k10temp\" ] || [ \"$name\" = \"zenpower\" ]; then " +
            "    read t < \"${f%/*}/temp1_input\" 2>/dev/null; ct=$((t / 1000)); break; " +
            "  fi; " +
            "done; " +
            "read cap < /sys/class/power_supply/BAT*/capacity 2>/dev/null || cap=100; " +
            "vf=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || echo '0 0'); " +
            "vol=${vf#* }; vol=${vol% \\[MUTED\\]}; " +
            "vol_pct=$(echo \"$vol\" | awk '{print int($1*100)}'); " +
            "echo \"${ct};${cap};${vol_pct}\""
        ]
        stdout: SplitParser {
            onRead: data => {
                var parts = data.trim().split(";");
                if (parts.length >= 3) {
                    root.cpuTemp = parseInt(parts[0]) || 0;
                    root.battery = parseInt(parts[1]) || 0;
                    root.volume = parseInt(parts[2]) || 0;
                }
            }
        }
    }

    Timer {
        interval: 3000 // Actualizamos cada 3 segundos
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: statsProc.running = true
    }

    RowLayout {
        anchors.fill: parent
        spacing: 16 * Theme.scale // Espaciado elegante entre los tres iconos

        // Componente reutilizable para cada cuadradito 
        component StatSquare : Rectangle {
            id: squareRoot
            property string iconTxt: ""
            property string valTxt: ""

            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Qt.alpha(Theme.white, 0.04) // Transparencia sutil 
            radius: 14 * Theme.scale
            border.color: Qt.alpha(Theme.white, 0.06)
            border.width: 1

            Column {
                anchors.centerIn: parent
                spacing: 6 * Theme.scale

                Text {
                    text: squareRoot.iconTxt
                    font.family: Theme.fontIcons
                    font.pixelSize: 22 * Theme.scale
                    color: Theme.blue // Cyan/azul como en image_23b87e.jpg
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                
                Text {
                    text: squareRoot.valTxt
                    font.family: Theme.fontMain
                    font.pixelSize: 11 * Theme.scale
                    font.weight: Font.DemiBold
                    color: Theme.white
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }

        // Instanciamos las tres tarjetas con sus respectivos datos
        StatSquare { 
            iconTxt: "󰔏" // Icono de Termómetro
            valTxt: root.cpuTemp + "°C" 
        }
        
        StatSquare { 
            iconTxt: "󰁹" // Icono de Batería
            valTxt: root.battery + "%" 
        }
        
        StatSquare { 
            iconTxt: "󰕾" // Icono de Altavoz
            valTxt: root.volume + "%" 
        }
    }
}