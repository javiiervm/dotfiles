import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io // <--- ESTE ES EL IMPORT QUE FALTABA
import ".." // Para acceder a Theme.qml

Item {
    id: updatesRoot
    property int pendingCount: 0
    
    implicitWidth: layout.implicitWidth
    implicitHeight: 44
    
    visible: pendingCount > 0

    // --- PROCESO: Comprobador Único (Cero background CPU) ---
    // Se ejecuta una vez al arrancar Hyprland/Quickshell, y luego
    // solamente cuando la terminal de actualización se cierra.
    Process {
        id: updateCheckerProc
        command: ["bash", "-c", "p=$(/usr/bin/checkupdates 2>/dev/null | wc -l); a=$(/usr/bin/yay -Qua 2>/dev/null | wc -l); echo $((p+a))"]
        running: true // Esto lanza el proceso una única vez al instanciar el componente
        stdout: SplitParser {
            onRead: (data) => {
                var count = parseInt(data.trim());
                if (!isNaN(count)) updatesRoot.pendingCount = count;
            }
        }
    }

    // --- PROCESO: Lanzador del actualizador ---
    Process { 
        id: updateLauncherProc 
        onRunningChanged: {
            if (!running) {
                // Forzamos un refresco inmediato cuando se cierra la ventana de kitty
                updateCheckerProc.running = true;
            }
        }
    }

    function launchUpdater() {
        var scriptLines = [
            "#!/bin/bash",
            "echo -e '\\e[1;34m::\\e[1;37m System Updater\\e[0m'",
            "echo 'Checking packages...'",
            "p=$(checkupdates 2>/dev/null | wc -l)",
            "a=$(yay -Qua 2>/dev/null | wc -l)",
            "t=$((p+a))",
            "echo -e '\\e[1;36mPacman:\\e[0m '$p",
            "echo -e '\\e[1;36mAUR (yay):\\e[0m '$a",
            "echo -e '\\e[1;36mTotal:\\e[0m  '$t",
            "echo ''",
            "if [ $t -gt 0 ]; then",
            "  read -p 'Do you want to update now? [Y/n] ' ans",
            "  if [[ $ans != 'n' && $ans != 'N' ]]; then",
            "    yay -Syu || sudo pacman -Syu",
            "  fi",
            "fi",
            "echo -e '\\n\\e[1;32mDone.\\e[0m Press any key to exit...'",
            "read -n 1 -s"
        ];
        var fullScript = scriptLines.join("\n");
        updateLauncherProc.command = ["bash", "-c", "cat << 'EOF' > /tmp/qs_update.sh\n" + fullScript + "\nEOF\nchmod +x /tmp/qs_update.sh && kitty bash -c /tmp/qs_update.sh"];
        updateLauncherProc.running = true;
    }

    RowLayout {
        id: layout
        anchors.fill: parent
        spacing: 8

        Text {
            text: "󰮯"
            color: Theme.white
            font.family: Theme.fontIcons
            font.pixelSize: 16
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            text: updatesRoot.pendingCount.toString()
            color: Theme.white
            font.family: Theme.fontMain
            font.pixelSize: 14
            font.bold: true
            Layout.alignment: Qt.AlignVCenter
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: launchUpdater()
    }
}