import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import "."
import "components"

ShellRoot {
    id: root

    property int batCap: 0
    property string batStat: ""
    property int vol: 0
    property bool volMute: false
    property string volDesc: ""
    property string wifiSsid: ""
    property string wifiSig: ""
    property string wifiFreq: ""
    property string btStat: "off"
    property string btDev: ""
    property string perfMode: "balanced"
    property bool dnd: false
 
    property int notifCount: 0
    property bool hasUnread: false
    property int cpuUsage: 0
    property int memUsage: 0

    // Nuevos estados para el NotificationCenter
    property bool airplaneMode: false
    property bool caffeineMode: false

    // --- NUEVO ESTADO: ACTUALIZACIONES ---
    property int pendingUpdates: 0

    // --- NUEVO ESTADO: APP TRAY ---
    property bool appSpotify: false
    property bool appDiscord: false
    property bool appObs: false

    property bool isNotifOpen: false
    property string activeMenuTitle: ""
    property string activeMenuInfo1: ""
    property string activeMenuInfo2: ""
    property color activeMenuAccent: "#ffffff"
    property int activeMenuOffset: 52 
    property bool isMenuOpen: false
    property bool isMenuVisible: false

    // --- ESTADOS PARA CAVA VISUALIZER ---
    property bool isPlayingMedia: false
    property bool isWorkspaceEmpty: true
    property bool showCavaVisualizer: isPlayingMedia && isWorkspaceEmpty

    property string cavaColor: Theme.blue // Color inicial

    property alias sharedNotifModel: sharedNotifModel
    ListModel { id: sharedNotifModel }
    ListModel { id: popupModel }
    ListModel {
        id: cavaModel
        Component.onCompleted: {
            // Inicializamos las 120 barras a altura 0
            for (var i = 0; i < 120; i++) {
                append({"barHeight": 0});
            }
        }
    }

    function clearNotifications() { cmdProc.command = ["sh", "-c", "echo CLEAR > /tmp/qs_notif_cmd"]; cmdProc.running = true }
    function toggleDnd() { cmdProc.command = ["sh", "-c", "echo TOGGLE_DND > /tmp/qs_notif_cmd"]; cmdProc.running = true }
    function removePopup(notifId) {
        for (var i = 0; i < popupModel.count; i++) {
            if (popupModel.get(i).nId === notifId) {
                popupModel.remove(i);
                break;
            }
        }
    }
    
    // Procesos separados para evitar bloqueos si clicas muy rápido
    Process { id: cmdProc }
    Process { id: wifiProc; command: ["sh", "-c", "nmcli radio wifi | grep -q 'enabled' && nmcli radio wifi off || nmcli radio wifi on"] }
    Process { id: btProc; command: ["sh", "-c", "rfkill toggle bluetooth"] }
    Process { id: airplaneProc; command: ["sh", "-c", "rfkill toggle all"] }
    Process { id: caffeineProc; command: ["sh", "-c", "pidof hypridle > /dev/null && killall hypridle || hypridle &"] }

    // --- NUEVOS PROCESOS: ACTUALIZADOR DE SISTEMA ---
    Process { 
        id: updateLauncherProc 
        onRunningChanged: {
            // Cuando 'running' pasa a false, significa que la terminal se acaba de cerrar
            if (!running) {
                // Apagamos y encendemos el comprobador para forzar un chequeo instantáneo
                updateCheckerProc.running = false;
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
        // Force execution on current workspace via hyprctl
        updateLauncherProc.command = ["bash", "-c", "cat << 'EOF' > /tmp/qs_update.sh\n" + fullScript + "\nEOF\nchmod +x /tmp/qs_update.sh && kitty bash -c /tmp/qs_update.sh"];
        updateLauncherProc.running = true;
    }

    Process {
        id: updateCheckerProc
        // Se ha cambiado 'grep -c . || echo 0' por 'wc -l' para evitar errores matemáticos en Bash
        command: ["bash", "-c", "p=$(/usr/bin/checkupdates 2>/dev/null | wc -l); a=$(/usr/bin/yay -Qua 2>/dev/null | wc -l); echo $((p+a))"]
        running: true
        stdout: SplitParser {
            onRead: (data) => {
                var count = parseInt(data.trim());
                console.log("DEBUG UPDATES: " + count); 
                if (!isNaN(count)) {
                    root.pendingUpdates = count;
                }
            }
        }
    }

    // --- NUEVOS PROCESOS: CUSTOM APP TRAY ---
    Process {
        id: appTrayMonitor
        // Verifica si los procesos existen cada 3 segundos sin gastar recursos
        command: ["bash", "-c", "while true; do s=$(pgrep -x spotify >/dev/null && echo 1 || echo 0); d=$( (pgrep -x Discord >/dev/null || pgrep -x discord >/dev/null || pgrep -x DiscordCore >/dev/null) && echo 1 || echo 0); o=$(pgrep -x obs >/dev/null && echo 1 || echo 0); echo \"$s;$d;$o\"; sleep 3; done"]
        running: true
        stdout: SplitParser {
            onRead: (data) => {
                var parts = data.trim().split(";");
                if (parts.length >= 3) {
                    root.appSpotify = parts[0] === "1";
                    root.appDiscord = parts[1] === "1";
                    root.appObs     = parts[2] === "1";
                }
            }
        }
    }
    // ------------------------------------------------

    // 1. Monitor de Escritorio y Media
    Process {
        id: mediaWorkspaceMonitor
        // Verifica con hyprctl las ventanas y con playerctl la música
        command: ["bash", "-c", "while true; do w=$(hyprctl activeworkspace -j | jq '.windows'); p=$(playerctl status 2>/dev/null | grep -q 'Playing' && echo 1 || echo 0); echo \"$w;$p\"; sleep 2; done"]
        running: true
        stdout: SplitParser {
            onRead: (data) => {
                var parts = data.trim().split(";");
                if (parts.length >= 2) {
                    root.isWorkspaceEmpty = (parseInt(parts[0]) === 0);
                    root.isPlayingMedia = (parts[1] === "1");
                }
            }
        }
    }

    // 2. Motor de Visualización (Cava)
    Process {
        id: cavaVisualizerProc
        command: [
            "bash", "-c", 
            "cat << 'EOF' > /tmp/qs_cava.conf\n" +
            "[general]\n" +
            "bars=120\n" +
            "framerate=60\n" +
            "[output]\n" +
            "method=raw\n" +
            "raw_target=/dev/stdout\n" +
            "data_format=ascii\n" +
            "ascii_max_range=100\n" +
            "[smoothing]\n" +
            "noise_reduction=80\n" +
            "monstercat=1\n" +
            "EOF\n" +
            "cava -p /tmp/qs_cava.conf"
        ]
        running: root.showCavaVisualizer 
        stdout: SplitParser {
            onRead: (data) => {
                var rawValues = data.trim().split(";");
                for(var i = 0; i < 120; i++) {
                    var val = parseInt(rawValues[i]);
                    // Actualizamos exclusivamente la altura de cada barra en el modelo
                    cavaModel.setProperty(i, "barHeight", isNaN(val) ? 0 : val);
                }
            }
        }
    }

    onIsMenuOpenChanged: {
        if (isMenuOpen) { 
            isMenuVisible = true
            closeTimer.stop()
        } else { 
            closeTimer.start()
        }
    }

    Process {
        id: colorMonitorProc
        command: [
            "bash", "-c", 
            // EL SALVAVIDAS: Forzamos la creación del archivo para que inotifywait no crashee al arrancar
            "touch /tmp/current_wallpaper; " + 
            "if [ -s /tmp/current_wallpaper ]; then python3 /home/javier/.config/quickshell/scripts/cava_color.py \"$(cat /tmp/current_wallpaper)\"; fi; " +
            "while inotifywait -q -e close_write,modify /tmp/current_wallpaper; do " +
            "  python3 /home/javier/.config/quickshell/scripts/cava_color.py \"$(cat /tmp/current_wallpaper)\"; " +
            "done"
        ]
        running: true
        stdout: SplitParser {
            onRead: (data) => {
                var hexColor = data.trim();
                if (hexColor.startsWith("#")) {
                    root.cavaColor = hexColor;
                }
            }
        }
    }

    Timer { id: closeTimer; interval: 300; onTriggered: root.isMenuVisible = false }

    Launcher { 
        id: mainLauncher 
        onRequestIslandMsg: function(icon, color, text) {
            if (typeof islandWidget !== "undefined") {
                islandWidget.triggerMsg(icon, color, text);
            }
        }
    }

    NotificationCenter {
        id: notifCenterWindow
        visible_state: root.isNotifOpen
        dndState: root.dnd
        modelData: sharedNotifModel
        
        wifiState: root.wifiSsid !== "" && root.wifiSsid !== "disconnected" && root.wifiSsid !== "Disconnected"
        btState: root.btStat === "on"
        airplaneState: root.airplaneMode
        caffeineState: root.caffeineMode
        
        onRequestClose: { root.isNotifOpen = false }
        onToggleDndRequested: { root.toggleDnd() }
        onClearRequested: { root.clearNotifications() }

        onToggleWifiRequested: { wifiProc.running = true }
        onToggleBtRequested: { btProc.running = true }
        onToggleAirplaneRequested: {
            airplaneProc.running = true
            root.airplaneMode = !root.airplaneMode
        }
        onToggleCaffeineRequested: {
            caffeineProc.running = true
            root.caffeineMode = !root.caffeineMode
        }
        onPowerRequested: { console.log("Acción de power pulsada") }
    }

    GlobalShortcut {
        name: "launcher"
        onPressed: { mainLauncher.toggle() }
    }

    Process {
        id: backendProc
        command: ["/bin/bash", "-c", "mkdir -p /tmp/fake_bin; printf '#!/bin/bash\\necho 0\\n' > /tmp/fake_bin/swaync-client; chmod +x /tmp/fake_bin/swaync-client; export PATH=\"/tmp/fake_bin:$PATH\"; /home/javier/.config/quickshell/scripts/backend_daemon.sh"]
        running: true
        stdout: SplitParser {
            onRead: (data) => {
                var fields = data.trim().split("|")
                if (fields.length >= 15) {
                    root.batCap = parseInt(fields[0]) || 0
                    root.batStat = fields[1].trim()
                    root.vol = parseInt(fields[2]) || 0
                    root.wifiSsid = fields[3].trim()
                    root.wifiSig = fields[4].trim()
                    root.wifiFreq = fields[5].trim()
                    root.btStat = fields[6].trim()
                    root.btDev = fields[7].trim()
                    root.perfMode = fields[8].trim()
                    root.dnd = (fields[9].trim() === "true")
                    //root.notifCount = parseInt(fields[10]) || 0
                    root.volMute = (fields[11].trim() === "true")
                    root.volDesc = fields[12].trim()
                    root.cpuUsage = parseInt(fields[13]) || 0
                    root.memUsage = parseInt(fields[14]) || 0
                }
            }
        }
    }

    Process {
        id: notifProc
        command: ["python3", "-OO", "/home/javier/.config/quickshell/scripts/notif_daemon.py"]
        running: true
        stdout: SplitParser {
            onRead: (line) => {
                if (line.startsWith("STATE|")) {
                    var state = JSON.parse(line.substring(6))
                    root.dnd = state.dnd
                    root.notifCount = state.count
                    sharedNotifModel.clear()
                    for (var i = 0; i < state.notifications.length; i++) {
                        sharedNotifModel.append(state.notifications[i])
                    }
                } else if (line.startsWith("POPUP|")) {
                    if (!root.isNotifOpen) {
                        root.hasUnread = true
                        var n = JSON.parse(line.substring(6))
                        popupModel.insert(0, { "nId": n.id, "pApp": n.app, "pTitle": n.title, "pBody": n.body, "pIcon": n.icon })
                    }
                }
            }
        }
    }

    PanelWindow {
        id: osdWindow
        screen: Quickshell.screens[0]
        anchors { top: true; right: true }
        margins { top: 50; right: 15 }
        implicitWidth: 360 
        implicitHeight: popupColumn.implicitHeight
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayershell.Overlay
        visible: popupModel.count > 0

        Column {
            id: popupColumn
            width: parent.width
            spacing: 10
            Repeater {
                model: popupModel
                delegate: Rectangle {
                    id: popupItem
                    width: 360; height: 80; radius: 15
                    color: Qt.alpha(Theme.bg0, 0.95); border.color: Qt.alpha(Theme.white, 0.1); border.width: 1
                    transform: Translate { id: slideTrans; x: 400 }
                    Component.onCompleted: { slideIn.start(); hideTimer.start(); }
                    NumberAnimation { id: slideIn; target: slideTrans; property: "x"; to: 0; duration: 400; easing.type: Easing.OutBack }
                    NumberAnimation { id: slideOut; target: slideTrans; property: "x"; to: 400; duration: 300; easing.type: Easing.InBack; onFinished: root.removePopup(nId) }
                    Timer { id: hideTimer; interval: 5000; onTriggered: slideOut.start() }
                    MouseArea { anchors.fill: parent; onClicked: slideOut.start() }
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 12; spacing: 12
                        Image { 
                            Layout.preferredWidth: 35; Layout.preferredHeight: 35; 
                            source: pIcon.startsWith("/") ? "file://" + pIcon : "image://icon/" + pIcon; fillMode: Image.PreserveAspectFit 
                        }
                        ColumnLayout {
                            spacing: 2
                            Text { text: pApp; color: Theme.blue; font.pixelSize: 10; font.bold: true }
                            Text { text: pTitle; color: Theme.white; font.pixelSize: 12; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                            Text { text: pBody; color: Theme.grey1; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true; maximumLineCount: 1 }
                        }
                    }
                }
            }
        }
    }

    PanelWindow {
        id: topBar
        anchors { top: true; left: true; right: true }
        implicitHeight: 44
        exclusiveZone: 44
        color: "transparent"

        Item {
            anchors.fill: parent
            opacity: 0
            NumberAnimation on opacity { from: 0; to: 1; duration: 400; easing.type: Easing.OutCubic; running: true }
            
            // --- CONTENEDOR IZQUIERDO (Logo Arch y Workspaces) ---
            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 12 // Alineación perfecta con gaps_out = 12 de Hyprland
                anchors.verticalCenter: parent.verticalCenter
                height: 34 // Misma altura que la isla (ajústalo si la tuya es distinta)
                width: leftRow.implicitWidth + 30 // 15px de margen interno a cada lado
                radius: height / 2 // Crea el efecto de cápsula completamente redondeada
                color: "#0a0a0a" // Fondo oscuro (puedes cambiarlo a "#000000" si la isla es más oscura)
                border.color: Qt.alpha(Theme.white, 0.08) // Un borde súper sutil para dar relieve
                border.width: 1

                RowLayout {
                    id: leftRow
                    anchors.centerIn: parent
                    spacing: 25
                    
                    Text { 
                        text: ""; color: Theme.white; font.family: Theme.fontIcons; font.pixelSize: 22; 
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { mainLauncher.toggle() } } 
                    }
                    Workspaces { showContainer: false } 
                }
            }

            // --- CONTENEDOR DERECHO (Iconos, bandeja, batería, notificaciones) ---
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 12 // Alineación perfecta con gaps_out = 12
                anchors.verticalCenter: parent.verticalCenter
                height: 34 
                // El ancho es dinámico: crecerá o encogerá mágicamente si aparecen apps o actualizaciones
                width: rightRow.implicitWidth + 30 
                radius: height / 2
                color: "#0a0a0a" 
                border.color: Qt.alpha(Theme.white, 0.08)
                border.width: 1

                RowLayout {
                    id: rightRow
                    anchors.centerIn: parent
                    spacing: 18
                    
                    // --- UPDATES MODULE (PACMAN) ---
                    Item {
                        id: updateModule
                        Layout.preferredWidth: updateLayout.implicitWidth
                        Layout.preferredHeight: 44
                        Layout.rightMargin: 15
                        visible: root.pendingUpdates > 0

                        RowLayout {
                            id: updateLayout
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
                                text: root.pendingUpdates.toString()
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

                    SystemIcons { 
                        id: sysIconsModule; rootRef: root; ssid: root.wifiSsid; wifiSignal: root.wifiSig; freq: root.wifiFreq
                        btOn: root.btStat === "on"; btDev: root.btDev; perf: root.perfMode; vol: root.vol; volMute: root.volMute; volDesc: root.volDesc
                    }

                    // --- CUSTOM APP TRAY (Spotify, Discord, OBS) ---
                    Item {
                        id: appTrayModule
                        visible: root.appSpotify || root.appDiscord || root.appObs
                        Layout.preferredWidth: appTrayLayout.implicitWidth
                        Layout.preferredHeight: 44
                        Layout.alignment: Qt.AlignVCenter
                        
                        RowLayout {
                            id: appTrayLayout
                            anchors.fill: parent
                            spacing: 12 // Un poco más ajustado para que quede cohesionado con SystemIcons

                            Text {
                                visible: root.appSpotify
                                text: ""
                                color: Theme.white
                                font.family: Theme.fontIcons
                                font.pixelSize: 15 // Reducido para igualar el peso visual
                                Layout.alignment: Qt.AlignVCenter
                                MouseArea { 
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor; 
                                    // pkill -9 fuerza el cierre inmediato sin minimizarse
                                    onClicked: { cmdProc.command = ["bash", "-c", "pkill -9 -x spotify"]; cmdProc.running = true; root.appSpotify = false; } 
                                }
                            }
                            
                            Text {
                                visible: root.appDiscord
                                text: ""
                                color: Theme.white
                                font.family: Theme.fontIcons
                                font.pixelSize: 14 // Discord suele verse más gordo por ser muy cuadrado, 14 lo equilibra
                                Layout.alignment: Qt.AlignVCenter
                                MouseArea { 
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor; 
                                    // -ix busca "discord" ignorando mayúsculas/minúsculas para no fallar nunca
                                    onClicked: { cmdProc.command = ["bash", "-c", "pkill -9 -ix discord || pkill -9 -x DiscordCore"]; cmdProc.running = true; root.appDiscord = false; } 
                                }
                            }
                            
                            Text {
                                visible: root.appObs
                                text: "󰑋"
                                color: Theme.white
                                font.family: Theme.fontIcons
                                font.pixelSize: 15 // Reducido para igualar el peso visual
                                Layout.alignment: Qt.AlignVCenter
                                MouseArea { 
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor; 
                                    onClicked: { cmdProc.command = ["bash", "-c", "pkill -9 -x obs"]; cmdProc.running = true; root.appObs = false; } 
                                }
                            }
                        }
                    }

                    Battery { percentage: root.batCap; charging: (root.batStat === "Charging" || root.batStat === "Full") }
                    MouseArea {
                        width: 26; height: 26; cursorShape: Qt.PointingHandCursor; onClicked: { root.isNotifOpen = !root.isNotifOpen }
                        Notification { dnd: root.dnd; count: root.notifCount; showContainer: false; anchors.fill: parent }
                    }
                }
            }
        }

        PanelWindow {
            id: popupMenuWindow
            anchors { top: true; right: true }
            WlrLayershell.layer: WlrLayershell.Overlay
            implicitHeight: root.isMenuVisible ? 90 : 0
            implicitWidth: 200
            margins { right: root.activeMenuOffset } 
            exclusiveZone: 0
            color: "transparent"
            SysMenu { title: root.activeMenuTitle; info1: root.activeMenuInfo1; info2: root.activeMenuInfo2; accent: root.activeMenuAccent; isOpen: root.isMenuOpen }
        }

        DynamicIsland { 
            id: islandWidget 
            // Filtro estricto que ignora palabras vacías o nulas devueltas por el sistema
            isBtConnected: {
                var dev = root.btDev ? root.btDev.toLowerCase().trim() : "";
                return root.btStat === "on" && dev !== "" && dev !== "disconnected" && dev !== "none" && dev !== "null" && dev !== "off";
            }
        }
    }

    PanelWindow {
        id: cavaWindow
        anchors { bottom: true; left: true; right: true }
        implicitHeight: 300  
        exclusiveZone: 0     
        color: "transparent"
        WlrLayershell.layer: WlrLayershell.Background 
        visible: root.showCavaVisualizer

        RowLayout {
            anchors.fill: parent
            spacing: 2 

            Repeater {
                model: cavaModel // Usamos el ListModel altamente reactivo
                
                Rectangle {
                    Layout.alignment: Qt.AlignBottom
                    Layout.fillWidth: true 
                    
                    // 'barHeight' es inyectada automáticamente por el ListModel.
                    // Usamos implicitHeight para que el RowLayout lo respete.
                    implicitHeight: Math.max(2, barHeight * 2.5) 
                    
                    radius: 4 

                    // --- NUEVO: Color dinámico ---
                    color: root.cavaColor 
                    opacity: 0.85
                    
                    Behavior on implicitHeight {
                        NumberAnimation { duration: 55; easing.type: Easing.OutCirc }
                    }
                    
                    // --- NUEVO: Animación suave al cambiar de color ---
                    Behavior on color {
                        ColorAnimation { duration: 800; easing.type: Easing.InOutQuad }
                    }
                }
            }
        }
    }
}