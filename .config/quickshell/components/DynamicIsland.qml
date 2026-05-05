import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Io 
import ".."

PanelWindow {
    id: islandWindow

    anchors {
        top: true
    }
    margins { 
        top: -38
    } 

    WlrLayershell.layer: WlrLayershell.Overlay
    exclusiveZone: 0
    color: "transparent"

    implicitWidth: 480
    implicitHeight: 240

    mask: Region {
        item: visualBg
    }

    function triggerMsg(icon, color, text) {
        triggerTextNotification(icon, text, color);
    }

    // --- MUSIC PROPERTIES ---
    property var playerList: (Mpris.players && Mpris.players.values) ? Mpris.players.values : []
    property var blacklist: ["firefox", "chromium", "brave", "mpv", "playerctl", "kdeconnect"]
    
    property var activePlayer: {
        if (playerList.length === 0) return null;
        var fallbackPlayer = null;
        for (var i = 0; i < playerList.length; i++) {
            var p = playerList[i];
            if (!p) continue;
            var fullName = (p.identity ? p.identity.toLowerCase() : "") + " " + (p.busName ? p.busName.toLowerCase() : "");
            if (fullName.indexOf("spotify") !== -1) return p;
            
            var isBlacklisted = false;
            for (var j = 0; j < blacklist.length; j++) {
                if (fullName.indexOf(blacklist[j]) !== -1) { isBlacklisted = true; break; }
            }
            if (!isBlacklisted && fallbackPlayer === null) fallbackPlayer = p;
        }
        return fallbackPlayer;
    }
    
    property bool isPlayerAvailable: activePlayer !== null
    
    property string songTitle: {
        if (!activePlayer) return "No music playing";
        var title = activePlayer.trackTitle || (activePlayer.metadata ? activePlayer.metadata["xesam:title"] : null);
        return title ? String(title) : "Unknown";
    }
    
    property string songArtist: {
        if (!activePlayer) return "Open Spotify";
        var artist = activePlayer.trackArtists || activePlayer.trackArtist || (activePlayer.metadata ? activePlayer.metadata["xesam:artist"] : null);
        if (Array.isArray(artist)) return artist.join(", ");
        return artist ? String(artist) : "Unknown";
    }
    
    property string songArt: {
        if (!activePlayer) return "";
        var art = activePlayer.trackArtUrl || (activePlayer.metadata ? activePlayer.metadata["mpris:artUrl"] : null);
        return art ? String(art) : "";
    }
    
    property bool isPlaying: activePlayer ? (activePlayer.playbackState === 1 || activePlayer.playbackStatus === "Playing") : false
    property bool isShuffle: activePlayer ? (activePlayer.shuffle || false) : false
    
    property string loopStatus: {
        if (!activePlayer) return "None";
        var ls = activePlayer.loopStatus;
        if (ls === 1 || ls === "Track") return "Track";
        if (ls === 2 || ls === "Playlist") return "Playlist";
        return "None";
    }

    property int currentTab: 0
    property int totalTabs: 2 // Reducido a 2 pestañas
    
    property real trackPosition: 0
    property real trackLength: 1 
    property bool isUserSeeking: false 

    Timer {
        id: positionPoller
        interval: 500 
        running: islandWindow.isExpanded && islandWindow.isPlayerAvailable && currentTab === 0
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (islandWindow.activePlayer && !islandWindow.isUserSeeking) {
                islandWindow.trackPosition = islandWindow.activePlayer.position || 0;
                islandWindow.trackLength = islandWindow.activePlayer.length || 1;
            }
        }
    }

    function formatTime(timeInSeconds) {
        if (!timeInSeconds || timeInSeconds <= 0) return "0:00";
        var totalSeconds = Math.floor(timeInSeconds);
        var m = Math.floor(totalSeconds / 60);
        var s = totalSeconds % 60;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    Process { id: quickCommand }
    function execCmd(cmd) { quickCommand.command = ["bash", "-c", cmd]; quickCommand.running = true; }

    // --- SISTEMA DE COLA DE NOTIFICACIONES ---
    property bool isNotifying: false
    property string notifyIcon: ""
    property string notifyText: ""
    property real notifyProgress: 0
    property bool notifyMuted: false
    property string notifyColor: "white"
    property var notifQueue: [] 

    function processQueue() {
        if (isNotifying || notifQueue.length === 0) return;
        var item = notifQueue.shift(); 
        notifyIcon = item.icon; notifyText = item.text; notifyProgress = item.progress; notifyMuted = item.muted; notifyColor = item.color;
        isNotifying = true;
        notificationTimeout.restart();
    }

    Timer { 
        id: notificationTimeout; interval: 2200; onTriggered: { isNotifying = false; Qt.callLater(processQueue); }
    }

    function triggerProgressNotification(icon, progress, muted, customColor) {
        if (islandWindow.isExpanded) return;
        if (isNotifying && notifyText === "") {
            notifyIcon = icon; notifyProgress = progress; notifyMuted = muted; notifyColor = customColor ? customColor : Theme.white;
            notificationTimeout.restart(); return;
        }
        notifQueue.push({ "icon": icon, "text": "", "progress": progress, "muted": muted, "color": customColor ? customColor : Theme.white });
        processQueue();
    }

    function triggerTextNotification(icon, text, customColor) {
        if (islandWindow.isExpanded) return;
        notifQueue.push({ "icon": icon, "text": text, "progress": 0, "muted": false, "color": customColor ? customColor : Theme.white });
        processQueue();
        execCmd("paplay /usr/share/sounds/freedesktop/stereo/message.oga 2>/dev/null &");
    }

    // =========================================================
    // MOTORES DE EVENTOS Y MONITORIZACIÓN (0% CPU BACKGROUND)
    // =========================================================
    property real lastVol: 0
    property bool lastVolMuted: false
    property real lastBri: 0
    property real lastMic: 0
    property bool lastMicMuted: false
    property bool firstReadComplete: false

    // 1. EVENTOS OSD (Volumen, Micrófono, Brillo, y punto indicador de Micro activo)
    Process {
        id: osdEventProc
        command: [
            "bash", "-c",
            "LC_ALL=C; F=/tmp/qs_osd_fifo; rm -f $F; mkfifo $F; exec 3<> $F; " +
            "pactl subscribe 2>/dev/null | grep --line-buffered -E '(sink|source)' | while read -r _; do echo 'SND' >&3; done & " +
            "udevadm monitor --subsystem-match=backlight 2>/dev/null | grep --line-buffered 'change' | while read -r _; do echo 'BRI' >&3; done & " +
            "trap 'kill $(jobs -p) 2>/dev/null; rm -f $F' EXIT; " +
            "check_osd() { " +
            "  vf=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || echo '0 0'); vol=${vf#* }; vol=${vol% \\[MUTED\\]}; [[ \"$vf\" == *MUTED* ]] && vm=1 || vm=0; " +
            "  mf=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null || echo '0 0'); mic=${mf#* }; mic=${mic% \\[MUTED\\]}; [[ \"$mf\" == *MUTED* ]] && mm=1 || mm=0; " +
            "  b_raw=$(brightnessctl -m 2>/dev/null || echo '0,0,0,0%'); IFS=, read -r c d v p m <<< \"$b_raw\"; bri=${p%%%}; " +
            "  mic_active=$(pactl list source-outputs 2>/dev/null | awk 'tolower($0)~/application\\.name =/ && tolower($0)!~/cava/ {c++} END {print c+0}'); " +
            "  echo \"$vol;$vm;$mic;$mm;$bri;$mic_active\"; " +
            "}; check_osd; while read -r _ <&3; do check_osd; done"
        ]
        running: true
        stdout: SplitParser {
            onRead: function(data) {
                var p = data.trim().split(";");
                if (p.length >= 6) {
                    var v = parseFloat(p[0]) || 0; var vm = p[1] === "1";
                    var m = parseFloat(p[2]) || 0; var mm = p[3] === "1";
                    var b = (parseFloat(p[4]) || 0) / 100;
                    globalMicActive = parseInt(p[5]) > 0;

                    if (firstReadComplete) {
                        if (Math.abs(v - lastVol) > 0.005 || vm !== lastVolMuted) triggerProgressNotification(vm ? "󰝟" : "󰕾", v, vm, null);
                        else if (Math.abs(b - lastBri) > 0.005) triggerProgressNotification("󰃠", b, false, null);
                        else if (Math.abs(m - lastMic) > 0.005 || mm !== lastMicMuted) triggerProgressNotification(mm ? "󰍭" : "󰍬", m, mm, null);
                    }
                    lastVol = v; lastVolMuted = vm; lastBri = b; lastMic = m; lastMicMuted = mm;
                    firstReadComplete = true;
                }
            }
        }
    }

    // 2. EVENTOS DE BATERÍA
    property real batCap: 100
    property string batStatus: "Unknown"
    property string lastBatStat: ""
    property bool lowBatNotified: false
    property bool fullBatNotified: false

    Process {
        id: batEventProc
        command: [
            "bash", "-c",
            "F=/tmp/qs_bat_fifo; rm -f $F; mkfifo $F; exec 3<> $F; " +
            "udevadm monitor --subsystem-match=power_supply 2>/dev/null | grep --line-buffered 'change' | while read -r _; do echo 'BAT' >&3; done & " +
            "trap 'kill $(jobs -p) 2>/dev/null; rm -f $F' EXIT; " +
            "check_bat() { " +
            "  read cap < /sys/class/power_supply/BAT*/capacity 2>/dev/null || cap=100; " +
            "  read stat < /sys/class/power_supply/BAT*/status 2>/dev/null || stat=\"Unknown\"; " +
            "  echo \"$cap;$stat\"; " +
            "}; check_bat; while read -r _ <&3; do check_bat; done"
        ]
        running: true
        stdout: SplitParser {
            onRead: function(data) {
                var p = data.trim().split(";");
                if (p.length >= 2) {
                    batCap = parseFloat(p[0]) || 100;
                    batStatus = p[1].trim();

                    if (lastBatStat !== "" && batStatus !== lastBatStat) {
                        if (batStatus === "Charging" || batStatus === "Full") triggerTextNotification("󱐋", "Power connected", "#30d158");
                        else if (batStatus === "Discharging") triggerTextNotification("󱐋", "Power disconnected", "white");
                    }
                    lastBatStat = batStatus;
                    
                    if (batCap <= 20 && batStatus === "Discharging") {
                        if (!lowBatNotified) { triggerTextNotification("󰂃", "Low battery, please charge", "#ff3b30"); lowBatNotified = true; }
                    } else lowBatNotified = false;

                    if (batCap >= 85 && batStatus === "Charging") {
                        if (!fullBatNotified) { triggerTextNotification("󰂄", "Battery charged (85%)", "#30d158"); fullBatNotified = true; }
                    } else fullBatNotified = false;
                }
            }
        }
    }

    // 3. EVENTOS DE CÁMARA (Shutter)
    Process {
        command: ["bash", "-c", "while inotifywait -qq -e create /tmp; do if [ -f /tmp/qs_shutter ]; then echo 'FLASH'; rm -f /tmp/qs_shutter; fi; done"]
        running: true
        stdout: SplitParser {
            onRead: function(data) {
                var lines = data.trim().split("\n");
                for (var i = 0; i < lines.length; i++) {
                    if (lines[i].trim() === "FLASH") {
                        execCmd("paplay /usr/share/sounds/freedesktop/stereo/camera-shutter.oga 2>/dev/null &");
                        shutterFlashAnim.restart();
                    }
                }
            }
        }
    }

    // 4. RENDIMIENTO DINÁMICO (El "Watchdog")
    // Lee a fondo solo cuando la pestaña 1 está abierta. Si está cerrada, lee a nivel súper superficial.
    property real dlSpeed: 0
    property real globalCt: 0
    property real globalGt: 0
    property bool globalCamActive: false
    property bool globalMicActive: false
    property real globalCu: 0
    property real globalGu: 0
    property real sysRamUsage: 0
    property string sysStorage: "0/0GB"
    
    // Alias para la UI del Tab 1
    property real sysGpuTemp: globalGt
    property real sysGpuUsage: globalGu 
    property real sysCpuTemp: globalCt
    property real sysCpuUsage: globalCu 

    Timer {
        id: watchdogTimer
        // 2s abierto, 10s cerrado
        interval: (islandWindow.isExpanded && currentTab === 1) ? 2000 : 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            watchdogProc.tabOpen = (islandWindow.isExpanded && currentTab === 1) ? "1" : "0";
            watchdogProc.running = true;
        }
    }

    Process {
        id: watchdogProc
        property string tabOpen: "0"
        // Este script ahora no tiene ningún 'sleep'. Se ejecuta de principio a fin en unos ~5 milisegundos.
        command: [
            "bash", "-c",
            "LC_ALL=C; " +
            "F_RX=\"/tmp/qs_rx_bytes\"; [ ! -f \"$F_RX\" ] && echo 0 > \"$F_RX\"; " +
            "prev_rx=$(cat \"$F_RX\"); curr_rx=0; " +
            "for f in /sys/class/net/w*/statistics/rx_bytes; do [ -f \"$f\" ] && { read v < \"$f\"; curr_rx=$((curr_rx+v)); }; done; " +
            "echo \"$curr_rx\" > \"$F_RX\"; " +
            "inter=$([ \"$tabOpen\" = \"1\" ] && echo 2 || echo 10); " +
            "if [ \"$curr_rx\" -lt \"$prev_rx\" ]; then dl=0; else dl=$(( (curr_rx - prev_rx) / inter / 1048576 )); fi; " +
            "ct=$(sensors 2>/dev/null | awk '/Tctl|Package id 0|Core 0/ {gsub(/[^0-9.]/,\"\",$2); print $2; exit}'); " +
            "gt=$(sensors 2>/dev/null | awk '/edge/ {gsub(/[^0-9.]/,\"\",$2); print $2; exit}'); " +
            "cam=$(fuser /dev/video* 2>/dev/null | wc -w); " +
            "if [ \"$tabOpen\" = \"1\" ]; then " +
            "  cu=$(top -bn1 | awk '/Cpu\\(s\\)/ {print $2 + $4}'); " +
            "  gu=$(cat /sys/class/drm/card0/device/gpu_busy_percent 2>/dev/null || echo 0); " +
            "  ru=$(free -m | awk '/Mem:/ {printf \"%.1f\", $3/1024}'); " +
            "  st=$(df -BG / | awk 'NR==2 {gsub(\"G\",\"GB\",$4); gsub(\"G\",\"GB\",$2); print $4\"/\"$2}'); " +
            "else cu=0; gu=0; ru=0; st=\"0/0GB\"; fi; " +
            "echo \"${dl:-0};${ct:-0};${gt:-0};${cam:-0};${cu:-0};${gu:-0};${ru:-0};${st:-0/0GB}\""
        ]
        running: false
        stdout: SplitParser {
            onRead: function(data) {
                var p = data.trim().split(";");
                if (p.length >= 8) {
                    dlSpeed = parseFloat(p[0]) || 0;
                    globalCt = parseFloat(p[1]) || 0;
                    globalGt = parseFloat(p[2]) || 0;
                    globalCamActive = parseInt(p[3]) > 0;
                    
                    if (watchdogProc.tabOpen === "1") {
                        globalCu = parseFloat(p[4]) || 0;
                        globalGu = parseFloat(p[5]) || 0;
                        sysRamUsage = parseFloat(p[6]) || 0;
                        sysStorage = p[7] || "0/0GB";
                    }
                }
            }
        }
    }

    // --- LÍMITES CONFIGURABLES ---
    property real maxTemp: 85
    property real maxLoad: 90
    property real maxRam: 28
    
    property bool isOverheating: globalCt > maxTemp || globalGt > maxTemp
    property bool isOverloaded: globalCu > maxLoad || sysRamUsage >= maxRam
    property bool isBtConnected: false 
    
    property string colorTemp: "#ff3b30"
    property string colorLoad: "#ff9f0a"
    property string colorBt: "#0a84ff"  
    
    property string baseAlertColor: isOverheating ? colorTemp : (isOverloaded ? colorLoad : (isBtConnected ? colorBt : "transparent"))
    property string altAlertColor: (isOverheating && isOverloaded) ? colorLoad : (baseAlertColor !== "transparent" ? Qt.alpha(baseAlertColor, 0.2) : "transparent")

    // --- STATES AND SIZES ---
    property bool isExpanded: hoverArea.containsMouse || islandWindow.isUserSeeking

    property int targetWidth: {
        if (isExpanded) {
            if (currentTab === 0) return isPlayerAvailable ? 420 : 210;
            if (currentTab === 1) return 420; 
        }
        if (isNotifying) {
            return notifyText !== "" ? 300 : 220; 
        }
        
        var leftSideWidth = (isPlaying ? 22 : 0) + (dlSpeed >= 5 ? 18 : 0);
        var rightSideWidth = (globalMicActive ? 12 : 0) + (globalCamActive ? 12 : 0);
        return 120 + (Math.max(leftSideWidth, rightSideWidth) * 2);
    }

    property int targetHeight: {
        if (isExpanded) {
            // Reajustado perfectamente: Altura mucho más pequeña al quitar Cava
            if (currentTab === 0) return isPlayerAvailable ? 120 : 60;
            if (currentTab === 1) return 160; 
        }
        return 32;
    }

    // --- VISUAL PILL ---
    Rectangle {
        id: visualBg
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        
        width: targetWidth
        height: targetHeight
        
        color: Theme.bg0
        radius: isExpanded ? 28 : height / 2
        clip: true

        border.color: baseAlertColor !== "transparent" ? baseAlertColor : Qt.alpha(Theme.white, 0.1)
        border.width: baseAlertColor !== "transparent" ? 2 : 1
        
        SequentialAnimation on border.color {
            running: baseAlertColor !== "transparent" && !isExpanded && (isOverheating || isOverloaded)
            loops: Animation.Infinite
            ColorAnimation { to: altAlertColor; duration: 800 }
            ColorAnimation { to: baseAlertColor; duration: 800 }
        }

        Behavior on width  { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
        Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
        Behavior on radius { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }

        property bool isAnimating: Math.abs(width - targetWidth) > 1.0 || Math.abs(height - targetHeight) > 1.0

        Rectangle {
            anchors.fill: parent
            color: "white"
            opacity: 0
            radius: parent.radius
            z: 999
            
            SequentialAnimation on opacity {
                id: shutterFlashAnim
                NumberAnimation { to: 0.9; duration: 40; easing.type: Easing.OutExpo }
                NumberAnimation { to: 0; duration: 300; easing.type: Easing.InExpo }
            }
        }

        MouseArea {
            id: hoverArea
            anchors.fill: parent
            hoverEnabled: true
            
            Timer { id: wheelCooldown; interval: 400 }
            
            onWheel: (wheel) => {
                if (!islandWindow.isExpanded || wheelCooldown.running) return;
                if (wheel.angleDelta.x < -40 && currentTab < totalTabs - 1) { 
                    currentTab++; wheelCooldown.restart(); 
                } else if (wheel.angleDelta.x > 40 && currentTab > 0) { 
                    currentTab--; wheelCooldown.restart(); 
                }
            }
        }

        // ── COLLAPSED STATE: CLOCK & PASSIVE OSD ──
        Item {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            height: 32

            visible: !islandWindow.isExpanded && !islandWindow.isNotifying
            opacity: (!visualBg.isAnimating && visible) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }

            Text {
                id: customClock
                anchors.centerIn: parent
                color: Theme.white
                font.family: Theme.fontMain
                font.pixelSize: 16
                font.bold: true
            }

            Row {
                anchors.right: customClock.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Text { 
                    text: "󰇚"
                    color: Qt.alpha(Theme.white, 0.5)
                    font.family: Theme.fontIcons
                    font.pixelSize: 12
                    visible: dlSpeed >= 5 
                }
                
                Row {
                    spacing: 3
                    visible: isPlaying
                    anchors.verticalCenter: parent.verticalCenter
                    
                    Repeater {
                        model: [ {d: 800, max: 12, min: 4}, {d: 650, max: 9, min: 3}, {d: 900, max: 11, min: 4} ]
                        
                        Rectangle {
                            width: 3
                            radius: 1.5
                            color: Theme.white
                            height: modelData.min
                            anchors.verticalCenter: parent.verticalCenter
                            
                            SequentialAnimation on height {
                                running: isPlaying && !islandWindow.isExpanded
                                loops: Animation.Infinite
                                NumberAnimation { to: modelData.max; duration: modelData.d; easing.type: Easing.InOutQuad }
                                NumberAnimation { to: modelData.min; duration: modelData.d; easing.type: Easing.InOutQuad }
                            }
                        }
                    }
                }
            }

            Row {
                anchors.left: customClock.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                
                Rectangle { width: 6; height: 6; radius: 3; color: "#ff9f0a"; visible: globalMicActive }
                Rectangle { width: 6; height: 6; radius: 3; color: "#30d158"; visible: globalCamActive }
            }

            Timer { 
                interval: 2000; running: true; repeat: true; triggeredOnStart: true
                onTriggered: {
                    var timeStr = new Date().toLocaleTimeString(Qt.locale("en_US"), "hh:mm A");
                    if (customClock.text !== timeStr) customClock.text = timeStr;
                }
            }
        }

        // ── COLLAPSED STATE: ACTIVE OSD NOTIFICATION ──
        Item {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            height: 32

            visible: !islandWindow.isExpanded && islandWindow.isNotifying
            opacity: (!visualBg.isAnimating && visible) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }

            RowLayout {
                anchors.centerIn: parent
                width: parent.width - 40
                spacing: 12
                
                Text {
                    text: islandWindow.notifyIcon
                    font.family: Theme.fontIcons
                    font.pixelSize: 16
                    color: islandWindow.notifyMuted ? Qt.alpha(islandWindow.notifyColor, 0.4) : islandWindow.notifyColor
                }
                
                Rectangle {
                    visible: notifyText === ""
                    Layout.fillWidth: true
                    height: 6
                    radius: 3
                    color: Qt.alpha(islandWindow.notifyColor, 0.2)
                    
                    Rectangle {
                        height: parent.height
                        radius: 3
                        color: islandWindow.notifyMuted ? Qt.alpha(islandWindow.notifyColor, 0.4) : islandWindow.notifyColor
                        width: parent.width * Math.max(0, Math.min(1, islandWindow.notifyProgress))
                        Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                    }
                }
                
                Text {
                    visible: notifyText === ""
                    text: Math.round(islandWindow.notifyProgress * 100) + "%"
                    color: islandWindow.notifyMuted ? Qt.alpha(islandWindow.notifyColor, 0.6) : islandWindow.notifyColor
                    font.pixelSize: 11
                    font.family: Theme.fontMain
                    font.bold: true
                    Layout.minimumWidth: 30
                    horizontalAlignment: Text.AlignRight
                }

                Text {
                    visible: notifyText !== ""
                    text: notifyText
                    color: notifyColor
                    font.family: Theme.fontMain
                    font.pixelSize: 13
                    font.bold: true
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignLeft
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
        }

        // ── EXPANDED STATE: TABS ──
        Item {
            anchors.fill: parent
            visible: islandWindow.isExpanded && !visualBg.isAnimating
            opacity: visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 100 } }

            // ================================
            // TAB 0: MUSIC PLAYER (SIN CAVA)
            // ================================
            Item {
                width: parent.width
                height: parent.height
                x: (0 - currentTab) * width
                opacity: currentTab === 0 ? 1 : 0
                Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.OutQuint } }
                Behavior on opacity { NumberAnimation { duration: 250 } }
                visible: opacity > 0 

                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width * 0.90
                    height: parent.height * 0.85
                    spacing: 10
                    anchors.verticalCenterOffset: -5 

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14

                        Rectangle {
                            Layout.preferredWidth: 70
                            Layout.preferredHeight: 70
                            Layout.alignment: Qt.AlignVCenter
                            radius: 12
                            color: Theme.bg1
                            clip: true
                            visible: islandWindow.isPlayerAvailable

                            Image { 
                                anchors.fill: parent
                                source: islandWindow.songArt
                                fillMode: Image.PreserveAspectCrop
                                visible: source !== "" 
                            }
                            Text { 
                                anchors.centerIn: parent
                                text: "󰎈"
                                font.family: Theme.fontIcons
                                color: Theme.white
                                font.pixelSize: 30
                                visible: parent.children[0].source == "" 
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Layout.alignment: Qt.AlignVCenter
                            
                            Text { 
                                text: islandWindow.songTitle
                                color: Theme.white
                                font.family: Theme.fontMain
                                font.pixelSize: 15
                                font.bold: true
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter 
                            }
                            Text { 
                                text: islandWindow.songArtist
                                color: Theme.grey1
                                font.family: Theme.fontMain
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter 
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.topMargin: 5
                                spacing: 14
                                visible: islandWindow.isPlayerAvailable
                                
                                Text { 
                                    text: "󰒟"
                                    font.family: Theme.fontIcons
                                    font.pixelSize: 17
                                    color: islandWindow.isShuffle ? Theme.white : Qt.alpha(Theme.white, 0.4)
                                    MouseArea { 
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: if (islandWindow.isPlayerAvailable) islandWindow.activePlayer.shuffle = !islandWindow.activePlayer.shuffle;
                                    } 
                                }
                                Text { 
                                    text: "󰒮"
                                    font.family: Theme.fontIcons
                                    font.pixelSize: 20
                                    color: Theme.white
                                    MouseArea { 
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: if (islandWindow.isPlayerAvailable) islandWindow.activePlayer.previous() 
                                    } 
                                }
                                Rectangle {
                                    width: 30
                                    height: 30
                                    radius: width / 2
                                    color: Theme.white
                                    Layout.alignment: Qt.AlignVCenter
                                    Text { 
                                        anchors.centerIn: parent
                                        text: islandWindow.isPlaying ? "󰏤" : "󰐊"
                                        font.family: Theme.fontIcons
                                        font.pixelSize: 16
                                        color: Theme.bg0 
                                    }
                                    MouseArea { 
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: { 
                                            if (!islandWindow.isPlayerAvailable) return;
                                            if (islandWindow.isPlaying) islandWindow.activePlayer.pause(); 
                                            else islandWindow.activePlayer.play(); 
                                        } 
                                    }
                                }
                                Text { 
                                    text: "󰒭"
                                    font.family: Theme.fontIcons
                                    font.pixelSize: 20
                                    color: Theme.white
                                    MouseArea { 
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: if (islandWindow.isPlayerAvailable) islandWindow.activePlayer.next() 
                                    } 
                                }
                                Text { 
                                    text: islandWindow.loopStatus === "Track" ? "󰑘" : "󰑖"
                                    font.family: Theme.fontIcons
                                    font.pixelSize: 17
                                    color: islandWindow.loopStatus !== "None" ? Theme.white : Qt.alpha(Theme.white, 0.4)
                                    MouseArea { 
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: { 
                                            if (!islandWindow.isPlayerAvailable) return; 
                                            let current = islandWindow.activePlayer.loopStatus;
                                            if (current === 0) islandWindow.activePlayer.loopStatus = 2; 
                                            else if (current === 2) islandWindow.activePlayer.loopStatus = 1; 
                                            else islandWindow.activePlayer.loopStatus = 0;
                                        } 
                                    } 
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        visible: islandWindow.isPlayerAvailable
                        spacing: 8
                        
                        Text { 
                            text: islandWindow.formatTime(islandWindow.trackPosition)
                            color: Qt.alpha(Theme.white, 0.6)
                            font.pixelSize: 11
                            font.family: Theme.fontMain
                            Layout.minimumWidth: 35
                            horizontalAlignment: Text.AlignRight 
                        }
                        
                        MouseArea {
                            id: progressArea
                            Layout.fillWidth: true
                            Layout.preferredHeight: 16
                            Layout.alignment: Qt.AlignVCenter
                            cursorShape: Qt.PointingHandCursor
                            
                            onPressed: { islandWindow.isUserSeeking = true; seekToMouse(); }
                            onPositionChanged: { if (pressed) seekToMouse(); }
                            onReleased: { 
                                islandWindow.isUserSeeking = false;
                                if (islandWindow.activePlayer) islandWindow.activePlayer.position = islandWindow.trackPosition; 
                            }
                            onCanceled: islandWindow.isUserSeeking = false;
                            
                            function seekToMouse() { 
                                if (!islandWindow.isPlayerAvailable || islandWindow.trackLength <= 0) return;
                                var percent = Math.max(0, Math.min(1, mouseX / width)); 
                                var newPos = percent * islandWindow.trackLength; 
                                islandWindow.trackPosition = newPos;
                                if (islandWindow.activePlayer) islandWindow.activePlayer.position = newPos; 
                            }
                            
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 6
                                radius: 3
                                color: Qt.alpha(Theme.white, 0.2)
                                
                                Rectangle {
                                    height: parent.height
                                    radius: 3
                                    color: Theme.white
                                    property double progress: (islandWindow.trackLength > 0) ? (islandWindow.trackPosition / islandWindow.trackLength) : 0
                                    Behavior on width { enabled: !islandWindow.isUserSeeking; NumberAnimation { duration: 500; easing.type: Easing.Linear } }
                                    width: parent.width * Math.max(0, Math.min(1, progress))
                                    
                                    Rectangle { 
                                        width: 10; height: 10; radius: 5; color: Theme.white
                                        anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; anchors.rightMargin: -4
                                        scale: islandWindow.isUserSeeking ? 1.3 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 150 } } 
                                    }
                                }
                            }
                        }
                        Text { 
                            text: islandWindow.formatTime(islandWindow.trackLength)
                            color: Qt.alpha(Theme.white, 0.6)
                            font.pixelSize: 11
                            font.family: Theme.fontMain
                            Layout.minimumWidth: 35 
                        }
                    }
                }
            }

            // ================================
            // TAB 1: REAL PERFORMANCE MONITOR
            // ================================
            Item {
                width: parent.width
                height: parent.height
                x: (1 - currentTab) * width
                opacity: currentTab === 1 ? 1 : 0
                Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.OutQuint } }
                Behavior on opacity { NumberAnimation { duration: 250 } }
                visible: opacity > 0

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 15
                    spacing: 20
                    
                    Repeater {
                        model: [ 
                            { temp: sysGpuTemp, usage: sysGpuUsage, tLabel: "GPU temp", uLabel: "Usage" }, 
                            { temp: sysCpuTemp, usage: sysCpuUsage, tLabel: "CPU temp", uLabel: "Usage" } 
                        ]
                        
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            
                            Item {
                                width: 100
                                height: 100
                                anchors.centerIn: parent
                                
                                Canvas {
                                    anchors.fill: parent
                                    property real progress: modelData.usage / 100.0
                                    Behavior on progress { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                                    onProgressChanged: requestPaint()
                                    onPaint: { 
                                        var ctx = getContext("2d");
                                        ctx.clearRect(0, 0, width, height); 
                                        var center = width / 2; var radius = center - 4;
                                        var start = 0.75 * Math.PI; var end = 2.25 * Math.PI; 
                                        ctx.lineCap = "round"; 
                                        ctx.beginPath(); ctx.arc(center, center, radius, start, end); 
                                        ctx.lineWidth = 5; ctx.strokeStyle = Qt.alpha(Theme.white, 0.1); ctx.stroke();
                                        if(progress > 0) { 
                                            ctx.beginPath(); ctx.arc(center, center, radius, start, start + (progress * (end - start))); 
                                            ctx.lineWidth = 5; ctx.strokeStyle = Theme.white; ctx.stroke();
                                        } 
                                    }
                                }
                                
                                Column { 
                                    anchors.centerIn: parent
                                    spacing: -2
                                    Text { 
                                        text: Math.round(modelData.temp) + "°C"
                                        color: modelData.temp > maxTemp ? colorTemp : Theme.white
                                        font.family: Theme.fontMain; font.pixelSize: 22; font.bold: true
                                        anchors.horizontalCenter: parent.horizontalCenter 
                                    }
                                    Text { text: modelData.tLabel; color: Qt.alpha(Theme.white, 0.6); font.family: Theme.fontMain; font.pixelSize: 10; anchors.horizontalCenter: parent.horizontalCenter } 
                                }
                                
                                Column { 
                                    anchors.bottom: parent.bottom; anchors.right: parent.right; anchors.bottomMargin: 0
                                    spacing: -2
                                    Text { 
                                        text: Math.round(modelData.usage) + "%"
                                        color: modelData.usage > maxLoad ? colorLoad : Theme.white
                                        font.family: Theme.fontMain; font.pixelSize: 11; font.bold: true
                                        anchors.right: parent.right 
                                    }
                                    Text { text: modelData.uLabel; color: Qt.alpha(Theme.white, 0.6); font.family: Theme.fontMain; font.pixelSize: 9; anchors.right: parent.right } 
                                }
                            }
                        }
                    }
                    
                    Item { 
                        Layout.fillWidth: true; Layout.fillHeight: true
                        
                        Item {
                            width: 100; height: 100; anchors.centerIn: parent
                            
                            Canvas {
                                anchors.fill: parent
                                property real progress: sysRamUsage / 32.0
                                Behavior on progress { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                                onProgressChanged: requestPaint()
                                onPaint: { 
                                    var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height); 
                                    var center = width/2; var radius = center-4; 
                                    var start = 0.75*Math.PI; var end = 2.25*Math.PI;
                                    ctx.lineCap="round"; ctx.beginPath(); ctx.arc(center, center, radius, start, end); 
                                    ctx.lineWidth=5; ctx.strokeStyle=Qt.alpha(Theme.white, 0.1); ctx.stroke();
                                    if(progress>0){ ctx.beginPath(); ctx.arc(center, center, radius, start, start+(progress*(end-start))); ctx.lineWidth=5; ctx.strokeStyle=Theme.white; ctx.stroke(); } 
                                }
                            }
                            
                            Column { 
                                anchors.centerIn: parent; spacing: -2
                                Text { text: sysRamUsage.toFixed(1) + "GB"; color: sysRamUsage >= maxRam ? colorLoad : Theme.white; font.family: Theme.fontMain; font.pixelSize: 19; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                                Text { text: "Memory"; color: Qt.alpha(Theme.white, 0.6); font.family: Theme.fontMain; font.pixelSize: 10; anchors.horizontalCenter: parent.horizontalCenter } 
                            }
                            
                            Column { 
                                anchors.bottom: parent.bottom; anchors.right: parent.right; anchors.bottomMargin: 0; spacing: -2
                                Text { text: sysStorage; color: Theme.white; font.family: Theme.fontMain; font.pixelSize: 10; font.bold: true; anchors.right: parent.right }
                                Text { text: "Storage"; color: Qt.alpha(Theme.white, 0.6); font.family: Theme.fontMain; font.pixelSize: 9; anchors.right: parent.right } 
                            }
                        }
                    }
                }
            }

            // ================================
            // PAGINATION INDICATOR (Dots)
            // ================================
            Row {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6
                
                visible: totalTabs > 1 && islandWindow.isExpanded
                
                Repeater {
                    model: totalTabs
                    Rectangle {
                        width: currentTab === index ? 16 : 6
                        height: 6
                        radius: 3
                        color: Theme.white
                        opacity: currentTab === index ? 0.9 : 0.3
                        
                        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }
                        Behavior on opacity { NumberAnimation { duration: 300 } }
                    }
                }
            }
        }
    }
}