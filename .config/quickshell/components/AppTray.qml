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

    // --- MONITOR DE APLICACIONES ---
    // Una única consulta a /proc por ciclo, sin shell persistente.
    Process {
        id: processMonitor

        command: [
            "pgrep", "-l", "-x",
            "spotify|Discord|discord|DiscordCore|vesktop|obs"
        ]

        // Primera comprobación inmediata al iniciar Quickshell.
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const names = this.text.trim()
                    .split("\n")
                    .map(line => line.replace(/^\d+\s+/, "").trim());

                trayRoot.appSpotify = names.includes("spotify");

                trayRoot.appDiscord =
                    names.includes("Discord") ||
                    names.includes("discord") ||
                    names.includes("DiscordCore") ||
                    names.includes("vesktop");

                trayRoot.appObs = names.includes("obs");
            }
        }
    }

    // Comprobaciones periódicas sin mantener Bash ejecutándose.
    Timer {
        id: processMonitorTimer
        interval: 5000
        running: true
        repeat: true

        onTriggered: {
            if (!processMonitor.running)
                processMonitor.running = true;
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