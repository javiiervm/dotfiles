import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".." // Para Theme.qml

Item {
    id: trayRoot
    
    // Estados internos
    property bool appSpotify: false
    property bool appDiscord: false
    property bool appObs: false

    // Ajustamos nuestro tamaño dinámicamente según si hay iconos visibles
    implicitWidth: appTrayLayout.implicitWidth
    implicitHeight: 44
    visible: appSpotify || appDiscord || appObs

    // Proceso auxiliar para matar aplicaciones
    Process { id: killProc }

    // --- MONITOR DE PROCESOS (Eficiente y Confiable) ---
    // pidof es rapidísimo. Un sleep de 3s aquí no despertará los núcleos pesados de la CPU.
    Process {
        id: processMonitor
        command: [
            "bash", "-c", 
            "while true; do " +
            "  s=$(pidof spotify >/dev/null && echo 1 || echo 0); " +
            "  d=$( (pidof Discord || pidof discord || pidof DiscordCore || pidof vesktop) >/dev/null && echo 1 || echo 0); " +
            "  o=$(pidof obs >/dev/null && echo 1 || echo 0); " +
            "  echo \"$s;$d;$o\"; " +
            "  sleep 3; " +
            "done"
        ]
        running: true
        stdout: SplitParser {
            onRead: (line) => {
                var parts = line.trim().split(";");
                if (parts.length >= 3) {
                    trayRoot.appSpotify = parts[0] === "1";
                    trayRoot.appDiscord = parts[1] === "1";
                    trayRoot.appObs     = parts[2] === "1";
                }
            }
        }
    }

    RowLayout {
        id: appTrayLayout
        anchors.fill: parent
        spacing: 12

        // --- SPOTIFY ---
        Text {
            visible: trayRoot.appSpotify
            text: ""
            color: Theme.white
            font.family: Theme.fontIcons
            font.pixelSize: 15
            Layout.alignment: Qt.AlignVCenter
            MouseArea { 
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor; 
                onClicked: { 
                    killProc.command = ["bash", "-c", "pkill -9 -ix spotify"]; 
                    killProc.running = true; 
                    trayRoot.appSpotify = false; 
                } 
            }
        }
        
        // --- DISCORD ---
        Text {
            visible: trayRoot.appDiscord
            text: ""
            color: Theme.white
            font.family: Theme.fontIcons
            font.pixelSize: 14 
            Layout.alignment: Qt.AlignVCenter
            MouseArea { 
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor; 
                onClicked: { 
                    killProc.command = ["bash", "-c", "pkill -9 -ix discord || pkill -9 -x DiscordCore || pkill -9 -ix vesktop"]; 
                    killProc.running = true; 
                    trayRoot.appDiscord = false; 
                } 
            }
        }
        
        // --- OBS ---
        Text {
            visible: trayRoot.appObs
            text: "󰑋"
            color: Theme.white
            font.family: Theme.fontIcons
            font.pixelSize: 15
            Layout.alignment: Qt.AlignVCenter
            MouseArea { 
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor; 
                onClicked: { 
                    killProc.command = ["bash", "-c", "pkill -9 -ix obs"]; 
                    killProc.running = true; 
                    trayRoot.appObs = false; 
                } 
            }
        }
    }
}