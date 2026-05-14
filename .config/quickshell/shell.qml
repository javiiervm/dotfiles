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
    //property bool showCavaVisualizer: isPlayingMedia && isWorkspaceEmpty
    property bool showCavaVisualizer: false // isPlayingMedia && isWorkspaceEmpty

    property string cavaColor: Theme.blue // Color inicial

    // Estados para el Control Center
    property bool isControlCenterOpen: false
    property string controlCenterTab: "wifi" // "wifi" o "bluetooth"

    // Datos avanzados para el Control Center
    property string advIp: "N/A"
    property string advSecurity: "N/A"
    property string advMac: "N/A"
    property string advBattery: "N/A"
    property string advFreq: "N/A"      // NUEVA
    property string advSignal: "N/A"    // NUEVA

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
    Process { id: airplaneProc; command: ["sh", "-c", "rfkill list all | grep -q 'Soft blocked: no' && rfkill block all || rfkill unblock all"] }
    Process { id: caffeineProc; command: ["sh", "-c", "pidof hypridle > /dev/null && killall hypridle || hypridle &"] }

    // --- MONITOR DE ESCRITORIO Y MEDIA (Basado en Eventos 0% CPU) ---
    Process {
        id: mediaWorkspaceMonitor
        command: [
            "bash", "-c",
            "F=/tmp/qs_media_fifo; rm -f $F; mkfifo $F; exec 3<> $F; " +
            "playerctl status --follow 2>/dev/null >&3 & " +
            "socat -U - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock | grep --line-buffered -E '(workspace|openwindow|closewindow|movewindow)' | while read -r _; do echo 'HYPR' >&3; done & " +
            "trap 'kill $(jobs -p) 2>/dev/null; rm -f $F' EXIT; " +
            "check_state() { w=$(hyprctl activeworkspace -j 2>/dev/null | jq '.windows' || echo 0); p=$(playerctl status 2>/dev/null | grep -q 'Playing' && echo 1 || echo 0); echo \"$w;$p\"; }; " +
            "check_state; " + 
            "while read -r event <&3; do check_state; done"
        ]
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

    // --- MONITOR DE MODO AVIÓN (Basado en Eventos 0% CPU) ---
    Process {
        id: airplaneMonitor
        command: [
            "bash", "-c",
            // Función que lee el estado real: Si hay algún bloqueo "Soft" o "Hard", el modo avión está activo.
            "check_airplane() { rfkill list all | grep -q 'Soft blocked: no' && echo 0 || echo 1; }; " +
            "check_airplane; " + // Estado inicial
            // Magia event-driven: 'rfkill event' frena el script hasta que tocas algo de red.
            "rfkill event | while read -r _; do check_airplane; done"
        ]
        running: true
        stdout: SplitParser {
            onRead: (data) => {
                root.airplaneMode = (data.trim() === "1");
            }
        }
    }

    Connections {
        target: root
        function onIsControlCenterOpenChanged() {
            if (root.isControlCenterOpen) {
                advInfoProc.running = true;
            }
        }
    }

    Process {
        id: advInfoProc
        command: [
            "bash", "-c", 
            "IP=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \\K\\S+' | head -n 1); " +
            "WIFI=$(nmcli -t -f active,security,freq,signal dev wifi 2>/dev/null | grep -E '^(sí|yes):' | head -n 1); " +
            "SEC=$(echo \"$WIFI\" | cut -d: -f2); " +
            "FREQ=$(echo \"$WIFI\" | cut -d: -f3 | tr -d ' '); " +
            "SIG=$(echo \"$WIFI\" | cut -d: -f4); " +
            "MAC=$(bluetoothctl show 2>/dev/null | grep 'Controller' | awk '{print $2}' | head -n 1); " +
            "BAT=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n 1); " +
            "echo \"${IP:-N/A}|${SEC:-N/A}|${FREQ:-N/A}|${SIG:-N/A}|${MAC:-N/A}|${BAT:-N/A}\""
        ]
        stdout: SplitParser {
            onRead: (data) => {
                var parts = data.trim().split('|');
                if(parts.length >= 6) {
                    root.advIp = parts[0];
                    root.advSecurity = parts[1];
                    root.advFreq = parts[2];
                    root.advSignal = parts[3];
                    root.advMac = parts[4];
                    root.advBattery = parts[5];
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
        WlrLayershell.layer: WlrLayershell.Top
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
                anchors.leftMargin: 12 
                anchors.verticalCenter: parent.verticalCenter
                height: 34 
                width: leftRow.implicitWidth + 30 
                radius: height / 2 
                color: "#0a0a0a" 
                border.color: Qt.alpha(Theme.white, 0.08) 
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
                anchors.rightMargin: 12 
                anchors.verticalCenter: parent.verticalCenter
                height: 34 
                width: rightRow.implicitWidth + 30 
                radius: height / 2
                color: "#0a0a0a" 
                border.color: Qt.alpha(Theme.white, 0.08)
                border.width: 1

                RowLayout {
                    id: rightRow
                    anchors.centerIn: parent
                    spacing: 18
                    
                    // --- UPDATES MODULE ENCAPSULADO ---
                    Updates { Layout.rightMargin: 15 }

                    SystemIcons { 
                        id: sysIconsModule; rootRef: root; ssid: root.wifiSsid; wifiSignal: root.wifiSig; freq: root.wifiFreq
                        btOn: root.btStat === "on"; btDev: root.btDev; perf: root.perfMode; vol: root.vol; volMute: root.volMute; volDesc: root.volDesc
                    }

                    // --- CUSTOM APP TRAY ENCAPSULADO ---
                    AppTray { Layout.alignment: Qt.AlignVCenter }

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

        // === ISLA DINÁMICA (TEMPORALMENTE COMENTADA) ===
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
                model: cavaModel 
                
                Rectangle {
                    Layout.alignment: Qt.AlignBottom
                    Layout.fillWidth: true 
                    
                    implicitHeight: Math.max(2, barHeight * 2.5) 
                    
                    radius: 4 
                    color: root.cavaColor 
                    opacity: 0.85
                    
                    Behavior on implicitHeight {
                        NumberAnimation { duration: 55; easing.type: Easing.OutCirc }
                    }
                    Behavior on color {
                        ColorAnimation { duration: 800; easing.type: Easing.InOutQuad }
                    }
                }
            }
        }
    }

    // Instancia del nuevo menú de wallpapers
    WallpaperCarousel {
        id: wallCarouselWidget
    }

    // Atajo global para abrirlo directamente (ej. Meta + W)
    GlobalShortcut {
        name: "wallpaper_menu"
        onPressed: { wallCarouselWidget.toggle() }
    }

    PanelWindow {
        id: controlCenterWindow
        screen: Quickshell.screens[0]

        // Fullscreen como el NotificationCenter — el dismiss y la tarjeta van dentro
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayershell.Overlay
        WlrLayershell.keyboardFocus: root.isControlCenterOpen ? WlrLayershell.OnDemand : WlrLayershell.None
        visible: root.isControlCenterOpen

        // 1. Dismiss de fondo (fullscreen, primer hijo = z inferior)
        MouseArea {
            anchors.fill: parent
            onClicked: root.isControlCenterOpen = false
        }

        // 2. Contenido (segundo hijo = z superior), posicionado arriba-derecha
        Item {
            id: cardContainer
            width: 460
            height: 340
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 1
            anchors.rightMargin: 12

            Rectangle {
                id: mainCard
                anchors.fill: parent
                radius: 12
                color: Qt.alpha("#0a0f18", 0.95)
                border.color: Qt.alpha(Theme.white, 0.1)
                border.width: 1
                focus: true

                Keys.onEscapePressed: root.isControlCenterOpen = false

                MouseArea {
                    anchors.fill: parent
                    // Sin onClicked = bloqueador silencioso (igual que NotificationCenter línea 132)
                    Timer { id: swipeCooldown; interval: 400 }
                    onWheel: (wheel) => {
                        if (swipeCooldown.running) return
                        if (wheel.angleDelta.x < -40) {
                            root.controlCenterTab = "bluetooth"
                            swipeCooldown.restart()
                        } else if (wheel.angleDelta.x > 40) {
                            root.controlCenterTab = "wifi"
                            swipeCooldown.restart()
                        }
                    }
                }

                Canvas {
                    id: connectionLines
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        ctx.strokeStyle = Qt.alpha(Theme.white, 0.2);
                        ctx.lineWidth = 2;
                        ctx.beginPath();
                        var centerX = width / 2;
                        var centerY = height / 2 - 20;
                        function drawNodeLine(targetX, targetY) {
                            ctx.moveTo(centerX, centerY);
                            ctx.bezierCurveTo(centerX + (targetX - centerX)/2, centerY,
                                              centerX + (targetX - centerX)/2, targetY,
                                              targetX, targetY);
                        }
                        if (root.controlCenterTab === "wifi") {
                            drawNodeLine(cardIp.x + cardIp.width, cardIp.y + cardIp.height/2);
                            drawNodeLine(cardSecurity.x + cardSecurity.width, cardSecurity.y + cardSecurity.height/2);
                            drawNodeLine(cardBand.x, cardBand.y + cardBand.height/2);
                            drawNodeLine(cardSignal.x, cardSignal.y + cardSignal.height/2);
                        } else {
                            drawNodeLine(cardMac.x + cardMac.width, cardMac.y + cardMac.height/2);
                            drawNodeLine(cardAudio.x + cardAudio.width, cardAudio.y + cardAudio.height/2);
                            drawNodeLine(cardBattery.x, cardBattery.y + cardBattery.height/2);
                        }
                        ctx.stroke();
                    }
                    Connections { target: root; function onControlCenterTabChanged() { connectionLines.requestPaint() } }
                }

                Rectangle {
                    id: centerNode
                    width: 120; height: 120; radius: 60
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -20
                    color: root.controlCenterTab === "wifi" ? "#5bc0eb" : "#cbaacb"
                    border.color: Qt.alpha(Theme.white, 0.1); border.width: 2
                    ColumnLayout {
                        anchors.centerIn: parent; spacing: 4
                        Text { text: root.controlCenterTab === "wifi" ? "" : ""; font.family: Theme.fontIcons; font.pixelSize: 32; color: "#1a1a1a"; Layout.alignment: Qt.AlignHCenter }
                        Text { text: root.controlCenterTab === "wifi" ? (root.wifiSsid || "Desconectado") : (root.btDev || "Sin Dispositivo"); color: "#1a1a1a"; font.bold: true; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter; Layout.maximumWidth: 100; elide: Text.ElideRight }
                        Text { text: "Connected"; color: Qt.alpha("#1a1a1a", 0.7); font.pixelSize: 9; Layout.alignment: Qt.AlignHCenter; visible: (root.wifiSsid !== "" && root.controlCenterTab === "wifi") || (root.btStat === "on" && root.controlCenterTab === "bluetooth") }
                    }
                }

                Component {
                    id: infoCard
                    Rectangle {
                        width: 120; height: 45; radius: 10
                        color: Qt.alpha("#1e222a", 0.8)
                        border.color: Qt.alpha(Theme.white, 0.1)
                        property string iconText: ""; property string mainText: ""; property string subText: ""
                        RowLayout {
                            anchors.fill: parent; anchors.margins: 8; spacing: 8
                            Text { text: iconText; font.family: Theme.fontIcons; color: root.controlCenterTab === "wifi" ? "#5bc0eb" : "#cbaacb"; font.pixelSize: 14 }
                            ColumnLayout {
                                spacing: 0
                                Text { text: mainText; color: Theme.white; font.bold: true; font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideRight }
                                Text { text: subText; color: Theme.grey1; font.pixelSize: 8 }
                            }
                        }
                    }
                }

                Loader { id: cardIp;       sourceComponent: infoCard; x: 20;  y: 60;  visible: root.controlCenterTab === "wifi"
                         onLoaded: { item.iconText = "󰩟"; item.mainText = Qt.binding(() => root.advIp);      item.subText = "IP Address" } }
                Loader { id: cardSecurity; sourceComponent: infoCard; x: 20;  y: 200; visible: root.controlCenterTab === "wifi"
                         onLoaded: { item.iconText = "󰒃"; item.mainText = Qt.binding(() => root.advSecurity); item.subText = "Security" } }
                Loader { id: cardBand;     sourceComponent: infoCard; x: 320; y: 60;  visible: root.controlCenterTab === "wifi"
                         onLoaded: { item.iconText = "󰖩"; item.mainText = Qt.binding(() => root.advFreq);     item.subText = "Band" } }
                Loader { id: cardSignal;   sourceComponent: infoCard; x: 320; y: 200; visible: root.controlCenterTab === "wifi"
                         onLoaded: { item.iconText = "󰤨"; item.mainText = Qt.binding(() => root.advSignal !== "N/A" ? root.advSignal + "%" : "N/A"); item.subText = "Signal" } }

                Loader { id: cardMac;     sourceComponent: infoCard; x: 20;  y: 60;  visible: root.controlCenterTab === "bluetooth"
                         onLoaded: { item.iconText = "󰒋"; item.mainText = Qt.binding(() => root.advMac);                                              item.subText = "MAC Address" } }
                Loader { id: cardAudio;   sourceComponent: infoCard; x: 20;  y: 200; visible: root.controlCenterTab === "bluetooth"
                         onLoaded: { item.iconText = "󰋋"; item.mainText = Qt.binding(() => root.volDesc || "None");                                   item.subText = "Audio Profile" } }
                Loader { id: cardBattery; sourceComponent: infoCard; x: 320; y: 130; visible: root.controlCenterTab === "bluetooth"
                         onLoaded: { item.iconText = "󰥉"; item.mainText = Qt.binding(() => root.advBattery !== "N/A" ? root.advBattery + "%" : "N/A"); item.subText = "Battery" } }

                Rectangle {
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 15
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 240; height: 35; radius: 17
                    color: Qt.alpha("#1e222a", 0.6)
                    border.color: Qt.alpha(Theme.white, 0.1)
                    RowLayout {
                        anchors.fill: parent; spacing: 0
                        Rectangle {
                            Layout.fillWidth: true; Layout.fillHeight: true; radius: 17
                            color: root.controlCenterTab === "wifi" ? Qt.alpha(Theme.white, 0.15) : "transparent"
                            RowLayout { anchors.centerIn: parent; spacing: 6
                                Text { text: ""; font.family: Theme.fontIcons; color: root.controlCenterTab === "wifi" ? "#5bc0eb" : Theme.grey1; font.pixelSize: 12 }
                                Text { text: "Wi-Fi"; color: root.controlCenterTab === "wifi" ? Theme.white : Theme.grey1; font.bold: true; font.pixelSize: 11 }
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.controlCenterTab = "wifi" }
                        }
                        Rectangle {
                            Layout.fillWidth: true; Layout.fillHeight: true; radius: 17
                            color: root.controlCenterTab === "bluetooth" ? Qt.alpha(Theme.white, 0.15) : "transparent"
                            RowLayout { anchors.centerIn: parent; spacing: 6
                                Text { text: ""; font.family: Theme.fontIcons; color: root.controlCenterTab === "bluetooth" ? "#cbaacb" : Theme.grey1; font.pixelSize: 12 }
                                Text { text: "Bluetooth"; color: root.controlCenterTab === "bluetooth" ? Theme.white : Theme.grey1; font.bold: true; font.pixelSize: 11 }
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.controlCenterTab = "bluetooth" }
                        }
                    }
                }
            }
        }
    }
}