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

    // Función pública para recibir mensajes del Launcher directamente en memoria
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
            
            if (fullName.indexOf("spotify") !== -1) {
                return p;
            }
            
            var isBlacklisted = false;
            for (var j = 0; j < blacklist.length; j++) {
                if (fullName.indexOf(blacklist[j]) !== -1) { 
                    isBlacklisted = true;
                    break; 
                }
            }
            
            if (!isBlacklisted && fallbackPlayer === null) {
                fallbackPlayer = p;
            }
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
    property int totalTabs: 4 
    
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

    Process { 
        id: quickCommand 
    }
    
    function execCmd(cmd) { 
        quickCommand.command = ["bash", "-c", cmd];
        quickCommand.running = true; 
    }

    // --- SISTEMA DE COLA DE NOTIFICACIONES ---
    property bool isNotifying: false
    property string notifyIcon: ""
    property string notifyText: ""
    property real notifyProgress: 0
    property bool notifyMuted: false
    property string notifyColor: "white"

    // FIX: Usamos un Array puro de JS, adiós a los problemas del ListModel
    property var notifQueue: [] 

    function processQueue() {
        if (isNotifying || notifQueue.length === 0) return;
        
        // Saca el primer elemento de la cola de forma segura
        var item = notifQueue.shift(); 
        
        notifyIcon = item.icon;
        notifyText = item.text;
        notifyProgress = item.progress;
        notifyMuted = item.muted;
        notifyColor = item.color;
        
        isNotifying = true;
        notificationTimeout.restart();
    }

    Timer { 
        id: notificationTimeout
        interval: 2200 
        onTriggered: {
            isNotifying = false;
            Qt.callLater(processQueue);
        }
    }

    function triggerProgressNotification(icon, progress, muted, customColor) {
        if (islandWindow.isExpanded) return;

        // BYPASS ANTI-LAG: Si la isla ya está mostrando un slider (texto vacío),
        // actualizamos los valores en tiempo real y reseteamos el temporizador.
        if (isNotifying && notifyText === "") {
            notifyIcon = icon;
            notifyProgress = progress;
            notifyMuted = muted;
            notifyColor = customColor ? customColor : Theme.white;
            notificationTimeout.restart();
            return;
        }

        // Si la isla está cerrada o mostrando un mensaje de texto, usamos la cola normal
        notifQueue.push({
            "icon": icon, 
            "text": "", 
            "progress": progress, 
            "muted": muted, 
            "color": customColor ? customColor : Theme.white
        });
        processQueue();
    }

    function triggerTextNotification(icon, text, customColor) {
        if (islandWindow.isExpanded) return;
        notifQueue.push({
            "icon": icon, 
            "text": text, 
            "progress": 0, 
            "muted": false, 
            "color": customColor ? customColor : Theme.white
        });
        processQueue();
        execCmd("paplay /usr/share/sounds/freedesktop/stereo/message.oga 2>/dev/null &");
    }

    // --- OSD PROPERTIES GLOBALES ---
    property real lastVol: 0
    property bool lastVolMuted: false
    property real lastBri: 0
    property real lastMic: 0
    property bool lastMicMuted: false
    property bool firstReadComplete: false

    // 1. FAST MONITOR (Volume, Mic, Brightness)
    Process {
        id: globalOsdMonitor
        command: ["bash", "-c", "LC_ALL=C; while true; do vf=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || echo '0 0'); vol=${vf#* }; vol=${vol% \\[MUTED\\]}; [[ \"$vf\" == *MUTED* ]] && vm=1 || vm=0; mf=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null || echo '0 0'); mic=${mf#* }; mic=${mic% \\[MUTED\\]}; [[ \"$mf\" == *MUTED* ]] && mm=1 || mm=0; b_raw=$(brightnessctl -m 2>/dev/null || echo '0,0,0,0%'); IFS=, read -r c d v p m <<< \"$b_raw\"; bri=${p%%%}; echo \"$vol;$vm;$mic;$mm;$bri\"; sleep 0.15; done"]
        running: true
        stdout: SplitParser {
            onRead: {
                var lines = data.trim().split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var p = lines[i].split(";");
                    
                    if (p.length >= 5) {
                        var v = parseFloat(p[0]) || 0;
                        var vm = p[1] === "1";
                        var m = parseFloat(p[2]) || 0;
                        var mm = p[3] === "1";
                        var b = (parseFloat(p[4]) || 0) / 100;

                        if (firstReadComplete) {
                            if (Math.abs(v - lastVol) > 0.005 || vm !== lastVolMuted) {
                                triggerProgressNotification(vm ? "󰝟" : "󰕾", v, vm, null);
                            } else if (Math.abs(b - lastBri) > 0.005) {
                                triggerProgressNotification("󰃠", b, false, null);
                            } else if (Math.abs(m - lastMic) > 0.005 || mm !== lastMicMuted) {
                                triggerProgressNotification(mm ? "󰍭" : "󰍬", m, mm, null);
                            }
                        }
                        
                        lastVol = v; lastVolMuted = vm; lastBri = b; lastMic = m; lastMicMuted = mm;
                        firstReadComplete = true;
                    }
                }
            }
        }
    }

    // 2. SLOW MONITOR (Sensors, Network, Battery, Privacy)
    property real globalCt: 0
    property real globalGt: 0
    property real batCap: 100
    property string batStatus: "Unknown"
    property bool globalCamActive: false
    property bool globalMicActive: false
    property real dlSpeed: 0
    property bool lowBatNotified: false
    property bool fullBatNotified: false
    
    // --- LÍMITES CONFIGURABLES ---
    property real maxTemp: 85
    property real maxLoad: 90
    property real maxRam: 28

    // --- NUEVAS PROPIEDADES DE ALERTA ---
    property real globalCu: 0
    property real globalGu: 0
    
    property bool isOverheating: globalCt > maxTemp || globalGt > maxTemp
    property bool isOverloaded: globalCu > maxLoad || sysRamUsage >= maxRam
    
    // --- NUEVA LÓGICA DE COLORES ---
    property bool isBtConnected: false // Recibe el dato desde shell.qml
    
    property string colorTemp: "#ff3b30"
    property string colorLoad: "#ff9f0a"
    property string colorBt: "#0a84ff"   // Azul estilo Apple/Bluetooth
    
    // Color principal a mostrar (El calor y la carga tienen prioridad sobre el Bluetooth)
    property string baseAlertColor: isOverheating ? colorTemp : 
                                    (isOverloaded ? colorLoad : 
                                    (isBtConnected ? colorBt : "transparent"))
    
    // Color secundario (Alterna entre Rojo/Naranja si se dan ambos, o atenúa el color base si solo se da uno)
    property string altAlertColor: (isOverheating && isOverloaded) ? colorLoad : 
                                (baseAlertColor !== "transparent" ? Qt.alpha(baseAlertColor, 0.2) : "transparent")
    property string lastBatStat: ""

    Process {
        id: globalSlowMonitor
        // Se añade la lectura de CPU (cu) y GPU (gu) al comando principal
        command: ["bash", "-c", "LC_ALL=C; while true; do rx1=0; for f in /sys/class/net/w*/statistics/rx_bytes; do [ -f \"$f\" ] && { read v < \"$f\"; rx1=$((rx1+v)); }; done; sleep 2; rx2=0; for f in /sys/class/net/w*/statistics/rx_bytes; do [ -f \"$f\" ] && { read v < \"$f\"; rx2=$((rx2+v)); }; done; dl=$(( (rx2 - rx1) / 2 / 1024 / 1024 )); ct=$(sensors 2>/dev/null | awk '/Tctl|Package id 0|Core 0/ {gsub(/[^0-9.]/,\"\",$2); print $2; exit}'); gt=$(sensors 2>/dev/null | awk '/edge/ {gsub(/[^0-9.]/,\"\",$2); print $2; exit}'); read bat_cap < /sys/class/power_supply/BAT*/capacity 2>/dev/null || bat_cap=100; read bat_stat < /sys/class/power_supply/BAT*/status 2>/dev/null || bat_stat=\"Unknown\"; cam=$(fuser /dev/video* 2>/dev/null | wc -w); mic_active=$(pactl list source-outputs 2>/dev/null | awk 'tolower($0)~/application\\.name =/ && tolower($0)!~/cava/ {c++} END {print c+0}'); cu=$(top -bn1 | awk '/Cpu\\(s\\)/ {print $2 + $4}'); gu=$(cat /sys/class/drm/card0/device/gpu_busy_percent 2>/dev/null || echo 0); echo \"${ct:-0};${gt:-0};$bat_cap;$bat_stat;$cam;$mic_active;$dl;$cu;$gu\"; done"]
        running: true
        stdout: SplitParser {
            onRead: function(data) {
                if (data && data.indexOf(";") !== -1) {
                    var p = data.split(";");
                    globalCt = parseFloat(p[0]) || 0;
                    globalGt = parseFloat(p[1]) || 0;
                    batCap = parseFloat(p[2]) || 100;
                    batStatus = p[3].trim();

                    if (lastBatStat !== "" && batStatus !== lastBatStat) {
                        if (batStatus === "Charging" || batStatus === "Full") {
                            triggerTextNotification("󱐋", "Power connected", "#30d158");
                        } else if (batStatus === "Discharging") {
                            triggerTextNotification("󱐋", "Power disconnected", "white");
                        }
                    }
                    lastBatStat = batStatus;
                    
                    globalCamActive = parseInt(p[4]) > 0;
                    globalMicActive = parseInt(p[5]) > 0;
                    dlSpeed = parseFloat(p[6]) || 0;
                    
                    // --- NUEVOS DATOS PARSEADOS ---
                    globalCu = parseFloat(p[7]) || 0;
                    globalGu = parseFloat(p[8]) || 0;
                    
                    if (batCap <= 20 && batStatus === "Discharging") {
                        if (!lowBatNotified) {
                            triggerTextNotification("󰂃", "Low battery, please charge", "#ff3b30");
                            lowBatNotified = true;
                        }
                    } else {
                        lowBatNotified = false;
                    }

                    if (batCap >= 85 && batStatus === "Charging") {
                        if (!fullBatNotified) {
                            triggerTextNotification("󰂄", "Battery charged (85%)", "#30d158");
                            fullBatNotified = true;
                        }
                    } else {
                        fullBatNotified = false;
                    }
                }
            }
        }
    }

    // 3. EVENT NOTIFICATION MONITOR (Shutter only)
    Process {
        command: ["bash", "-c", "while true; do if [[ -f /tmp/qs_shutter ]]; then echo 'FLASH'; rm -f /tmp/qs_shutter; fi; sleep 0.2; done"]
        running: true
        stdout: SplitParser {
            onRead: function(data) {
                var lines = data.trim().split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var text = lines[i].trim();
                    if (text === "FLASH") {
                        execCmd("paplay /usr/share/sounds/freedesktop/stereo/camera-shutter.oga 2>/dev/null &");
                        shutterFlashAnim.restart();
                    }
                }
            }
        }
    }

    // --- TAB SENSORS/WEATHER PROPS ---
    property real sysGpuTemp: globalGt
    property real sysGpuUsage: globalGu // Linkeado al global
    property real sysCpuTemp: globalCt
    property real sysCpuUsage: globalCu // Linkeado al global
    property real sysRamUsage: 0
    property string sysStorage: "0/0GB"

    property string wCity: "Alicante"
    property string wCurrentTemp: "--°"
    property string wCurrentWind: "-- km/h"
    property string wCurrentHum: "--%"
    property string wCurrentDesc: "Loading..."
    property string wCurrentIcon: "☁️"
    property var wForecast: []

    function getWeatherDetails(code) {
        if (code === 0) return { icon: "☀️", text: "Clear" };
        if (code === 1) return { icon: "🌤️", text: "Mostly clear" };
        if (code === 2) return { icon: "⛅", text: "Partly cloudy" };
        if (code === 3) return { icon: "☁️", text: "Overcast" };
        if (code === 45 || code === 48) return { icon: "🌫️", text: "Fog" };
        if (code >= 51 && code <= 57) return { icon: "🌧️", text: "Drizzle" };
        if (code >= 61 && code <= 67) return { icon: "🌧️", text: "Rain" };
        if (code >= 71 && code <= 77) return { icon: "❄️", text: "Snow" };
        if (code >= 80 && code <= 82) return { icon: "🌦️", text: "Showers" };
        if (code >= 85 && code <= 86) return { icon: "❄️", text: "Snow showers" };
        if (code >= 95 && code <= 99) return { icon: "⛈️", text: "Thunderstorm" };
        return { icon: "☁️", text: "Cloudy" };
    }

    // --- STATES AND SIZES ---
    property bool isExpanded: hoverArea.containsMouse || islandWindow.isUserSeeking

    property int targetWidth: {
        if (isExpanded) {
            if (currentTab === 0) return isPlayerAvailable ? 420 : 210;
            if (currentTab === 1) return 420; 
            if (currentTab === 2) return 300;
            if (currentTab === 3) return 400; 
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
            if (currentTab === 0) return isPlayerAvailable ? 190 : 60;
            if (currentTab === 1) return 160; 
            if (currentTab === 2) return 180;
            if (currentTab === 3) return 195; 
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
            // Añadimos la condición de que solo parpadee si es una alerta de hardware (calor o carga)
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
            
            Timer { 
                id: wheelCooldown
                interval: 400 
            }
            
            onWheel: (wheel) => {
                if (!islandWindow.isExpanded || wheelCooldown.running) return;
                if (wheel.angleDelta.x < -40 && currentTab < totalTabs - 1) { 
                    currentTab++;
                    wheelCooldown.restart(); 
                }
                else if (wheel.angleDelta.x > 40 && currentTab > 0) { 
                    currentTab--;
                    wheelCooldown.restart(); 
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
                
                Rectangle { 
                    width: 6; height: 6; radius: 3; color: "#ff9f0a"; 
                    visible: globalMicActive 
                }
                Rectangle { 
                    width: 6; height: 6; radius: 3; color: "#30d158"; 
                    visible: globalCamActive 
                }
            }

            Timer { 
                interval: 2000
                running: true
                repeat: true
                triggeredOnStart: true
                onTriggered: {
                    var timeStr = new Date().toLocaleTimeString(Qt.locale("en_US"), "hh:mm A");
                    if (customClock.text !== timeStr) {
                        customClock.text = timeStr;
                    }
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
                    
                    // --- NUEVAS PROPIEDADES PARA TEXTOS LARGOS ---
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    // ---------------------------------------------
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
            // TAB 0: MUSIC PLAYER
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
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (islandWindow.isPlayerAvailable) islandWindow.activePlayer.shuffle = !islandWindow.activePlayer.shuffle;
                                    } 
                                }
                                Text { 
                                    text: "󰒮"
                                    font.family: Theme.fontIcons
                                    font.pixelSize: 20
                                    color: Theme.white
                                    MouseArea { 
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
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
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
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
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (islandWindow.isPlayerAvailable) islandWindow.activePlayer.next() 
                                    } 
                                }
                                Text { 
                                    text: islandWindow.loopStatus === "Track" ? "󰑘" : "󰑖"
                                    font.family: Theme.fontIcons
                                    font.pixelSize: 17
                                    color: islandWindow.loopStatus !== "None" ? Theme.white : Qt.alpha(Theme.white, 0.4)
                                    MouseArea { 
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
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
                                    Behavior on width { 
                                        enabled: !islandWindow.isUserSeeking
                                        NumberAnimation { duration: 500; easing.type: Easing.Linear } 
                                    }
                                    width: parent.width * Math.max(0, Math.min(1, progress))
                                    
                                    Rectangle { 
                                        width: 10
                                        height: 10
                                        radius: 5
                                        color: Theme.white
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.right: parent.right
                                        anchors.rightMargin: -4
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

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 45
                        Layout.alignment: Qt.AlignBottom
                        visible: islandWindow.isPlayerAvailable
                        
                        Process {
                            id: cavaProcess
                            command: ["bash", "-c", "printf '[general]\\nframerate=30\\nbars=40\\n[output]\\nmethod=raw\\nraw_target=/dev/stdout\\ndata_format=ascii\\nascii_max_range=45\\n' > /tmp/island_cava.conf && exec stdbuf -oL cava -p /tmp/island_cava.conf"]
                            //running: islandWindow.isExpanded && islandWindow.isPlaying && currentTab === 0
                            running: islandWindow.isPlaying
                            property var levels: []
                            onRunningChanged: { if (!running) levels = []; }
                            stdout: SplitParser { 
                                onRead: function(data) { 
                                    if (data && data.indexOf(";") !== -1) cavaProcess.levels = data.split(";");
                                } 
                            }
                        }
                        
                        Row {
                            anchors.centerIn: parent
                            height: parent.height
                            spacing: 3
                            
                            Repeater {
                                model: 40 
                                Rectangle { 
                                    width: 6
                                    property real rawValue: cavaProcess.levels.length > index ? parseFloat(cavaProcess.levels[index]) * 1.2 : 2
                                    height: isNaN(rawValue) || rawValue < 2 ? 2 : Math.min(rawValue, 45)
                                    anchors.bottom: parent.bottom
                                    color: Qt.alpha(Theme.white, 0.4)
                                    radius: 3
                                    Behavior on height { NumberAnimation { duration: 45; easing.type: Easing.OutQuad } } 
                                }
                            }
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

                Process {
                    id: sysExpandedMonitor
                    command: ["bash", "-c", "LC_ALL=C; while true; do ru=$(free -m | awk '/Mem:/ {printf \"%.1f\", $3/1024}'); st=$(df -BG / | awk 'NR==2 {gsub(\"G\",\"GB\",$4); gsub(\"G\",\"GB\",$2); print $4\"/\"$2}'); echo \"$ru;$st\"; sleep 5; done"]
                    running: true
                    stdout: SplitParser { 
                        onRead: function(data) { 
                            if (data && data.indexOf(";") !== -1) { 
                                var parts = data.split(";");
                                sysRamUsage = parseFloat(parts[0])||0; 
                                sysStorage = parts[1]||"0/0GB";
                            } 
                        } 
                    }
                }

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
                                        var center = width / 2; 
                                        var radius = center - 4;
                                        var start = 0.75 * Math.PI; 
                                        var end = 2.25 * Math.PI; 
                                        ctx.lineCap = "round"; 
                                        ctx.beginPath();
                                        ctx.arc(center, center, radius, start, end); 
                                        ctx.lineWidth = 5; 
                                        ctx.strokeStyle = Qt.alpha(Theme.white, 0.1); 
                                        ctx.stroke();
                                        if(progress > 0) { 
                                            ctx.beginPath();
                                            ctx.arc(center, center, radius, start, start + (progress * (end - start))); 
                                            ctx.lineWidth = 5; 
                                            ctx.strokeStyle = Theme.white; 
                                            ctx.stroke();
                                        } 
                                    }
                                }
                                
                                Column { 
                                    anchors.centerIn: parent
                                    spacing: -2
                                    Text { 
                                        text: Math.round(modelData.temp) + "°C"
                                        color: modelData.temp > maxTemp ? colorTemp : Theme.white
                                        font.family: Theme.fontMain
                                        font.pixelSize: 22
                                        font.bold: true
                                        anchors.horizontalCenter: parent.horizontalCenter 
                                    }
                                    Text { 
                                        text: modelData.tLabel
                                        color: Qt.alpha(Theme.white, 0.6)
                                        font.family: Theme.fontMain
                                        font.pixelSize: 10
                                        anchors.horizontalCenter: parent.horizontalCenter 
                                    } 
                                }
                                
                                Column { 
                                    anchors.bottom: parent.bottom
                                    anchors.right: parent.right
                                    anchors.bottomMargin: 0
                                    spacing: -2
                                    Text { 
                                        text: Math.round(modelData.usage) + "%"
                                        color: modelData.usage > maxLoad ? colorLoad : Theme.white
                                        font.family: Theme.fontMain
                                        font.pixelSize: 11
                                        font.bold: true
                                        anchors.right: parent.right 
                                    }
                                    Text { 
                                        text: modelData.uLabel
                                        color: Qt.alpha(Theme.white, 0.6)
                                        font.family: Theme.fontMain
                                        font.pixelSize: 9
                                        anchors.right: parent.right 
                                    } 
                                }
                            }
                        }
                    }
                    
                    Item { 
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        
                        Item {
                            width: 100
                            height: 100
                            anchors.centerIn: parent
                            
                            Canvas {
                                anchors.fill: parent
                                property real progress: sysRamUsage / 32.0
                                Behavior on progress { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                                
                                onProgressChanged: requestPaint()
                                
                                onPaint: { 
                                    var ctx = getContext("2d");
                                    ctx.clearRect(0, 0, width, height); 
                                    var center = width/2; 
                                    var radius = center-4; 
                                    var start = 0.75*Math.PI; 
                                    var end = 2.25*Math.PI;
                                    ctx.lineCap="round"; 
                                    ctx.beginPath(); 
                                    ctx.arc(center, center, radius, start, end); 
                                    ctx.lineWidth=5; 
                                    ctx.strokeStyle=Qt.alpha(Theme.white, 0.1); 
                                    ctx.stroke();
                                    if(progress>0){ 
                                        ctx.beginPath();
                                        ctx.arc(center, center, radius, start, start+(progress*(end-start))); 
                                        ctx.lineWidth=5; 
                                        ctx.strokeStyle=Theme.white; 
                                        ctx.stroke(); 
                                    } 
                                }
                            }
                            
                            Column { 
                                anchors.centerIn: parent
                                spacing: -2
                                Text { 
                                    text: sysRamUsage.toFixed(1) + "GB"
                                    color: sysRamUsage >= maxRam ? colorLoad : Theme.white
                                    font.family: Theme.fontMain
                                    font.pixelSize: 19
                                    font.bold: true
                                    anchors.horizontalCenter: parent.horizontalCenter 
                                }
                                Text { 
                                    text: "Memory"
                                    color: Qt.alpha(Theme.white, 0.6)
                                    font.family: Theme.fontMain
                                    font.pixelSize: 10
                                    anchors.horizontalCenter: parent.horizontalCenter 
                                } 
                            }
                            
                            Column { 
                                anchors.bottom: parent.bottom
                                anchors.right: parent.right
                                anchors.bottomMargin: 0
                                spacing: -2
                                Text { 
                                    text: sysStorage
                                    color: Theme.white
                                    font.family: Theme.fontMain
                                    font.pixelSize: 10
                                    font.bold: true
                                    anchors.right: parent.right 
                                }
                                Text { 
                                    text: "Storage"
                                    color: Qt.alpha(Theme.white, 0.6)
                                    font.family: Theme.fontMain
                                    font.pixelSize: 9
                                    anchors.right: parent.right 
                                } 
                            }
                        }
                    }
                }
            }

            // ================================
            // TAB 2: ADVANCED CONTROL CENTER
            // ================================
            Item {
                width: parent.width
                height: parent.height
                x: (2 - currentTab) * width
                opacity: currentTab === 2 ? 1 : 0
                Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.OutQuint } }
                Behavior on opacity { NumberAnimation { duration: 250 } }
                visible: opacity > 0

                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width * 0.85
                    spacing: 12
                    
                    Repeater {
                        model: 3 
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 14
                            
                            property real currentProgress: index === 0 ? lastVol : (index === 1 ? lastMic : lastBri)
                            property bool currentMuted: index === 0 ? lastVolMuted : (index === 1 ? lastMicMuted : false)
                            property string activeIcon: index === 0 ? (currentMuted ? "" : "") : (index === 1 ? (currentMuted ? "" : "") : "")
                            property string setCmd: index === 0 ? "wpctl set-volume @DEFAULT_AUDIO_SINK@ " : (index === 1 ? "wpctl set-volume @DEFAULT_AUDIO_SOURCE@ " : "brightnessctl s ")
                            property string toggleCmd: index === 0 ? "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle" : (index === 1 ? "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle" : "")
                            property bool canMute: index !== 2
                            
                            property real visualProgress: currentProgress
                            Behavior on visualProgress { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                            Text { 
                                text: activeIcon
                                font.family: Theme.fontIcons
                                font.pixelSize: 18
                                color: currentMuted ? Qt.alpha(Theme.white, 0.4) : Theme.white
                                Layout.preferredWidth: 20 
                                horizontalAlignment: Text.AlignHCenter
                                MouseArea { 
                                    anchors.fill: parent
                                    cursorShape: canMute ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    enabled: canMute
                                    onClicked: if (canMute) execCmd(toggleCmd) 
                                }
                            }
                            
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 24
                                
                                property real handleX: Math.max(0, Math.min(1, visualProgress)) * (width - 24)
                                
                                Rectangle { 
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    height: 8
                                    radius: 4
                                    color: Qt.alpha(Theme.white, 0.2) 
                                }
                                
                                Rectangle { 
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    height: 8
                                    radius: 4
                                    color: currentMuted ? Qt.alpha(Theme.white, 0.4) : Theme.white
                                    width: parent.handleX + 12 
                                }
                                
                                Rectangle {
                                    width: 24
                                    height: 24
                                    radius: 12
                                    color: Theme.bg0
                                    border.color: currentMuted ? Qt.alpha(Theme.white, 0.4) : Theme.white
                                    border.width: 1.5
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: parent.handleX
                                    Behavior on border.color { ColorAnimation { duration: 150 } }
                                    
                                    Text { 
                                        anchors.centerIn: parent
                                        text: Math.round(currentProgress * 100)
                                        color: currentMuted ? Qt.alpha(Theme.white, 0.6) : Theme.white
                                        font.pixelSize: 9
                                        font.family: Theme.fontMain
                                        font.bold: true 
                                    }
                                }
                                
                                MouseArea { 
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onPositionChanged: (mouse) => { if (pressed) updateValue(mouse.x); }
                                    onPressed: (mouse) => updateValue(mouse.x)
                                    
                                    function updateValue(mouseX) { 
                                        var percent = Math.max(0, Math.min(1, mouseX / width));
                                        var val = index === 2 ? Math.round(percent * 100) + "%" : percent.toFixed(2); 
                                        execCmd(setCmd + val);
                                    } 
                                }
                            }
                        }
                    }
                }
            }

            // ================================
            // TAB 3: REAL WEATHER (OPENMETEO)
            // ================================
            Item {
                width: parent.width
                height: parent.height
                x: (3 - currentTab) * width
                opacity: currentTab === 3 ? 1 : 0
                Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.OutQuint } }
                Behavior on opacity { NumberAnimation { duration: 250 } }
                visible: opacity > 0

                Process {
                    id: weatherProcess
                    command: ["bash", "-c", "LC_ALL=C; while true; do curl -s --max-time 5 'https://api.open-meteo.com/v1/forecast?latitude=38.3452&longitude=-0.4815&current=temperature_2m,relative_humidity_2m,wind_speed_10m,weather_code&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=6' | tr -d '\\n'; echo ''; sleep 600; done"]
                    running: islandWindow.isExpanded && currentTab === 3
                    stdout: SplitParser {
                        onRead: function(data) {
                            if (!data || data.indexOf("{") === -1) return;
                            try {
                                var json = JSON.parse(data);
                                var current = json.current; 
                                var daily = json.daily;
                                
                                var details = islandWindow.getWeatherDetails(current.weather_code);
                                wCurrentIcon = details.icon; 
                                wCurrentDesc = details.text;
                                wCurrentTemp = Math.round(current.temperature_2m) + "°";
                                wCurrentWind = current.wind_speed_10m + " km/h"; 
                                wCurrentHum = current.relative_humidity_2m + "%";
                                
                                var newForecast = [];
                                var daysNames = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
                                for (var i = 1; i < 6; i++) {
                                    var dateParts = daily.time[i].split("-");
                                    var dateObj = new Date(dateParts[0], dateParts[1] - 1, dateParts[2]);
                                    var dayDetails = islandWindow.getWeatherDetails(daily.weather_code[i]);
                                    newForecast.push({ 
                                        day: daysNames[dateObj.getDay()], 
                                        icon: dayDetails.icon, 
                                        max: Math.round(daily.temperature_2m_max[i]), 
                                        min: Math.round(daily.temperature_2m_min[i]) 
                                    });
                                }
                                wForecast = newForecast;
                            } catch(e) {}
                        }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 20
                    
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 6
                        
                        RowLayout { 
                            spacing: 8
                            Text { 
                                text: wCurrentIcon
                                font.pixelSize: 22 
                            }
                            Text { 
                                text: wCity
                                color: Theme.white
                                font.family: Theme.fontMain
                                font.pixelSize: 15
                                font.bold: true 
                            } 
                        }
                        
                        RowLayout { 
                            spacing: 15
                            Text { 
                                text: wCurrentTemp
                                color: Theme.white
                                font.family: Theme.fontMain
                                font.pixelSize: 45
                                font.bold: true 
                            }
                            ColumnLayout { 
                                spacing: 2
                                Text { 
                                    text: wCurrentWind
                                    color: Qt.alpha(Theme.white, 0.6)
                                    font.family: Theme.fontMain
                                    font.pixelSize: 12 
                                }
                                Text { 
                                    text: wCurrentHum
                                    color: Qt.alpha(Theme.white, 0.6)
                                    font.family: Theme.fontMain
                                    font.pixelSize: 12 
                                } 
                            } 
                        }
                        
                        Text { 
                            text: wCurrentDesc
                            color: Theme.white
                            font.family: Theme.fontMain
                            font.pixelSize: 16
                            font.bold: true
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap 
                        }
                    }
                    
                    Rectangle { 
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true
                        Layout.topMargin: 10
                        Layout.bottomMargin: 10
                        color: Qt.alpha(Theme.white, 0.1) 
                    }
                    
                    ColumnLayout {
                        Layout.preferredWidth: 140
                        Layout.fillHeight: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 8
                        
                        Repeater {
                            model: wForecast
                            RowLayout { 
                                Layout.fillWidth: true
                                Text { 
                                    text: modelData.day
                                    color: Theme.white
                                    font.family: Theme.fontMain
                                    font.pixelSize: 12
                                    font.bold: true
                                    Layout.preferredWidth: 35 
                                }
                                Text { 
                                    text: modelData.icon
                                    font.pixelSize: 14
                                    Layout.alignment: Qt.AlignHCenter 
                                }
                                Item { 
                                    Layout.fillWidth: true 
                                } 
                                Text { 
                                    text: modelData.max + "°"
                                    color: Theme.white
                                    font.family: Theme.fontMain
                                    font.pixelSize: 13
                                    font.bold: true 
                                }
                                Text { 
                                    text: modelData.min + "°"
                                    color: Qt.alpha(Theme.white, 0.6)
                                    font.family: Theme.fontMain
                                    font.pixelSize: 13 
                                } 
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