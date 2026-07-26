import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Qt5Compat.GraphicalEffects
import "."
import "components"

ShellRoot {
    id: root

    readonly property var theme: Theme

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
    property bool showCavaVisualizer: false 

    property string cavaColor: Theme.blue 

    // Estados para el Control Center
    property bool isControlCenterOpen: false
    property string controlCenterTab: "wifi"

    // Datos avanzados para el Control Center
    property string advIp: "N/A"
    property string advSecurity: "N/A"
    property string advMac: "N/A"
    property string advBattery: "N/A"
    property string advFreq: "N/A"      
    property string advSignal: "N/A"    

    // --- ESTADOS DEL DOCK DINÁMICO ---
    property int bottomGap: 12
    property bool isDockHovered: false
    property bool isMacosMode: false

    // --- ESTADOS DE ALT+TAB NATIVO ---
    property bool isAltTabVisible: false
    property var altTabList: []
    property int altTabCurrentIndex: 0

    property alias sharedNotifModel: sharedNotifModel
    ListModel { id: sharedNotifModel }
    ListModel { id: popupModel }
    ListModel {
        id: cavaModel
        Component.onCompleted: {
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
    
    // Procesos separados
    Process { id: cmdProc }
    Process { id: wifiProc; command: ["sh", "-c", "nmcli radio wifi | grep -q 'enabled' && nmcli radio wifi off || nmcli radio wifi on"] }
    Process { id: btProc; command: ["sh", "-c", "rfkill toggle bluetooth"] }
    Process { id: airplaneProc; command: ["sh", "-c", "rfkill list all | grep -q 'Soft blocked: no' && rfkill block all || rfkill unblock all"] }
    Process { id: caffeineProc; command: ["sh", "-c", "pidof hypridle > /dev/null && killall hypridle || hypridle &"] }

    // --- LECTOR DINÁMICO DE MÁRGENES DE HYPRLAND ---
    Process {
        id: hyprGapReader
        command: ["bash", "-c", "hyprctl -j getoption general:gaps_out | grep -oP '(?<=\"customType\":\\[)\\d+,\\d+,\\d+' | cut -d',' -f3 || echo 12"]
        running: true
        stdout: SplitParser {
            onRead: (data) => {
                var gap = parseInt(data.trim());
                if (!isNaN(gap) && gap >= 0) root.bottomGap = gap;
            }
        }
    }

    // --- MONITOR DEL MODO MACOS ---
    Process {
        id: macosModeMonitor
        command: [
            "bash", "-c",
            "check() { [ -f /tmp/hypr_macos_mode ] && echo 1 || echo 0; }; " +
            "check; " +
            "if command -v inotifywait >/dev/null 2>&1; then " +
            "  inotifywait -m -q -e create,delete,moved_to,moved_from --format '%f' /tmp | while read -r f; do " +
            "    [ \"$f\" = \"hypr_macos_mode\" ] && check; " +
            "  done; " +
            "else " +
            "  while true; do sleep 1; check; done; " +
            "fi"
        ]
        running: true
        stdout: SplitParser {
            onRead: (data) => {
                var val = data.trim();
                if (val === "1" || val === "0") root.isMacosMode = (val === "1");
            }
        }
    }

    // --- 1. MONITOR DE ESCRITORIO ---
    Process {
        id: workspaceMonitorProc
        command: [
            "bash", "-c",
            "check_empty() { w=$(hyprctl activeworkspace -j 2>/tmp/qs_dock_err.log | jq -e '.windows' 2>>/tmp/qs_dock_err.log); rc=$?; if [ $rc -ne 0 ] || [ -z \"$w\" ]; then echo \"ERR rc=$rc w=$w\" >> /tmp/qs_dock_err.log; return; fi; [ \"$w\" = \"0\" ] && echo 1 || echo 0; }; " +
            "check_empty; " +
            "SOCAT_BIN=$(command -v socat 2>/dev/null); " +
            "if [ -z \"$SOCAT_BIN\" ]; then " +
            "  for p in /usr/bin/socat /usr/local/bin/socat /bin/socat; do [ -x \"$p\" ] && SOCAT_BIN=\"$p\" && break; done; " +
            "fi; " +
            "if [ -z \"$SOCAT_BIN\" ]; then " +
            "  echo \"socat no encontrado en ninguna ruta conocida, usando sondeo (polling) cada 2s\" >> /tmp/qs_dock_err.log; " +
            "  while true; do check_empty; sleep 2; done; " +
            "else " +
            "  echo \"usando socat: $SOCAT_BIN\" >> /tmp/qs_dock_err.log; " +
            "  while true; do " +
            "    \"$SOCAT_BIN\" -U - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock 2>>/tmp/qs_dock_err.log | grep --line-buffered -E '(workspace|openwindow|closewindow|movewindow)' | while read -r _; do check_empty; done; " +
            "    echo \"socat desconectado, reintentando en 1s\" >> /tmp/qs_dock_err.log; " +
            "    sleep 1; " +
            "  done; " +
            "fi"
        ]
        running: true
        stdout: SplitParser {
            onRead: (data) => {
                var val = data.trim();
                if (val === "1" || val === "0") {
                    root.isWorkspaceEmpty = (val === "1");
                }
            }
        }
    }

    // --- 2. MONITOR DE MEDIOS ---
    Process {
        id: mediaMonitorProc
        command: [
            "bash", "-c",
            "playerctl status --follow 2>/dev/null | while read -r status; do " +
            "  if [ \"$status\" = \"Playing\" ]; then echo 1; else echo 0; fi; " +
            "done"
        ]
        running: true
        stdout: SplitParser {
            onRead: (data) => {
                var val = data.trim();
                if (val === "1" || val === "0") {
                    root.isPlayingMedia = (val === "1");
                }
            }
        }
    }

    // Motor de Visualización (Cava)
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

    onIsNotifOpenChanged: {
        if (!isNotifOpen) {
            hasUnread = false
        }
    }

    Process {
        id: colorMonitorProc
        command: [
            "bash", "-c", 
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
        command: ["/home/javier/.config/quickshell/scripts/backend_daemon.sh"]
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
                        popupModel.insert(0, { "nId": n.id, "pApp": n.app, "pTitle": n.title, "pBody": n.body, "pIcon": n.icon, "pUrgency": n.urgency })
                    }
                }
            }
        }
    }

    // Carga ultrarrápida de la lista de ventanas
    Process {
        id: altTabFetchProc
        command: ["/home/javier/.config/quickshell/scripts/alttab_fetch.sh"]
        stdout: SplitParser {
            onRead: (data) => {
                try {
                    var list = JSON.parse(data.trim());
                    if (list && list.length > 0) {
                        root.altTabList = list;
                        root.altTabCurrentIndex = list.length > 1 ? 1 : 0;
                        root.isAltTabVisible = true;
                    }
                } catch (e) {}
            }
        }
    }

    Process { id: altTabFocusProc }

    // Métodos invocables desde Hyprland via IPC (qsctl dispatch)
    function alttab_next() {
        if (!root.isAltTabVisible) {
            altTabFetchProc.running = true;
        } else {
            if (root.altTabList.length > 0) {
                root.altTabCurrentIndex = (root.altTabCurrentIndex + 1) % root.altTabList.length;
            }
        }
    }

    function alttab_commit() {
        if (root.isAltTabVisible) {
            if (root.altTabList.length > 0 && root.altTabCurrentIndex < root.altTabList.length) {
                var target = root.altTabList[root.altTabCurrentIndex];
                var addr = "address:" + target.address;
                if (target.minimized) {
                    altTabFocusProc.command = ["bash", "-c",
                        "~/.config/hypr/scripts/macos_restore_minimized.sh '" + target.address + "'"];
                } else {
                    altTabFocusProc.command = ["bash", "-c",
                        "hyprctl dispatch focuswindow '" + addr + "' && hyprctl dispatch alterzorder 'top," + addr + "'"];
                }
                altTabFocusProc.running = true;
            }
            root.isAltTabVisible = false;
        }
    }

    // Expone alttab_next / alttab_commit por IPC para que Hyprland pueda invocarlos
    // con: qs ipc -p ~/.config/quickshell call alttab next|commit
    IpcHandler {
        target: "alttab"

        function next(): void {
            root.alttab_next();
        }

        function commit(): void {
            root.alttab_commit();
        }
    }

    // --- MONITOR DE MODO AVIÓN ---
    Process {
        id: airplaneMonitor
        command: [
            "bash", "-c",
            "check_airplane() { rfkill list all | grep -q 'Soft blocked: no' && echo 0 || echo 1; }; " +
            "check_airplane; " + 
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
                    
                    color: pUrgency === 2 ? Qt.alpha(Theme.red, 0.15) : Theme.bgGlass
                    border.color: pUrgency === 2 ? Theme.red : Qt.alpha(Theme.white, 0.15)
                    border.width: pUrgency === 2 ? 2 : 1
                    
                    transform: Translate { id: slideTrans; x: 400 }
                    Component.onCompleted: { slideIn.start(); hideTimer.start(); }
                    NumberAnimation { id: slideIn; target: slideTrans; property: "x"; to: 0; duration: 400; easing.type: Easing.OutBack }
                    NumberAnimation { id: slideOut; target: slideTrans; property: "x"; to: 400; duration: 300; easing.type: Easing.InBack; onFinished: root.removePopup(nId) }
                    Timer { id: hideTimer; interval: 5000; onTriggered: slideOut.start() }
                    
                    MouseArea { anchors.fill: parent; onClicked: slideOut.start() }
                    
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 12; spacing: 12
                        Item {
                            Layout.preferredWidth: 35
                            Layout.preferredHeight: 35

                            Image {
                                id: notifImgPopup
                                anchors.fill: parent
                                source: pIcon.startsWith("/") ? "file://" + pIcon : "image://icon/" + pIcon
                                fillMode: Image.PreserveAspectCrop
                                visible: false
                            }

                            Rectangle {
                                id: maskPopup
                                anchors.fill: parent
                                radius: width / 2
                                visible: false
                            }

                            OpacityMask {
                                anchors.fill: parent
                                source: notifImgPopup
                                maskSource: maskPopup
                                layer.enabled: pUrgency === 2 
                            }
                        }
                        
                        ColumnLayout {
                            spacing: 2
                            Text { 
                                text: pApp + (pUrgency === 2 ? " • CRITICAL" : "") 
                                color: pUrgency === 2 ? Theme.red : Theme.blue 
                                font.pixelSize: 10; font.bold: true 
                            }
                            Text { text: pTitle; color: Theme.white; font.pixelSize: 12; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                            Text { text: pBody; color: Theme.grey1; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true; maximumLineCount: 1 }
                        }

                        Item {
                            Layout.alignment: Qt.AlignTop | Qt.AlignRight
                            width: 20
                            height: 20
                            Text { 
                                anchors.centerIn: parent
                                text: "󰅖"
                                font.family: Theme.fontIcons
                                color: xMousePopup.containsMouse ? Theme.white : Theme.grey1
                                font.pixelSize: 14 
                            }
                            MouseArea { 
                                id: xMousePopup
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { 
                                    slideOut.start() 
                                    cmdProc.command = ["sh", "-c", "echo 'REMOVE|" + nId + "' > /tmp/qs_notif_cmd"]
                                    cmdProc.running = true
                                }
                            }
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
            
            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 12 
                anchors.verticalCenter: parent.verticalCenter
                height: 34 
                width: leftRow.implicitWidth + 30 
                radius: height / 2 
                color: Theme.bgGlass 
                border.color: Qt.alpha(Theme.white, 0.15) 
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

            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 12 
                anchors.verticalCenter: parent.verticalCenter
                height: 34 
                width: rightRow.implicitWidth + 30 
                radius: height / 2
                color: Theme.bgGlass 
                border.color: Qt.alpha(Theme.white, 0.15)
                border.width: 1

                RowLayout {
                    id: rightRow
                    anchors.centerIn: parent
                    spacing: 18
                    
                    Updates { Layout.rightMargin: 15 }

                    SystemIcons { 
                        id: sysIconsModule; rootRef: root; ssid: root.wifiSsid; wifiSignal: root.wifiSig; freq: root.wifiFreq
                        btOn: root.btStat === "on"; btDev: root.btDev; perf: root.perfMode; vol: root.vol; volMute: root.volMute; volDesc: root.volDesc
                    }

                    AppTray { Layout.alignment: Qt.AlignVCenter }

                    Battery { percentage: root.batCap; charging: (root.batStat === "Charging" || root.batStat === "Full") }
                    MouseArea {
                        width: 26; height: 26; cursorShape: Qt.PointingHandCursor; onClicked: { root.isNotifOpen = !root.isNotifOpen }
                        Notification { 
                            dnd: root.dnd; 
                            count: root.notifCount; 
                            hasUnread: root.hasUnread; 
                            showContainer: false; 
                            anchors.fill: parent 
                        }
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

    WallpaperCarousel {
        id: wallCarouselWidget
    }

    GlobalShortcut {
        name: "wallpaper_menu"
        onPressed: { wallCarouselWidget.toggle() }
    }

    PanelWindow {
        id: controlCenterWindow
        screen: Quickshell.screens[0]

        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayershell.Overlay
        WlrLayershell.keyboardFocus: root.isControlCenterOpen ? WlrLayershell.OnDemand : WlrLayershell.None
        visible: root.isControlCenterOpen

        MouseArea {
            anchors.fill: parent
            onClicked: root.isControlCenterOpen = false
        }

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
                color: Theme.bgGlass
                border.color: Qt.alpha(Theme.white, 0.15)
                border.width: 1
                focus: true

                Keys.onEscapePressed: root.isControlCenterOpen = false

                MouseArea {
                    anchors.fill: parent
                    Timer { id: swipeCooldown; interval: 400 }
                    onWheel: (wheel) => {
                        if (swipeCooldown.running) return
                        var tabs = ["wifi", "bluetooth", "audio", "performance"];
                        var idx = tabs.indexOf(root.controlCenterTab);
                        if (wheel.angleDelta.x < -40 || wheel.angleDelta.y < -40) {
                            root.controlCenterTab = tabs[(idx + 1) % tabs.length];
                            swipeCooldown.restart()
                        } else if (wheel.angleDelta.x > 40 || wheel.angleDelta.y > 40) {
                            root.controlCenterTab = tabs[(idx - 1 + tabs.length) % tabs.length];
                            swipeCooldown.restart()
                        }
                    }
                }

                Component {
                    id: infoCard
                    Rectangle {
                        width: 120; height: 45; radius: 10
                        color: Qt.alpha("#1e222a", 0.8)
                        border.color: Qt.alpha(Theme.white, 0.1)
                        property string iconText: ""
                        property string mainText: "" 
                        property string subText: ""
                        property color accentColor: Theme.white
                        
                        RowLayout {
                            anchors.fill: parent; anchors.margins: 8; spacing: 8
                            Text { text: iconText; font.family: Theme.fontIcons; color: accentColor; font.pixelSize: 14 }
                            ColumnLayout {
                                spacing: 0
                                Text { text: mainText; color: Theme.white; font.bold: true; font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideRight }
                                Text { text: subText; color: Theme.grey1; font.pixelSize: 8 }
                            }
                        }
                    }
                }

                Component {
                    id: tabCore
                    Item {
                        anchors.fill: parent
                        property string tabName: "wifi"

                        Canvas {
                            anchors.fill: parent
                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.clearRect(0, 0, width, height);
                                ctx.strokeStyle = Qt.alpha(Theme.white, 0.2);
                                ctx.lineWidth = 2;
                                ctx.beginPath();
                                var cx = width / 2;
                                var cy = height / 2 - 20;
                                function drawNodeLine(tx, ty) {
                                    ctx.moveTo(cx, cy);
                                    ctx.bezierCurveTo(cx + (tx - cx)/2, cy, cx + (tx - cx)/2, ty, tx, ty);
                                }
                                if (tabName === "bluetooth") {
                                    drawNodeLine(140, 82.5); drawNodeLine(140, 222.5); drawNodeLine(320, 152.5);
                                } else if (tabName === "audio") {
                                    drawNodeLine(140, 82.5); drawNodeLine(140, 222.5);
                                } else {
                                    drawNodeLine(140, 82.5); drawNodeLine(140, 222.5); drawNodeLine(320, 82.5); drawNodeLine(320, 222.5);
                                }
                                ctx.stroke();
                            }
                        }

                        Rectangle {
                            width: 120; height: 120; radius: 60
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: -20
                            color: tabName === "wifi" ? "#5bc0eb" : tabName === "bluetooth" ? "#cbaacb" : tabName === "audio" ? "#e74c3c" : (root.perfMode === "power-saver" ? "#2ecc71" : root.perfMode === "performance" ? "#f39c12" : Theme.white)
                            border.color: Qt.alpha(Theme.white, 0.1); border.width: 2
                            ColumnLayout {
                                anchors.centerIn: parent; spacing: 4
                                Text { 
                                    text: tabName === "wifi" ? "" : tabName === "bluetooth" ? "" : tabName === "audio" ? (root.volMute || root.vol === 0 ? "󰝟" : "󰕾") : "󰓅"
                                    font.family: Theme.fontIcons; font.pixelSize: 32; color: "#1a1a1a"; Layout.alignment: Qt.AlignHCenter 
                                }
                                Text { 
                                    text: tabName === "wifi" ? (root.wifiSsid || "Desconectado") : tabName === "bluetooth" ? (root.btDev || "Sin Dispositivo") : tabName === "audio" ? root.vol + "%" : root.perfMode.charAt(0).toUpperCase() + root.perfMode.slice(1)
                                    color: "#1a1a1a"; font.bold: true; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter; Layout.maximumWidth: 100; elide: Text.ElideRight 
                                }
                                Text { 
                                    text: tabName === "audio" ? (root.volMute ? "Muted" : "Active") : tabName === "performance" ? "System Controlled" : "Connected"
                                    color: Qt.alpha("#1a1a1a", 0.7); font.pixelSize: 9; Layout.alignment: Qt.AlignHCenter; 
                                    visible: (root.wifiSsid !== "" && tabName === "wifi") || (root.btStat === "on" && tabName === "bluetooth") || (tabName === "audio") || (tabName === "performance")
                                }
                            }
                        }
                    }
                }

                Item {
                    id: slideWindow
                    anchors.top: parent.top
                    anchors.bottom: bottomNav.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    clip: true

                    property var tabsList: ["wifi", "bluetooth", "audio", "performance"]
                    property int currentIndex: tabsList.indexOf(root.controlCenterTab)

                    Item {
                        id: slideContainer
                        width: slideWindow.width * 4
                        height: slideWindow.height
                        x: -slideWindow.currentIndex * slideWindow.width

                        Behavior on x {
                            NumberAnimation { duration: 400; easing.type: Easing.OutQuart }
                        }

                        Item {
                            width: slideWindow.width; height: parent.height; x: 0
                            Loader { anchors.fill: parent; sourceComponent: tabCore; onLoaded: item.tabName = "wifi" }
                            Loader { sourceComponent: infoCard; x: 20; y: 60;  onLoaded: { item.accentColor = "#5bc0eb"; item.iconText = "󰩟"; item.mainText = Qt.binding(() => root.advIp); item.subText = "IP Address" } }
                            Loader { sourceComponent: infoCard; x: 20; y: 200; onLoaded: { item.accentColor = "#5bc0eb"; item.iconText = "󰒃"; item.mainText = Qt.binding(() => root.advSecurity); item.subText = "Security" } }
                            Loader { sourceComponent: infoCard; x: 320; y: 60; onLoaded: { item.accentColor = "#5bc0eb"; item.iconText = "󰖩"; item.mainText = Qt.binding(() => root.advFreq); item.subText = "Band" } }
                            Loader { sourceComponent: infoCard; x: 320; y: 200; onLoaded: { item.accentColor = "#5bc0eb"; item.iconText = "󰤨"; item.mainText = Qt.binding(() => root.advSignal !== "N/A" ? root.advSignal + "%" : "N/A"); item.subText = "Signal" } }
                        }

                        Item {
                            width: slideWindow.width; height: parent.height; x: slideWindow.width
                            Loader { anchors.fill: parent; sourceComponent: tabCore; onLoaded: item.tabName = "bluetooth" }
                            Loader { sourceComponent: infoCard; x: 20; y: 60;  onLoaded: { item.accentColor = "#cbaacb"; item.iconText = "󰒋"; item.mainText = Qt.binding(() => root.advMac); item.subText = "MAC Address" } }
                            Loader { sourceComponent: infoCard; x: 20; y: 200; onLoaded: { item.accentColor = "#cbaacb"; item.iconText = "󰋋"; item.mainText = Qt.binding(() => root.volDesc || "None"); item.subText = "Audio Profile" } }
                            Loader { sourceComponent: infoCard; x: 320; y: 130; onLoaded: { item.accentColor = "#cbaacb"; item.iconText = "󰥉"; item.mainText = Qt.binding(() => root.advBattery !== "N/A" ? root.advBattery + "%" : "N/A"); item.subText = "Battery" } }
                        }

                        Item {
                            width: slideWindow.width; height: parent.height; x: slideWindow.width * 2
                            Loader { anchors.fill: parent; sourceComponent: tabCore; onLoaded: item.tabName = "audio" }
                            Loader { sourceComponent: infoCard; x: 20; y: 60;  onLoaded: { item.accentColor = "#e74c3c"; item.iconText = "󰋋"; item.mainText = Qt.binding(() => root.volDesc || "Built-in Audio"); item.subText = "Output Device" } }
                            Loader { sourceComponent: infoCard; x: 20; y: 200; onLoaded: { item.accentColor = "#e74c3c"; item.iconText = Qt.binding(() => root.volMute ? "󰝟" : "󰕾"); item.mainText = Qt.binding(() => root.volMute ? "Muted" : "Unmuted"); item.subText = "Audio State" } }
                        }

                        Item {
                            width: slideWindow.width; height: parent.height; x: slideWindow.width * 3
                            Loader { anchors.fill: parent; sourceComponent: tabCore; onLoaded: item.tabName = "performance" }
                            Loader { sourceComponent: infoCard; x: 20; y: 60;  onLoaded: { item.accentColor = Qt.binding(() => root.perfMode === "power-saver" ? "#2ecc71" : root.perfMode === "performance" ? "#f39c12" : Theme.white); item.iconText = "󰻠"; item.mainText = Qt.binding(() => root.cpuUsage + "%"); item.subText = "CPU Usage" } }
                            Loader { sourceComponent: infoCard; x: 20; y: 200; onLoaded: { item.accentColor = Qt.binding(() => root.perfMode === "power-saver" ? "#2ecc71" : root.perfMode === "performance" ? "#f39c12" : Theme.white); item.iconText = "󰍛"; item.mainText = Qt.binding(() => root.memUsage + "%"); item.subText = "Memory" } }
                            Loader { sourceComponent: infoCard; x: 320; y: 60; onLoaded: { item.accentColor = Qt.binding(() => root.perfMode === "power-saver" ? "#2ecc71" : root.perfMode === "performance" ? "#f39c12" : Theme.white); item.iconText = "󰁹"; item.mainText = Qt.binding(() => root.batCap + "%"); item.subText = "Battery Level" } }
                            Loader { sourceComponent: infoCard; x: 320; y: 200; onLoaded: { item.accentColor = Qt.binding(() => root.perfMode === "power-saver" ? "#2ecc71" : root.perfMode === "performance" ? "#f39c12" : Theme.white); item.iconText = "󰚥"; item.mainText = Qt.binding(() => root.batStat || "Unknown"); item.subText = "Power State" } }
                        }
                    }
                }

                Rectangle {
                    id: bottomNav
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 15
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 360; height: 35; radius: 17
                    color: Qt.alpha("#1e222a", 0.6)
                    border.color: Qt.alpha(Theme.white, 0.1)

                    readonly property var tabs: ["wifi", "bluetooth", "audio", "performance"]
                    readonly property int currentIndex: tabs.indexOf(root.controlCenterTab)
                    readonly property real stepWidth: width / 4

                    Rectangle {
                        id: activeIndicator
                        width: bottomNav.stepWidth - 4; height: 31
                        radius: 15; y: 2
                        x: 2 + (bottomNav.currentIndex * bottomNav.stepWidth)
                        color: Qt.alpha(Theme.white, 0.15)

                        Behavior on x {
                            NumberAnimation { duration: 400; easing.type: Easing.OutQuart }
                        }
                    }

                    RowLayout {
                        anchors.fill: parent; spacing: 0
                        
                        Item {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            RowLayout { anchors.centerIn: parent; spacing: 6
                                Text { text: ""; font.family: Theme.fontIcons; color: root.controlCenterTab === "wifi" ? "#5bc0eb" : Theme.grey1; font.pixelSize: 12 }
                                Text { text: "Wi-Fi"; color: Theme.white; font.bold: true; font.pixelSize: 11; visible: root.controlCenterTab === "wifi" }
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.controlCenterTab = "wifi" }
                        }
                        
                        Item {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            RowLayout { anchors.centerIn: parent; spacing: 6
                                Text { text: ""; font.family: Theme.fontIcons; color: root.controlCenterTab === "bluetooth" ? "#cbaacb" : Theme.grey1; font.pixelSize: 12 }
                                Text { text: "Bluetooth"; color: Theme.white; font.bold: true; font.pixelSize: 11; visible: root.controlCenterTab === "bluetooth" }
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.controlCenterTab = "bluetooth" }
                        }
                        
                        Item {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            RowLayout { anchors.centerIn: parent; spacing: 6
                                Text { text: "󰕾"; font.family: Theme.fontIcons; color: root.controlCenterTab === "audio" ? "#e74c3c" : Theme.grey1; font.pixelSize: 12 }
                                Text { text: "Audio"; color: Theme.white; font.bold: true; font.pixelSize: 11; visible: root.controlCenterTab === "audio" }
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.controlCenterTab = "audio" }
                        }
                        
                        Item {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            RowLayout { anchors.centerIn: parent; spacing: 6
                                Text { 
                                    text: "󰓅"; font.family: Theme.fontIcons; 
                                    color: root.controlCenterTab === "performance" ? (root.perfMode === "power-saver" ? "#2ecc71" : root.perfMode === "performance" ? "#f39c12" : Theme.white) : Theme.grey1; 
                                    font.pixelSize: 12 
                                }
                                Text { text: "Perf"; color: Theme.white; font.bold: true; font.pixelSize: 11; visible: root.controlCenterTab === "performance" }
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.controlCenterTab = "performance" }
                        }
                    }
                }
            }
        }
    }

    // --- ZONA DE GATILLO DEL DOCK ---
    PanelWindow {
        id: dockTriggerZone
        anchors { bottom: true; left: true; right: true }
        implicitHeight: 2 
        color: "transparent"
        WlrLayershell.layer: WlrLayershell.Top
        
        MouseArea {
            id: triggerArea
            anchors.fill: parent
            hoverEnabled: true
            onEntered: { root.isDockHovered = true; dockHideTimer.stop(); }
            onExited: dockHideTimer.start()
        }
    }

    // --- TEMPORIZADOR DE DEBOUNCE PARA EL DOCK ---
    Timer {
        id: dockHideTimer
        interval: 350
        onTriggered: {
            if (!dockHoverHandler.hovered && !triggerArea.containsMouse) {
                root.isDockHovered = false;
            }
        }
    }

    // --- COMPONENTE DEL DOCK ---
    PanelWindow {
        id: customDockWindow
        anchors { bottom: true }
        margins { bottom: root.bottomGap } 

        WlrLayershell.layer: WlrLayershell.Overlay 
        exclusiveZone: 0
        color: "transparent"

        implicitWidth: dockLayout.implicitWidth + 30
        implicitHeight: 58 

        Item {
            anchors.fill: parent
            
            property bool showDock: root.isMacosMode || root.isWorkspaceEmpty || root.isDockHovered
            
            opacity: showDock ? 1 : 0
            visible: opacity > 0

            transform: Translate {
                y: parent.showDock ? 0 : 25
                Behavior on y {
                    NumberAnimation { duration: 400; easing.type: Easing.OutQuint }
                }
            }
            
            Behavior on opacity {
                NumberAnimation { duration: 300; easing.type: Easing.OutQuint }
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.bgGlass
                radius: height / 2
                border.color: Qt.alpha(Theme.white, 0.15)
                border.width: 1

                HoverHandler {
                    id: dockHoverHandler
                    onHoveredChanged: {
                        if (hovered) {
                            root.isDockHovered = true;
                            dockHideTimer.stop();
                        } else {
                            dockHideTimer.start();
                        }
                    }
                }

                RowLayout {
                    id: dockLayout
                    anchors.centerIn: parent
                    spacing: 14 

                    Repeater {
                        model: [
                            { type: "font", icon: "󰈹", cmd: "firefox" },
                            { type: "font", icon: "󰉋", cmd: "dolphin" },
                            { type: "font", icon: "󰆍", cmd: "kitty" },
                            { type: "font", icon: "󰨞", cmd: "code" },
                            { type: "svg",  icon: "icons/discord.svg", cmd: "discord" },
                            { type: "font", icon: "󰓇", cmd: "spotify" },
                            { type: "font", icon: "󰖣", cmd: "firefox --new-window https://web.whatsapp.com" },
                            { type: "svg",  icon: "icons/obsidian.svg", cmd: "obsidian" },
                            { type: "svg",  icon: "icons/notion.svg", cmd: "firefox --new-window https://www.notion.so" },
                        ]

                        Rectangle {
                            width: 44; height: 44; radius: 22 
                            
                            color: iconMouseArea.containsMouse ? Qt.alpha(Theme.white, 0.1) : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Text {
                                anchors.centerIn: parent
                                visible: modelData.type !== "svg"
                                text: modelData.icon
                                font.family: Theme.fontIcons
                                font.pixelSize: 24 
                                color: Theme.white
                            }

                            Image {
                                id: svgIcon
                                anchors.centerIn: parent
                                width: 22; height: 22
                                visible: false
                                source: modelData.type === "svg" ? modelData.icon : ""
                                sourceSize.width: 22
                                sourceSize.height: 22
                                smooth: true
                                fillMode: Image.PreserveAspectFit
                            }

                            ColorOverlay {
                                anchors.fill: svgIcon
                                source: svgIcon
                                color: Theme.white
                                visible: modelData.type === "svg"
                            }

                            MouseArea {
                                id: iconMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    dockLauncherProc.command = ["bash", "-c", modelData.cmd + " & disown"]
                                    dockLauncherProc.running = true
                                }
                            }
                        }
                    }
                }
            }
        }

        Process { id: dockLauncherProc }
    }

    // --- COMPONENTE OVERLAY DE ALT+TAB ---
    AltTabOverlay {
        rootRef: root
    }
}