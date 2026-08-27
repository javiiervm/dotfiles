import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
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

    BackgroundEffect.blurRegion: Glass.blurEnabled ? islandBlurRegion : null

    Region {
        id: islandBlurRegion
        item: visualBg
        // La región de blur debe seguir exactamente el radio visual real
        // de GlassSurface. Usar `radius` aquí dejaba la región rectangular
        // durante el estado expandido y producía pequeñas líneas rectas en
        // las tangencias superiores de las esquinas.
        radius: visualBg.glassRadius
    }

    implicitWidth: 480
    implicitHeight: 240

    mask: Region {
        item: visualBg
        // Igualamos también el input/mask de Wayland a la silueta de la isla.
        radius: visualBg.glassRadius
    }

    // --- PROPIEDAD REQUERIDA POR SHELL.QML ---
    // Ocultamos la ventana entera (no solo visualmente) en fullscreen.
    // Esto evita depender de un transform animado sobre el item enmascarado,
    // que puede desincronizarse con el input-region real de la capa Wayland.
    property bool isFullscreen: false
    visible: !isFullscreen

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
    onActivePlayerChanged: pollLoopStatus()
    
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

    // --- PALETA DINÁMICA DE LA CARÁTULA ---
    property color artworkPalettePrimary: "#d8d8d8"
    property color artworkPaletteSecondary: "#eeeeee"
    property color artworkPaletteAccent: "#ffffff"

    onSongArtChanged: updateArtworkPalette()
    
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
    property int totalTabs: 3

    // Devuelve la posición visual más cercana de una pestaña respecto a la activa.
    // A diferencia de (tabIndex - currentTab), esta distancia "envuelve" los extremos
    // del carrusel. Así, desde la pestaña 2, la 0 está a +1 isla (no a -2), y
    // desde la pestaña 0, la 2 está a -1 isla (no a +2).
    // Resultado: los saltos 2 -> 0 y 0 -> 2 se animan exactamente una pestaña
    // en la misma dirección que el resto del carrusel.
    function circularTabOffset(tabIndex) {
        var delta = tabIndex - currentTab;
        var half = totalTabs / 2;

        if (delta > half)
            delta -= totalTabs;
        else if (delta < -half)
            delta += totalTabs;

        return delta;
    }

    onIsExpandedChanged: {
        if (isExpanded && currentTab === 1) {
            watchdogTimer.restart()
        }
    }

    onCurrentTabChanged: {
        if (isExpanded && currentTab === 1) {
            watchdogTimer.restart()
        }
    }

    // --- ACTUALIZAR EN LAS PROPIEDADES DE LA ISLA ---
    property string todayTotalTime: "0h 0m"
    property string avgDailyTime: "0h 0m"
    property string vsYesterdayTime: "0h 0m"
    property var weekChartData: [0, 0, 0, 0, 0, 0, 0]
    property var weekChartTimes: ["0m", "0m", "0m", "0m", "0m", "0m", "0m"]
    property int todayDayIndex: 0
    ListModel { id: appUsageModel }

    // Todas las pestañas expandidas comparten exactamente el mismo tamaño.
    // Punto medio entre Stats (420x160) y App Usage (460x235): 440x198.
    property int expandedWidth: 440
    property int expandedHeight: 198

    property int targetWidth: {
        if (isExpanded) {
            return expandedWidth;
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
            return expandedHeight;
        }
        return 32;
    }
    
    property real trackPosition: 0
    property real trackLength: 1 
    property bool isUserSeeking: false 

    // --- ESTADO REAL DEL LOOP (via playerctl, no confiamos en la propiedad MPRIS de Quickshell) ---
    property string liveLoopStatus: "None"

    function playerBusShort() {
        if (!islandWindow.activePlayer || !islandWindow.activePlayer.busName) return "";
        return islandWindow.activePlayer.busName.replace("org.mpris.MediaPlayer2.", "");
    }

    Process {
        id: loopStatusProc
        stdout: SplitParser {
            onRead: function(data) {
                var s = data.trim();
                if (s === "Track" || s === "Playlist" || s === "None") {
                    islandWindow.liveLoopStatus = s;
                }
            }
        }
    }

    function pollLoopStatus() {
        var bus = islandWindow.playerBusShort();
        if (bus === "") return;
        loopStatusProc.command = ["bash", "-c", "playerctl -p " + bus + " loop 2>/dev/null"];
        loopStatusProc.running = true;
    }

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
            islandWindow.pollLoopStatus();
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

    // --- PALETA DE LA CARÁTULA MUSICAL ---
    // Event-driven: solo se ejecuta cuando cambia songArt.
    Process {
        id: artworkPaletteProc
        property string requestedArt: ""

        stdout: SplitParser {
            onRead: function(data) {
                if (artworkPaletteProc.requestedArt !== islandWindow.songArt)
                    return;

                var colors = data.trim().split(";");
                var hexRe = /^#[0-9a-fA-F]{6}$/;

                if (colors.length < 3
                    || !hexRe.test(colors[0])
                    || !hexRe.test(colors[1])
                    || !hexRe.test(colors[2])) {
                    return;
                }

                islandWindow.artworkPalettePrimary = colors[0];
                islandWindow.artworkPaletteSecondary = colors[1];
                islandWindow.artworkPaletteAccent = colors[2];
                progressWave.requestPaint();
            }
        }
    }

    function updateArtworkPalette() {
        var art = islandWindow.songArt;

        if (!art || art === "") {
            artworkPalettePrimary = "#d8d8d8";
            artworkPaletteSecondary = "#eeeeee";
            artworkPaletteAccent = "#ffffff";
            return;
        }

        if (artworkPaletteProc.running)
            artworkPaletteProc.running = false;

        artworkPaletteProc.requestedArt = art;
        artworkPaletteProc.command = [
            "python3",
            "/home/javier/.config/quickshell/scripts/cava_color.py",
            "--palette",
            art
        ];

        Qt.callLater(function() {
            if (artworkPaletteProc.requestedArt === islandWindow.songArt)
                artworkPaletteProc.running = true;
        });
    }

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
        // 1s abierto, 10s cerrado
        interval: (islandWindow.isExpanded && currentTab === 1) ? 1000 : 10000
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
        command: [
            "bash", "-c",
            "tabOpen=\"" + watchdogProc.tabOpen + "\"; " +
            "LC_ALL=C; " +

            // 1. Red (Cero subprocesos, puramente bash)
            "F_RX=\"/tmp/qs_rx_bytes\"; [ ! -f \"$F_RX\" ] && echo 0 > \"$F_RX\"; " +
            "read prev_rx < \"$F_RX\" 2>/dev/null || prev_rx=0; curr_rx=0; " +
            "for f in /sys/class/net/w*/statistics/rx_bytes; do [ -f \"$f\" ] && { read v < \"$f\"; curr_rx=$((curr_rx+v)); }; done; " +
            "echo \"$curr_rx\" > \"$F_RX\"; " +
            "inter=$([ \"$tabOpen\" = \"1\" ] && echo 1 || echo 10); " +
            "if [ \"$curr_rx\" -lt \"$prev_rx\" ]; then dl=0; else dl=$(( (curr_rx - prev_rx) / inter / 1048576 )); fi; " +

            // 2. CPU Temp (Driver k10temp para Ryzen AI)
            // Lee el hardware directo, sin llamar al binario 'sensors', impacto literal de 0% CPU.
            "ct=0; for f in /sys/class/hwmon/hwmon*/name; do " +
            "  read name < \"$f\" 2>/dev/null; " +
            "  if [ \"$name\" = \"k10temp\" ] || [ \"$name\" = \"zenpower\" ]; then " +
            "    read t < \"${f%/*}/temp1_input\" 2>/dev/null; " +
            "    ct=$((t / 1000)); break; " +
            "  fi; " +
            "done; " +

            // 3. Lógica inteligente para preservar la batería
            "if [ \"$tabOpen\" = \"1\" ]; then " +
            "  cu=$(top -bn1 | awk '/Cpu\\(s\\)/ {print $2 + $4}'); " +
            // Se agrupa uso y temperatura de la RTX 5070 en una sola llamada, 
            // SOLAMENTE cuando la pestaña está abierta viéndola.
            "  gpu_info=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>/dev/null || echo \"0, 0\"); " +
            "  gu=$(echo \"$gpu_info\" | cut -d',' -f1); " +
            "  gt=$(echo \"$gpu_info\" | cut -d',' -f2 | tr -d ' '); " +
            "  ru=$(free -m | awk '/Mem:/ {printf \"%.1f\", $3/1024}'); " +
            "  st=$(df -BG / | awk 'NR==2 {gsub(\"G\",\"GB\",$4); gsub(\"G\",\"GB\",$2); print $4\"/\"$2}'); " +
            "else " +
            // MODO AHORRO BATERÍA: Si la isla está colapsada, no despertamos la dGPU y ahorramos los procesos de RAM/Disco
            "  cu=0; gu=0; gt=0; ru=0; st=\"0/0GB\"; " +
            "fi; " +

            "cam=$(fuser /dev/video* 2>/dev/null | wc -w); " +
            "echo \"${dl:-0};${ct:-0};${gt:-0};${cam:-0};${cu:-0};${gu:-0};${ru:-0};${st:-0/0GB}\""
        ]
        running: false
        stdout: SplitParser {
            onRead: function(data) {
                var p = data.trim().split(";");
                if (p.length >= 8) {
                    dlSpeed = parseFloat(p[0]) || 0;
                    globalCt = parseFloat(p[1]) || 0;
                    
                    // Solo actualizamos gt si nos han devuelto un valor útil (>0)
                    var readGt = parseFloat(p[2]) || 0;
                    if (readGt > 0) globalGt = readGt; 
                    
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

    // --- ACTUALIZAR EL PROCESO DE LECTURA ---
    Process {
        id: appUsageProc
        running: islandWindow.isExpanded && currentTab === 2
        // Ahora lee de ~/.cache para tener persistencia
        command: ["bash", "-c", "cat ~/.cache/qs_app_usage.json 2>/dev/null"]
        stdout: SplitParser {
            onRead: function(data) {
                try {
                    var parsed = JSON.parse(data.trim());
                    islandWindow.todayTotalTime = parsed.total;
                    islandWindow.avgDailyTime = parsed.avg_daily;
                    islandWindow.vsYesterdayTime = parsed.vs_yesterday;
                    islandWindow.weekChartData = parsed.chart;
                    if (parsed.chart_times) islandWindow.weekChartTimes = parsed.chart_times;
                    islandWindow.todayDayIndex = parsed.current_day_index;
                    
                    appUsageModel.clear();
                    for (var i = 0; i < parsed.apps.length; i++) {
                        appUsageModel.append(parsed.apps[i]);
                    }
                } catch(e) {}
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

    // --- VISUAL PILL ---
    GlassSurface {
        id: visualBg
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        
        width: targetWidth
        height: targetHeight

        glassRadius: isExpanded ? 28 : height / 2
        clip: true

        // GlassSurface dibuja por defecto un highlight horizontal de 1 px
        // en el borde superior. En una superficie tan grande y redondeada
        // como la Dynamic Island se percibe como una línea recta en las
        // tangencias superiores de las esquinas, así que lo desactivamos
        // únicamente aquí. El borde glass normal permanece intacto.
        showHighlight: false

        border.color: baseAlertColor !== "transparent" ? baseAlertColor : Glass.borderColor
        border.width: baseAlertColor !== "transparent" ? 2 : Glass.borderWidth
        
        SequentialAnimation on border.color {
            running: baseAlertColor !== "transparent" && !isExpanded && (isOverheating || isOverloaded)
            loops: Animation.Infinite
            ColorAnimation { to: altAlertColor; duration: 800 }
            ColorAnimation { to: baseAlertColor; duration: 800 }
        }

        Behavior on width  { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
        Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
        Behavior on glassRadius { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }

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

                if (wheel.angleDelta.x < -40) {
                    // Scroll circular hacia la derecha: 0 -> 1 -> 2 -> 0
                    currentTab = (currentTab + 1) % totalTabs;
                    wheelCooldown.restart();
                } else if (wheel.angleDelta.x > 40) {
                    // Scroll circular hacia la izquierda: 0 -> 2 -> 1 -> 0
                    currentTab = (currentTab - 1 + totalTabs) % totalTabs;
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

            // ---------------------------------------------------------
            // ARTWORK DE FONDO DEL RELOJ
            // ---------------------------------------------------------
            // Totalmente event-driven: depende únicamente de isPlaying/songArt.
            // No añade timers, polling ni procesos adicionales.
            Item {
                id: collapsedArtworkLayer
                anchors.fill: parent
                visible: islandWindow.isPlaying && islandWindow.songArt !== ""
                z: -1

                // Fuente pequeña: el reloj mide solo 32 px de alto, así que no
                // necesitamos decodificar una textura grande para esta vista.
                Image {
                    id: collapsedArtworkSource
                    anchors.fill: parent
                    source: islandWindow.isPlaying ? islandWindow.songArt : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    smooth: true
                    retainWhileLoading: true
                    sourceSize.width: Math.max(160, Math.ceil(collapsedArtworkLayer.width * 1.5))
                    sourceSize.height: 64
                    visible: false
                }

                // Recorte real de píldora. cached:false evita quedarse con una
                // portada antigua cuando MPRIS cambia de canción.
                OpacityMask {
                    anchors.fill: parent
                    source: collapsedArtworkSource
                    cached: false

                    maskSource: Rectangle {
                        width: collapsedArtworkLayer.width
                        height: collapsedArtworkLayer.height
                        radius: height / 2
                        color: "white"
                    }
                }

                // Oscurecimiento para que reloj e indicadores mantengan
                // contraste independientemente de la carátula.
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: "#000000"
                    opacity: 0.60
                }
            }

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
            id: expandedTabsViewport
            anchors.fill: parent
            visible: islandWindow.isExpanded && !visualBg.isAnimating
            opacity: visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 100 } }

            // Una única máscara FIJA para todo el carrusel.
            // Las pestañas se deslizan por debajo de esta silueta, así que
            // durante la transición nunca se ve su bounding-box rectangular.
            layer.enabled: visible
            layer.smooth: true
            layer.effect: OpacityMask {
                cached: false

                maskSource: Rectangle {
                    width: expandedTabsViewport.width
                    height: expandedTabsViewport.height
                    radius: visualBg.glassRadius
                    color: "white"
                }
            }

            // ================================
            // TAB 0: MUSIC PLAYER
            // ================================
            Item {
                width: parent.width
                height: parent.height
                x: islandWindow.circularTabOffset(0) * width
                opacity: currentTab === 0 ? 1 : 0
                Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.OutQuint } }
                Behavior on opacity { NumberAnimation { duration: 250 } }
                visible: opacity > 0

                // ========================================================
                // NOTHING PLAYING
                // Visualmente idéntico al MediaPlayerCard de la lockscreen.
                // ========================================================
                Item {
                    anchors.fill: parent
                    visible: !islandWindow.isPlayerAvailable

                    Row {
                        anchors.centerIn: parent
                        spacing: 10

                        Text {
                            text: "󰎆"
                            color: Qt.alpha(Theme.white, 0.45)
                            font.family: Theme.fontIcons
                            font.pixelSize: 18
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: "Nothing playing"
                            color: Qt.alpha(Theme.white, 0.55)
                            font.family: Theme.fontMain
                            font.pixelSize: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                // ========================================================
                // ACTIVE PLAYER
                // La carátula se usa como fondo de toda la pestaña,
                // inspirándose en el reproductor de One UI.
                // ========================================================
                Item {
                    anchors.fill: parent
                    visible: islandWindow.isPlayerAvailable

                    // ----------------------------------------------------
                    // FULL-BLEED ALBUM ART BACKGROUND
                    //
                    // El recorte redondeado lo realiza expandedTabsViewport
                    // de forma fija. La portada puede actualizarse directamente
                    // sin una máscara individual que se desplace con la pestaña.
                    // ----------------------------------------------------
                    Image {
                        id: islandBackgroundArtwork
                        anchors.fill: parent
                        source: islandWindow.songArt
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        smooth: true
                        mipmap: true
                        retainWhileLoading: true
                        sourceSize.width: islandWindow.expandedWidth
                        sourceSize.height: islandWindow.expandedWidth
                        opacity: 0.50
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: "#000000"
                        opacity: islandWindow.songArt !== "" ? 0.48 : 0.20
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: 82
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.30) }
                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.00) }
                        }
                    }

                    // ----------------------------------------------------
                    // PLAYER CONTENT
                    // ----------------------------------------------------
                    Item {
                        id: islandPlayerContent
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        anchors.topMargin: 14
                        anchors.bottomMargin: 14

                        Column {
                            id: islandMetadata
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.topMargin: 8
                            spacing: 3

                            Text {
                                width: parent.width
                                text: islandWindow.songTitle
                                color: Theme.white
                                font.family: Theme.fontMain
                                font.pixelSize: 17
                                font.bold: true
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                style: Text.Raised
                                styleColor: Qt.rgba(0, 0, 0, 0.35)
                            }

                            Text {
                                width: parent.width
                                text: islandWindow.songArtist
                                color: Qt.alpha(Theme.white, 0.74)
                                font.family: Theme.fontMain
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                style: Text.Raised
                                styleColor: Qt.rgba(0, 0, 0, 0.30)
                            }
                        }

                        // Shuffle + previous + play/pause + next + repeat.
                        // El bloque queda centrado respecto a la barra inferior.
                        RowLayout {
                            id: islandPlaybackControls
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: islandProgressRow.top
                            // Compensamos la subida de la barra para conservar
                            // prácticamente la misma posición de los controles.
                            anchors.bottomMargin: 12
                            height: 46
                            spacing: 14

                            Item { Layout.fillWidth: true }

                            Item {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 30
                                Layout.alignment: Qt.AlignVCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰒟"
                                    font.family: Theme.fontIcons
                                    font.pixelSize: 18
                                    color: islandWindow.isShuffle ? Theme.white : Qt.alpha(Theme.white, 0.48)
                                    style: Text.Raised
                                    styleColor: Qt.rgba(0, 0, 0, 0.30)
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (islandWindow.isPlayerAvailable)
                                            islandWindow.activePlayer.shuffle = !islandWindow.activePlayer.shuffle;
                                    }
                                }
                            }

                            Item {
                                Layout.preferredWidth: 38
                                Layout.preferredHeight: 38
                                Layout.alignment: Qt.AlignVCenter

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 36
                                    height: 36
                                    radius: width / 2
                                    color: Qt.rgba(0, 0, 0, 0.28)

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰒮"
                                        font.family: Theme.fontIcons
                                        font.pixelSize: 20
                                        color: Theme.white
                                        style: Text.Raised
                                        styleColor: Qt.rgba(0, 0, 0, 0.30)
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (islandWindow.isPlayerAvailable) islandWindow.activePlayer.previous()
                                }
                            }

                            Item {
                                Layout.preferredWidth: 46
                                Layout.preferredHeight: 46
                                Layout.alignment: Qt.AlignVCenter

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 44
                                    height: 44
                                    radius: width / 2
                                    color: Qt.rgba(0, 0, 0, 0.30)

                                    Text {
                                        anchors.centerIn: parent
                                        text: islandWindow.isPlaying ? "󰏤" : "󰐊"
                                        font.family: Theme.fontIcons
                                        font.pixelSize: 20
                                        color: Theme.white
                                        style: Text.Raised
                                        styleColor: Qt.rgba(0, 0, 0, 0.30)
                                    }
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

                            Item {
                                Layout.preferredWidth: 38
                                Layout.preferredHeight: 38
                                Layout.alignment: Qt.AlignVCenter

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 36
                                    height: 36
                                    radius: width / 2
                                    color: Qt.rgba(0, 0, 0, 0.28)

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰒭"
                                        font.family: Theme.fontIcons
                                        font.pixelSize: 20
                                        color: Theme.white
                                        style: Text.Raised
                                        styleColor: Qt.rgba(0, 0, 0, 0.30)
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (islandWindow.isPlayerAvailable) islandWindow.activePlayer.next()
                                }
                            }

                            Item {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 30
                                Layout.alignment: Qt.AlignVCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: islandWindow.liveLoopStatus === "Track" ? "󰑘" : "󰑖"
                                    font.family: Theme.fontIcons
                                    font.pixelSize: 18
                                    color: islandWindow.liveLoopStatus !== "None" ? Theme.white : Qt.alpha(Theme.white, 0.48)
                                    style: Text.Raised
                                    styleColor: Qt.rgba(0, 0, 0, 0.30)
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (!islandWindow.isPlayerAvailable) return;

                                        let current = islandWindow.liveLoopStatus;
                                        let next = "None";
                                        if (current === "None") next = "Playlist";
                                        else if (current === "Playlist") next = "Track";
                                        else next = "None";

                                        islandWindow.liveLoopStatus = next;
                                        islandWindow.activePlayer.loopStatus = next;
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }

                        // Barra de reproducción completa, ahora aprovechando todo
                        // el ancho disponible al desaparecer la carátula lateral.
                        RowLayout {
                            id: islandProgressRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 6
                            spacing: 6

                            Item {
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 34
                                Layout.alignment: Qt.AlignVCenter

                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.verticalCenterOffset: 1

                                    text: islandWindow.formatTime(islandWindow.trackPosition)
                                    color: Qt.alpha(Theme.white, 0.76)
                                    font.family: Theme.fontMain
                                    font.pixelSize: 10
                                    font.bold: true
                                    horizontalAlignment: Text.AlignRight
                                    style: Text.Raised
                                    styleColor: Qt.rgba(0, 0, 0, 0.30)
                                }
                            }

                            MouseArea {
                                id: progressArea
                                Layout.fillWidth: true
                                Layout.preferredHeight: 34
                                Layout.alignment: Qt.AlignVCenter
                                cursorShape: Qt.PointingHandCursor

                                // La onda es puramente visual: no analiza el audio.
                                // Solo se repinta mientras la pestaña musical está
                                // realmente abierta, así que cerrada no añade trabajo.
                                property real wavePhase: 0
                                property real visualProgress: islandWindow.trackLength > 0
                                    ? Math.max(0, Math.min(1, islandWindow.trackPosition / islandWindow.trackLength))
                                    : 0

                                // Geometría compartida para que el thumb y su glow nunca se recorten
                                // en los extremos de la barra.
                                property real progressThumbRadius: islandWindow.isUserSeeking ? 7.4 : 6.4
                                property real progressHaloRadius: islandWindow.isUserSeeking ? 11.5 : 9.5
                                property real progressGlowRadius: progressHaloRadius + 7.0
                                property real progressEdgePadding: progressGlowRadius + 1.5

                                Behavior on visualProgress {
                                    enabled: !islandWindow.isUserSeeking
                                    NumberAnimation { duration: 420; easing.type: Easing.Linear }
                                }

                                Timer {
                                    id: progressWaveTimer
                                    interval: 40 // 25 FPS: suficientemente suave para una onda tan pequeña.
                                    repeat: true
                                    running: islandWindow.isExpanded
                                             && islandWindow.currentTab === 0
                                             && islandWindow.isPlayerAvailable
                                             && islandWindow.isPlaying
                                    onTriggered: {
                                        progressArea.wavePhase += 0.085;
                                        // No hacemos wrap corto tipo 2π porque puede percibirse
                                        // como reinicio visual del patrón. Solo saneamos muy de vez en
                                        // cuando para evitar crecimiento infinito del número.
                                        if (progressArea.wavePhase > 1000000)
                                            progressArea.wavePhase = 0;
                                        progressWave.requestPaint();
                                    }
                                }

                                onVisualProgressChanged: progressWave.requestPaint()
                                onWidthChanged: progressWave.requestPaint()
                                onHeightChanged: progressWave.requestPaint()

                                Connections {
                                    target: islandWindow
                                    function onIsPlayingChanged() {
                                        progressWave.requestPaint();
                                    }
                                }

                                function seekToMouse() {
                                    if (!islandWindow.isPlayerAvailable || islandWindow.trackLength <= 0) return;

                                    var left = progressEdgePadding;
                                    var right = Math.max(left + 1, width - progressEdgePadding);
                                    var percent = (mouseX - left) / (right - left);
                                    percent = Math.max(0, Math.min(1, percent));

                                    var newPos = percent * islandWindow.trackLength;
                                    islandWindow.trackPosition = newPos;
                                    if (islandWindow.activePlayer) islandWindow.activePlayer.position = newPos;
                                }

                                onPressed: {
                                    islandWindow.isUserSeeking = true;
                                    seekToMouse();
                                }
                                onPositionChanged: {
                                    if (pressed) seekToMouse();
                                }
                                onReleased: {
                                    if (islandWindow.activePlayer)
                                        islandWindow.activePlayer.position = islandWindow.trackPosition;
                                    islandWindow.isUserSeeking = false;
                                }
                                onCanceled: islandWindow.isUserSeeking = false

                                Canvas {
                                    id: progressWave
                                    anchors.fill: parent

                                    onPaint: {
                                        var ctx = getContext("2d");
                                        ctx.reset();

                                        var w = width;
                                        var h = height;
                                        if (w <= 0 || h <= 0) return;

                                        var p = Math.max(0, Math.min(1, progressArea.visualProgress));
                                        var phase = progressArea.wavePhase;

                                        // Geometría base de la barra.
                                        // Usamos una pista interior para que el thumb nunca se recorte
                                        // en 0% ni en 100%, y para que los extremos sigan siendo redondeados.
                                        // El eje vertical de la barra se calcula a partir del glow,
                                        // para que el brillo del thumb nunca se recorte por abajo.
                                        var baseY = Math.max(
                                            progressArea.progressGlowRadius + 0.5,
                                            h - progressArea.progressGlowRadius - 1.0
                                        );
                                        var lineWidth = 4.0;
                                        var thumbRadius = progressArea.progressThumbRadius;
                                        var haloRadius = progressArea.progressHaloRadius;
                                        var trackInset = progressArea.progressEdgePadding;
                                        var trackStart = trackInset;
                                        var trackEnd = Math.max(trackStart, w - trackInset);
                                        var trackWidth = Math.max(1, trackEnd - trackStart);
                                        var thumbX = trackStart + p * trackWidth;
                                        var playedWidth = Math.max(0, thumbX - trackStart);

                                        // -----------------------------------------
                                        // 1. ONDAS SOBRE LA ZONA YA REPRODUCIDA
                                        // -----------------------------------------
                                        if (islandWindow.isPlaying && playedWidth > 2) {
                                            ctx.save();

                                            // Las ondas deben quedarse dentro del tramo reproducido,
                                            // pero sin ese corte feo en los extremos. La solución es
                                            // hacer fade a cero dentro del propio rango [trackStart, thumbX].
                                            var waveStart = trackStart;
                                            var waveEnd = thumbX;
                                            var edgeFadePx = 18;

                                            function drawWave(amplitude, periodPx, speedPx, alpha, verticalBias, waveColor) {
                                                ctx.beginPath();
                                                ctx.moveTo(waveStart, baseY);

                                                var step = 3;
                                                var omega = (Math.PI * 2) / Math.max(1, periodPx);
                                                var travel = phase * speedPx;

                                                for (var x = waveStart; x <= waveEnd; x += step) {
                                                    var localX = x - trackStart;

                                                    // Fade interno suave en ambos bordes.
                                                    var fadeIn = Math.min(
                                                        1,
                                                        Math.max(0, (x - waveStart) / edgeFadePx)
                                                    );
                                                    var fadeOut = Math.min(
                                                        1,
                                                        Math.max(0, (waveEnd - x) / edgeFadePx)
                                                    );
                                                    var envelope = fadeIn * fadeOut;

                                                    var s1 = 0.5 + 0.5 * Math.sin((localX - travel) * omega);
                                                    var s2 = 0.5 + 0.5 * Math.sin((localX - travel * 0.62) * omega * 0.58 + 1.15);
                                                    var shape = (s1 * 0.72 + s2 * 0.28);

                                                    var y = baseY - verticalBias - shape * amplitude * envelope;

                                                    if (x === waveStart)
                                                        ctx.moveTo(x, baseY);
                                                    ctx.lineTo(x, y);
                                                }

                                                ctx.lineTo(waveEnd, baseY);
                                                ctx.closePath();
                                                ctx.fillStyle = Qt.alpha(waveColor, alpha);
                                                ctx.fill();
                                            }

                                            drawWave(12.0, 120, 30, 0.34, 0.0, islandWindow.artworkPalettePrimary);
                                            drawWave(9.0, 92, -22, 0.40, 0.25, islandWindow.artworkPaletteSecondary);
                                            drawWave(6.8, 68, 16, 0.46, 0.45, islandWindow.artworkPaletteAccent);

                                            // Cresta superior: mismo fade interno, sin salirse
                                            // del tramo reproducido.
                                            ctx.beginPath();
                                            var crestStep = 3;
                                            var crestOmega = (Math.PI * 2) / 90;
                                            for (var cx = waveStart; cx <= waveEnd; cx += crestStep) {
                                                var localCX = cx - trackStart;

                                                var cFadeIn = Math.min(
                                                    1,
                                                    Math.max(0, (cx - waveStart) / edgeFadePx)
                                                );
                                                var cFadeOut = Math.min(
                                                    1,
                                                    Math.max(0, (waveEnd - cx) / edgeFadePx)
                                                );
                                                var cEnv = cFadeIn * cFadeOut;

                                                var c1 = 0.5 + 0.5 * Math.sin((localCX - phase * 22) * crestOmega);
                                                var c2 = 0.5 + 0.5 * Math.sin((localCX - phase * 14) * crestOmega * 0.54 + 0.9);
                                                var cShape = c1 * 0.72 + c2 * 0.28;
                                                var cy = baseY - 0.35 - cShape * 8.0 * cEnv;

                                                if (cx === waveStart)
                                                    ctx.moveTo(cx, baseY);
                                                else
                                                    ctx.lineTo(cx, cy);
                                            }
                                            ctx.lineTo(waveEnd, baseY);
                                            ctx.lineWidth = 1.1;
                                            ctx.lineJoin = "round";
                                            ctx.lineCap = "round";
                                            ctx.strokeStyle = Qt.alpha(islandWindow.artworkPaletteAccent, 0.76);
                                            ctx.stroke();

                                            ctx.restore();
                                        }

                                        // -----------------------------------------
                                        // 2. BARRA RECTA COMPLETA CON EXTREMOS REDONDOS
                                        // -----------------------------------------
                                        ctx.beginPath();
                                        ctx.moveTo(trackStart, baseY);
                                        ctx.lineTo(trackEnd, baseY);
                                        ctx.lineWidth = lineWidth;
                                        ctx.lineCap = "round";
                                        ctx.strokeStyle = Qt.alpha(Theme.white, 0.28);
                                        ctx.stroke();

                                        if (playedWidth > 0) {
                                            ctx.beginPath();
                                            ctx.moveTo(trackStart, baseY);
                                            ctx.lineTo(thumbX, baseY);
                                            ctx.lineWidth = lineWidth;
                                            ctx.lineCap = "round";
                                            ctx.strokeStyle = Qt.alpha(Theme.white, 0.96);
                                            ctx.stroke();
                                        }

                                        // -----------------------------------------
                                        // 3. THUMB TIPO ONE UI
                                        // -----------------------------------------
                                        // Glow suave tipo One UI alrededor del thumb.
                                        // Se apoya en el color principal extraído de la portada.
                                        var glowRadius = haloRadius + 7.0;

                                        var outerGlow = ctx.createRadialGradient(
                                            thumbX, baseY, thumbRadius * 0.20,
                                            thumbX, baseY, glowRadius
                                        );
                                        outerGlow.addColorStop(0.0, Qt.alpha(islandWindow.artworkPalettePrimary, 0.58));
                                        outerGlow.addColorStop(0.38, Qt.alpha(islandWindow.artworkPalettePrimary, 0.32));
                                        outerGlow.addColorStop(0.74, Qt.alpha(islandWindow.artworkPalettePrimary, 0.14));
                                        outerGlow.addColorStop(1.0, Qt.rgba(0, 0, 0, 0.0));

                                        ctx.beginPath();
                                        ctx.arc(thumbX, baseY, glowRadius, 0, Math.PI * 2);
                                        ctx.fillStyle = outerGlow;
                                        ctx.fill();

                                        // Halo blanco interior sutil para conservar el look brillante
                                        // de One UI sin perder el color dinámico de la portada.
                                        var innerHalo = ctx.createRadialGradient(
                                            thumbX, baseY, 1,
                                            thumbX, baseY, haloRadius
                                        );
                                        innerHalo.addColorStop(0.0, Qt.rgba(1, 1, 1, 0.34));
                                        innerHalo.addColorStop(0.52, Qt.rgba(1, 1, 1, 0.18));
                                        innerHalo.addColorStop(1.0, Qt.rgba(1, 1, 1, 0.0));

                                        ctx.beginPath();
                                        ctx.arc(thumbX, baseY, haloRadius, 0, Math.PI * 2);
                                        ctx.fillStyle = innerHalo;
                                        ctx.fill();

                                        // Interior coloreado según la carátula.
                                        // El aro blanco se conserva para mantener contraste.
                                        ctx.beginPath();
                                        ctx.arc(thumbX, baseY, thumbRadius, 0, Math.PI * 2);
                                        ctx.fillStyle = Qt.alpha(islandWindow.artworkPalettePrimary, 0.98);
                                        ctx.fill();

                                        // Pequeño brillo central para que el relleno no se vea plano.
                                        ctx.beginPath();
                                        ctx.arc(thumbX, baseY, Math.max(1.6, thumbRadius - 2.2), 0, Math.PI * 2);
                                        ctx.fillStyle = Qt.alpha(Theme.white, 0.24);
                                        ctx.fill();

                                        // Aro blanco externo.
                                        ctx.beginPath();
                                        ctx.arc(thumbX, baseY, thumbRadius, 0, Math.PI * 2);
                                        ctx.lineWidth = 2.4;
                                        ctx.strokeStyle = Qt.alpha(Theme.white, 0.99);
                                        ctx.stroke();
                                    }
                                }
                            }

                            Item {
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 34
                                Layout.alignment: Qt.AlignVCenter

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: islandWindow.formatTime(islandWindow.trackLength)
                                    color: Qt.alpha(Theme.white, 0.76)
                                    font.family: Theme.fontMain
                                    font.pixelSize: 10
                                    font.bold: true
                                    horizontalAlignment: Text.AlignLeft
                                    style: Text.Raised
                                    styleColor: Qt.rgba(0, 0, 0, 0.30)
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
                x: islandWindow.circularTabOffset(1) * width
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
            // TAB 2: APP USAGE MONITOR (Side-by-Side Layout)
            // ================================
            Item {
                width: parent.width
                height: parent.height
                x: islandWindow.circularTabOffset(2) * width
                opacity: currentTab === 2 ? 1 : 0
                Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.OutQuint } }
                Behavior on opacity { NumberAnimation { duration: 250 } }
                visible: opacity > 0

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.topMargin: 10
                    anchors.bottomMargin: 10
                    spacing: 6

                    // --- 1. CABECERA RESUMEN ---
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        color: Qt.alpha(Theme.white, 0.03)
                        radius: 8
                        border.color: Qt.alpha(Theme.white, 0.05)
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 12

                            RowLayout {
                                spacing: 4
                                Text { text: "Today"; color: Qt.alpha(Theme.white, 0.5); font.family: Theme.fontMain; font.pixelSize: 10 }
                                Text { text: todayTotalTime; color: Theme.white; font.family: Theme.fontMain; font.pixelSize: 13; font.bold: true }
                            }
                            Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; Layout.topMargin: 6; Layout.bottomMargin: 6; color: Qt.alpha(Theme.white, 0.08) }
                            RowLayout {
                                spacing: 4
                                Text { text: "Avg."; color: Qt.alpha(Theme.white, 0.5); font.family: Theme.fontMain; font.pixelSize: 10 }
                                Text { text: avgDailyTime; color: Qt.alpha(Theme.white, 0.8); font.family: Theme.fontMain; font.pixelSize: 11; font.bold: true }
                            }
                            Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; Layout.topMargin: 6; Layout.bottomMargin: 6; color: Qt.alpha(Theme.white, 0.08) }
                            RowLayout {
                                spacing: 4
                                Text { 
                                    text: vsYesterdayTime; 
                                    color: Theme.white; // Cambiado a blanco
                                    font.family: Theme.fontMain; 
                                    font.pixelSize: 11; 
                                    font.bold: true 
                                }
                                Text { 
                                    text: "vs yesterday"; 
                                    color: Qt.alpha(Theme.white, 0.5); 
                                    font.family: Theme.fontMain; 
                                    font.pixelSize: 10 
                                }
                            }
                        }
                    }

                    // --- 2. CUERPO PRINCIPAL (Dos Columnas) ---
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 8

                        // COLUMNA IZQUIERDA: APPS (60%)
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: 200
                            spacing: 4

                            Text {
                                text: "Most Used Applications"
                                color: Qt.alpha(Theme.white, 0.7)
                                font.family: Theme.fontMain
                                font.pixelSize: 10
                                font.bold: true
                                Layout.leftMargin: 2
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                color: Qt.alpha(Theme.white, 0.02)
                                radius: 10
                                border.color: Qt.alpha(Theme.white, 0.04)
                                border.width: 1
                                clip: true

                                ListView {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    model: appUsageModel
                                    spacing: 5
                                    clip: true

                                    delegate: Item {
                                        width: ListView.view.width
                                        height: 22

                                        RowLayout {
                                            anchors.fill: parent
                                            spacing: 8

                                            Image {
                                                Layout.preferredWidth: 16; Layout.preferredHeight: 16
                                                source: "image://icon/" + model.icon
                                                fillMode: Image.PreserveAspectFit
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    Text { text: model.name; color: Theme.white; font.family: Theme.fontMain; font.pixelSize: 11; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                                                    Text { text: model.time; color: Qt.alpha(Theme.white, 0.7); font.family: Theme.fontMain; font.pixelSize: 10; font.bold: true }
                                                }
                                                Rectangle {
                                                    Layout.fillWidth: true;
                                                    height: 4; radius: 2; color: Qt.alpha(Theme.white, 0.05)
                                                    Rectangle {
                                                        height: parent.height; radius: 2;
                                                        color: Theme.white // Cambiado a blanco
                                                        width: parent.width * model.percent
                                                        Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // COLUMNA DERECHA: GRÁFICA (40%)
                        ColumnLayout {
                            Layout.fillHeight: true
                            Layout.preferredWidth: 120
                            spacing: 4

                            Text {
                                text: "Weekly Usage"
                                color: Qt.alpha(Theme.white, 0.7)
                                font.family: Theme.fontMain
                                font.pixelSize: 10
                                font.bold: true
                                Layout.leftMargin: 2
                            }

                            Rectangle {
                                id: chartBg
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                color: Qt.alpha(Theme.white, 0.02)
                                radius: 10
                                border.color: Qt.alpha(Theme.white, 0.04)
                                border.width: 1

                                // Generamos dinámicamente los últimos 7 días (número del mes)
                                property var dayLabels: {
                                    var arr = [];
                                    var today = new Date();
                                    // Bucle inverso: de hace 6 días a hoy (0)
                                    for (var i = 6; i >= 0; i--) {
                                        var d = new Date(today.getTime() - i * 24 * 60 * 60 * 1000);
                                        arr.push(d.getDate().toString());
                                    }
                                    return arr;
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 4

                                    Repeater {
                                        model: weekChartData 
                                        
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            spacing: 4

                                            // 1. ÁREA DE LA BARRA
                                            Item {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true

                                                // Barra de fondo oscuro
                                                Rectangle {
                                                    anchors.top: parent.top
                                                    anchors.bottom: parent.bottom
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    width: 12
                                                    radius: 4
                                                    color: Qt.alpha(Theme.white, 0.04)
                                                }
                                                
                                                // Barra animada
                                                Rectangle {
                                                    anchors.bottom: parent.bottom
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    width: 12 
                                                    radius: 4
                                                    height: parent.height * modelData
                                                    // El día actual ahora siempre es el último (índice 6)
                                                    color: index === 6 ? Theme.white : Qt.alpha(Theme.white, 0.3)
                                                    
                                                    Behavior on height { NumberAnimation { duration: 700; easing.type: Easing.OutBounce } }
                                                }
                                            }

                                            // 2. NÚMERO DEL DÍA
                                            Text {
                                                Layout.fillWidth: true
                                                text: chartBg.dayLabels[index] // Muestra el número calculado
                                                color: index === 6 ? Theme.white : Qt.alpha(Theme.white, 0.4)
                                                font.family: Theme.fontMain
                                                font.pixelSize: 9
                                                font.bold: index === 6 // Negrita solo para el último (hoy)
                                                horizontalAlignment: Text.AlignHCenter
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

        }
    }
}