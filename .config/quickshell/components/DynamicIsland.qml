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

    // Configurable from shell.qml so the island can use a different
    // vertical position on the external monitor in clamshell mode.
    property int topMargin: -38

    anchors {
        top: true
    }
    margins {
        top: islandWindow.topMargin
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

    // =========================================================
    // SCREEN RECORDING LIVE ACTIVITY
    // =========================================================
    // State changes arrive through a FIFO. There is no status polling loop:
    // the only 1 s Timer below exists while a recording is actually running,
    // solely to render the elapsed time.
    property string recordingStatus: "idle"   // idle | starting | running | paused | finalizing
    property int recordingElapsed: 0
    property string recordingOutput: ""
    property string recordingAudio: "none"
    property string recordingCapture: "screen"
    // If a backend event arrives while the status Process is still reading the
    // previous one, remember it instead of dropping it. This is especially
    // important when finalization is very fast: "finalizing" and "finished"
    // can be emitted almost back-to-back.
    property bool recordingRefreshPending: false
    // While recording, hovering the clock area should open the island, but the
    // control buttons themselves should stay clickable without expanding it.
    // We therefore arm expansion only when the dedicated clock hotspot is
    // hovered, and keep it open until the pointer leaves the island.
    property bool recordingHoverExpandArmed: false
    readonly property bool recordingActivityActive:
        recordingStatus === "starting"
        || recordingStatus === "running"
        || recordingStatus === "paused"
        || recordingStatus === "finalizing"

    onRecordingStatusChanged: {
        if (!recordingActivityActive)
            recordingHoverExpandArmed = false
    }

    function formatRecordingTime(seconds) {
        var value = Math.max(0, Math.floor(seconds || 0));
        var hours = Math.floor(value / 3600);
        var minutes = Math.floor((value % 3600) / 60);
        var secs = value % 60;
        var mm = (minutes < 10 ? "0" : "") + minutes;
        var ss = (secs < 10 ? "0" : "") + secs;
        return hours > 0 ? hours + ":" + mm + ":" + ss : mm + ":" + ss;
    }

    Process {
        id: recordingEventProc
        running: true
        command: [
            "bash", "-c",
            "F=\"${XDG_RUNTIME_DIR:-/tmp}/qs-screenrec-events\"; " +
            "rm -f \"$F\"; mkfifo \"$F\"; " +
            "printf 'refresh\\n'; " +
            "trap 'rm -f \"$F\"' EXIT; " +
            "while IFS= read -r line < \"$F\"; do printf '%s\\n' \"${line:-refresh}\"; done"
        ]
        stdout: SplitParser {
            onRead: function(line) {
                if (line.trim() !== "")
                    islandWindow.refreshRecordingState();
            }
        }
    }

    Process {
        id: recordingStatusProc
        property string output: ""
        stdout: SplitParser {
            onRead: function(line) {
                if (line && line.trim() !== "")
                    recordingStatusProc.output += line;
            }
        }
        onExited: function(exitCode) {
            if (exitCode === 0 && recordingStatusProc.output !== "") {
                try {
                    var data = JSON.parse(recordingStatusProc.output);
                    islandWindow.recordingStatus = data.status || "idle";
                    islandWindow.recordingElapsed = data.elapsed || 0;
                    islandWindow.recordingOutput = data.output || "";
                    islandWindow.recordingAudio = data.audio || "none";
                    islandWindow.recordingCapture = data.capture || "screen";

                    if (islandWindow.recordingStatus === "finished") {
                        islandWindow.recordingStatus = "idle";
                        islandWindow.triggerTextNotification("󰻃", "Recording saved", "#ff453a");
                        recordingClearProc.command = [
                            "/home/javier/.config/quickshell/scripts/screen_record.sh", "clear"
                        ];
                        recordingClearProc.running = true;
                    }
                } catch (e) {
                    console.warn("DynamicIsland: recording state parse error:", e);
                }
            }

            // Coalesce events instead of losing them. A finished event can arrive
            // while this Process is still handling the preceding finalizing event.
            if (islandWindow.recordingRefreshPending) {
                islandWindow.recordingRefreshPending = false;
                Qt.callLater(islandWindow.refreshRecordingState);
            }
        }
    }

    Process { id: recordingActionProc }
    Process { id: recordingClearProc }

    function refreshRecordingState() {
        if (recordingStatusProc.running) {
            recordingRefreshPending = true;
            return;
        }
        recordingRefreshPending = false;
        recordingStatusProc.output = "";
        recordingStatusProc.command = [
            "/home/javier/.config/quickshell/scripts/screen_record.sh", "status"
        ];
        recordingStatusProc.running = true;
    }

    function toggleRecordingPause() {
        if (recordingStatus !== "running" && recordingStatus !== "paused")
            return;
        recordingActionProc.running = false;
        recordingActionProc.command = [
            "/home/javier/.config/quickshell/scripts/screen_record.sh",
            recordingStatus === "running" ? "pause" : "resume"
        ];
        recordingActionProc.running = true;
    }

    function stopRecording() {
        if (recordingStatus !== "running" && recordingStatus !== "paused")
            return;
        // Stop/finalize can take a moment when several paused segments need
        // concatenating, so detach it and let FIFO events drive the UI.
        recordingActionProc.running = false;
        recordingActionProc.command = [
            "/home/javier/.config/quickshell/scripts/screen_record.sh", "stop"
        ];
        recordingActionProc.startDetached();
    }

    Timer {
        id: recordingElapsedTimer
        interval: 1000
        repeat: true
        running: islandWindow.recordingStatus === "running"
        onTriggered: islandWindow.recordingElapsed += 1
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

    // Stats is strictly on-demand. The Process below only exists while the
    // island is expanded AND tab 1 is visible. Clear transient network data
    // immediately when leaving it so the collapsed island never keeps a stale
    // download indicator alive.
    onIsExpandedChanged: {
        if (!isExpanded)
            dlSpeed = 0
    }

    onCurrentTabChanged: {
        if (currentTab !== 1)
            dlSpeed = 0
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
        if (recordingActivityActive) {
            if (recordingStatus === "running" || recordingStatus === "paused") return 238;
            return 190;
        }
        // La reproducción musical ya no necesita ensanchar la isla:
        // la mini-onda vive dentro del ancho normal del reloj.
        // Solo reservamos espacio extra para indicadores que realmente
        // ocupan los laterales del estado colapsado.
        var leftSideWidth = (dlSpeed >= 5 ? 18 : 0);
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
            // Comprobación híbrida: reaccionamos inmediatamente a eventos udev,
            // pero como algunos drivers no emiten un evento al cambiar solo el
            // porcentaje, despertamos este MISMO bash cada 30 s como respaldo.
            // `read -t` es un builtin de bash: no crea procesos periódicos extra.
            "}; check_bat; while true; do read -r -t 30 _ <&3 || true; check_bat; done"
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

    // 4. CÁMARA: detector por eventos, separado por completo de Stats.
    // inotifywait duerme bloqueado hasta que un nodo /dev/video* se abre/cierra;
    // solo entonces ejecutamos fuser una vez para conocer el estado real.
    Process {
        id: cameraUsageProc
        command: [
            "bash", "-c",
            "shopt -s nullglob; devs=(/dev/video*); " +
            "if [ ${#devs[@]} -eq 0 ]; then exit 0; fi; " +
            "echo STATE; " +
            "inotifywait -m -q -e open -e close_nowrite -e close_write --format STATE \"${devs[@]}\" 2>/dev/null"
        ]
        running: true
        stdout: SplitParser {
            onRead: function(data) {
                if (data.trim() !== "STATE") return;
                cameraStateProbe.running = true;
            }
        }
    }

    Process {
        id: cameraStateProbe
        command: ["bash", "-c", "fuser /dev/video* >/dev/null 2>&1 && echo 1 || echo 0"]
        running: false
        stdout: SplitParser {
            onRead: function(data) {
                globalCamActive = data.trim() === "1";
            }
        }
    }

    // 5. STATS DEL SISTEMA — ESTRICTAMENTE ON-DEMAND
    // ------------------------------------------------
    // Un único bash permanece vivo SOLO mientras esta pestaña es visible.
    // Lee CPU/RAM/red/temperatura directamente desde /proc y /sys. La RTX se
    // consulta con nvidia-smi cada 2 s y el disco cada 5 s. Al cambiar de pestaña
    // o cerrar la isla Quickshell detiene el proceso: 0 polling de Stats fuera.
    property real dlSpeed: 0
    property real globalCt: 0
    property real globalGt: 0
    property bool globalCamActive: false
    property bool globalMicActive: false
    property real globalCu: 0
    property real globalGu: 0

    property real sysRamUsage: 0
    property real sysRamTotal: 32
    property real sysRamPercent: 0
    property real sysStorageFree: 0
    property real sysStorageTotal: 0
    property real sysStoragePercent: 0
    property string sysStorage: "0/0GB"
    property real sysLoad1: 0
    property string sysUptime: "0m"

    // Alias para la UI del Tab 1
    property real sysGpuTemp: globalGt
    property real sysGpuUsage: globalGu
    property real sysCpuTemp: globalCt
    property real sysCpuUsage: globalCu

    function formatUptime(seconds) {
        var s = Math.max(0, Math.floor(seconds || 0));
        var days = Math.floor(s / 86400);
        var hours = Math.floor((s % 86400) / 3600);
        var mins = Math.floor((s % 3600) / 60);
        if (days > 0) return days + "d " + hours + "h";
        if (hours > 0) return hours + "h " + mins + "m";
        return mins + "m";
    }

    Process {
        id: statsProc
        running: islandWindow.isExpanded && currentTab === 1
        command: [
            "bash", "-c",
            "LC_ALL=C; " +
            "prev_total=0; prev_idle=0; prev_rx=0; tick=0; gu=0; gt=0; st_free=0; st_total=0; " +
            "while true; do " +
            "  tick=$((tick+1)); " +
            // CPU usage from /proc/stat, no top/awk.
            "  read _ user nice system idle iowait irq softirq steal _ < /proc/stat; " +
            "  total=$((user+nice+system+idle+iowait+irq+softirq+steal)); idle_all=$((idle+iowait)); " +
            "  if [ $prev_total -gt 0 ]; then dt=$((total-prev_total)); di=$((idle_all-prev_idle)); [ $dt -gt 0 ] && cu=$((100*(dt-di)/dt)) || cu=0; else cu=0; fi; " +
            "  prev_total=$total; prev_idle=$idle_all; " +
            // CPU temperature directly from hwmon.
            "  ct=0; for f in /sys/class/hwmon/hwmon*/name; do read name < \"$f\" 2>/dev/null || continue; if [ \"$name\" = \"k10temp\" ] || [ \"$name\" = \"zenpower\" ]; then read t < \"${f%/*}/temp1_input\" 2>/dev/null || t=0; ct=$((t/1000)); break; fi; done; " +
            // RAM directly from /proc/meminfo. MemAvailable is a better measure than free RAM.
            "  mt=0; ma=0; while read key val _; do case \"$key\" in MemTotal:) mt=$val ;; MemAvailable:) ma=$val; break ;; esac; done < /proc/meminfo; " +
            "  mu=$((mt-ma)); if [ $mt -gt 0 ]; then rp=$((100*mu/mt)); else rp=0; fi; " +
            // Aggregate received bytes for non-loopback interfaces.
            "  rx=0; for f in /sys/class/net/*/statistics/rx_bytes; do case \"$f\" in */lo/*) continue ;; esac; read v < \"$f\" 2>/dev/null || v=0; rx=$((rx+v)); done; " +
            "  if [ $prev_rx -gt 0 ] && [ $rx -ge $prev_rx ]; then dl=$((rx-prev_rx)); else dl=0; fi; prev_rx=$rx; " +
            // System load and uptime from procfs.
            "  read load1 _ < /proc/loadavg; read up _ < /proc/uptime; up=${up%%.*}; " +
            // dGPU: one nvidia-smi every 2 seconds, and only while this Process exists.
            "  if [ $((tick%2)) -eq 1 ]; then gpu_info=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>/dev/null); if [ -n \"$gpu_info\" ]; then IFS=',' read -r gu gt <<< \"$gpu_info\"; gu=${gu// /}; gt=${gt// /}; else gu=0; gt=0; fi; fi; " +
            // Storage changes slowly; refresh every 5 seconds instead of every frame.
            "  if [ $tick -eq 1 ] || [ $((tick%5)) -eq 0 ]; then while read a b; do [ \"$a\" = \"Size\" ] && continue; st_total=${a%G}; st_free=${b%G}; done < <(df -BG --output=size,avail / 2>/dev/null); st_total=${st_total:-0}; st_free=${st_free:-0}; fi; " +
            "  echo \"${cu:-0};${ct:-0};${gu:-0};${gt:-0};${mu:-0};${mt:-1};${rp:-0};${dl:-0};${st_free:-0};${st_total:-0};${load1:-0};${up:-0}\"; " +
            "  sleep 1; " +
            "done"
        ]
        stdout: SplitParser {
            onRead: function(data) {
                var p = data.trim().split(";");
                if (p.length < 12) return;

                globalCu = parseFloat(p[0]) || 0;
                globalCt = parseFloat(p[1]) || 0;
                globalGu = parseFloat(p[2]) || 0;
                globalGt = parseFloat(p[3]) || 0;

                var usedKb = parseFloat(p[4]) || 0;
                var totalKb = parseFloat(p[5]) || 1;
                sysRamUsage = usedKb / 1048576.0;
                sysRamTotal = totalKb / 1048576.0;
                sysRamPercent = parseFloat(p[6]) || 0;

                // p[7] llega en bytes por intervalo (~1 s). Convertimos aquí
                // a MiB/s con punto flotante para no perder velocidades < 1 MB/s.
                dlSpeed = (parseFloat(p[7]) || 0) / 1048576.0;
                sysStorageFree = parseFloat(p[8]) || 0;
                sysStorageTotal = parseFloat(p[9]) || 0;
                sysStoragePercent = sysStorageTotal > 0
                    ? Math.max(0, Math.min(100, 100 * (sysStorageTotal - sysStorageFree) / sysStorageTotal))
                    : 0;
                sysStorage = Math.round(Math.max(0, sysStorageTotal - sysStorageFree))
                    + "GB/" + Math.round(sysStorageTotal) + "GB";
                sysLoad1 = parseFloat(p[10]) || 0;
                sysUptime = formatUptime(parseFloat(p[11]) || 0);
            }
        }
    }

    // 5B. WATCHDOG DE ALERTAS — MUY BAJO CONSUMO
    // ------------------------------------------------
    // El dashboard detallado sigue siendo 100% on-demand. Este proceso existe
    // únicamente cuando Stats NO está abierta y sirve solo para mantener vivas
    // las alertas del borde.
    //
    // Coste:
    //  - un único bash dormido casi todo el tiempo;
    //  - cada 15 s lee /proc y /sys (sin top/free/sensors);
    //  - nvidia-smi SOLO se ejecuta si la dGPU NVIDIA ya está runtime-active,
    //    evitando despertarla solo para comprobar una alerta.
    //
    // Al abrir Stats se detiene automáticamente y statsProc pasa a proporcionar
    // las medidas detalladas cada segundo.
    Process {
        id: alertWatchdogProc
        running: !(islandWindow.isExpanded && currentTab === 1)
        command: [
            "bash", "-c",
            "LC_ALL=C; " +
            "prev_total=0; prev_idle=0; " +
            // Localiza una GPU NVIDIA PCI una sola vez.
            "nvidia_dev=''; " +
            "for d in /sys/bus/pci/devices/*; do " +
            "  [ -r \"$d/vendor\" ] || continue; read v < \"$d/vendor\"; " +
            "  [ \"$v\" = \"0x10de\" ] || continue; " +
            "  [ -r \"$d/class\" ] || continue; read c < \"$d/class\"; " +
            "  case \"$c\" in 0x030000|0x030200) nvidia_dev=\"$d\"; break ;; esac; " +
            "done; " +
            "while true; do " +
            // CPU usage: diferencia entre dos muestras del contador del kernel.
            "  read _ user nice system idle iowait irq softirq steal _ < /proc/stat; " +
            "  total=$((user+nice+system+idle+iowait+irq+softirq+steal)); idle_all=$((idle+iowait)); " +
            "  if [ $prev_total -gt 0 ]; then dt=$((total-prev_total)); di=$((idle_all-prev_idle)); [ $dt -gt 0 ] && cu=$((100*(dt-di)/dt)) || cu=0; else cu=0; fi; " +
            "  prev_total=$total; prev_idle=$idle_all; " +
            // Temperatura CPU directamente desde hwmon.
            "  ct=0; for f in /sys/class/hwmon/hwmon*/name; do " +
            "    read name < \"$f\" 2>/dev/null || continue; " +
            "    if [ \"$name\" = \"k10temp\" ] || [ \"$name\" = \"zenpower\" ]; then " +
            "      read t < \"${f%/*}/temp1_input\" 2>/dev/null || t=0; ct=$((t/1000)); break; " +
            "    fi; " +
            "  done; " +
            // RAM: solo porcentaje, desde /proc/meminfo.
            "  mt=0; ma=0; while read key val _; do case \"$key\" in MemTotal:) mt=$val ;; MemAvailable:) ma=$val; break ;; esac; done < /proc/meminfo; " +
            "  if [ $mt -gt 0 ]; then rp=$((100*(mt-ma)/mt)); else rp=0; fi; " +
            // GPU: NO despertamos la NVIDIA. Solo preguntamos si ya está activa.
            "  gu=0; gt=0; gpu_active=0; " +
            "  if [ -n \"$nvidia_dev\" ]; then " +
            "    if [ -r \"$nvidia_dev/power/runtime_status\" ]; then read rs < \"$nvidia_dev/power/runtime_status\"; [ \"$rs\" = \"active\" ] && gpu_active=1; " +
            "    else gpu_active=1; fi; " +
            "  fi; " +
            "  if [ $gpu_active -eq 1 ]; then " +
            "    gpu_info=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>/dev/null); " +
            "    if [ -n \"$gpu_info\" ]; then IFS=',' read -r gu gt <<< \"$gpu_info\"; gu=${gu// /}; gt=${gt// /}; fi; " +
            "  fi; " +
            "  echo \"${cu:-0};${ct:-0};${gu:-0};${gt:-0};${rp:-0};${gpu_active:-0}\"; " +
            "  sleep 15; " +
            "done"
        ]
        stdout: SplitParser {
            onRead: function(data) {
                // Si Stats se ha abierto mientras llegaba una última línea del
                // watchdog, dejamos que statsProc sea la única fuente de datos.
                if (islandWindow.isExpanded && currentTab === 1)
                    return;

                var p = data.trim().split(";");
                if (p.length < 6)
                    return;

                globalCu = parseFloat(p[0]) || 0;
                globalCt = parseFloat(p[1]) || 0;

                var gpuWasActive = p[5] === "1";
                if (gpuWasActive) {
                    globalGu = parseFloat(p[2]) || 0;
                    globalGt = parseFloat(p[3]) || 0;
                } else {
                    // Una dGPU suspendida no puede estar generando carga/temperatura
                    // peligrosa; evitamos además conservar una alerta antigua.
                    globalGu = 0;
                    globalGt = 0;
                }

                sysRamPercent = parseFloat(p[4]) || 0;
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
    property real maxRam: 90
    
    property bool isOverheating: globalCt > maxTemp || globalGt > maxTemp
    property bool isOverloaded: globalCu > maxLoad || sysRamPercent >= maxRam
    property bool isBtConnected: false 
    
    property string colorTemp: "#ff3b30"
    property string colorLoad: "#ff9f0a"
    property string colorBt: "#0a84ff"  
    
    property string baseAlertColor: isOverheating ? colorTemp : (isOverloaded ? colorLoad : (isBtConnected ? colorBt : "transparent"))
    property string altAlertColor: (isOverheating && isOverloaded) ? colorLoad : (baseAlertColor !== "transparent" ? Qt.alpha(baseAlertColor, 0.2) : "transparent")

    // --- STATES AND SIZES ---
    // Normal behaviour: hovering the island expands it. While a screen
    // recording live activity is shown, the pause/stop controls must remain
    // easy to click, so expansion is only armed by hovering the clock area.
    property bool isExpanded: islandWindow.isUserSeeking
                              || (!islandWindow.recordingActivityActive && hoverArea.containsMouse)
                              || (islandWindow.recordingActivityActive && islandWindow.recordingHoverExpandArmed)

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

            onExited: {
                if (islandWindow.recordingActivityActive && !islandWindow.isUserSeeking)
                    islandWindow.recordingHoverExpandArmed = false
            }
            
            Timer { id: wheelCooldown; interval: 400 }
            
            onWheel: (wheel) => {
                if (!islandWindow.isExpanded || wheelCooldown.running) return;

                // Touchpad: mantiene el gesto horizontal que ya existía.
                // Ratón: añade la rueda vertical como segunda forma de navegar.
                // Priorizamos el eje horizontal si ambos traen delta para no
                // alterar el comportamiento actual del touchpad.
                var delta = Math.abs(wheel.angleDelta.x) >= Math.abs(wheel.angleDelta.y)
                            ? wheel.angleDelta.x
                            : wheel.angleDelta.y;

                if (delta < -40) {
                    // Swipe izquierda / rueda arriba: 0 -> 1 -> 2 -> 0
                    currentTab = (currentTab + 1) % totalTabs;
                    wheelCooldown.restart();
                } else if (delta > 40) {
                    // Swipe derecha / rueda abajo: 0 -> 2 -> 1 -> 0
                    currentTab = (currentTab - 1 + totalTabs) % totalTabs;
                    wheelCooldown.restart();
                }
            }
        }

        // Persistent clock hover hotspot used only while recording. It stays
        // alive even when the compact recording row becomes invisible during
        // expansion, so every leave/re-enter cycle reliably arms expansion.
        // Its scene position is kept fixed relative to the island center even
        // while visualBg changes width.
        Item {
            id: recordingExpansionHotspot
            visible: islandWindow.recordingActivityActive
                     && (islandWindow.recordingStatus === "running"
                         || islandWindow.recordingStatus === "paused")
            x: (parent.width / 2) + 46
            y: 0
            width: 72
            height: 32
            z: 1200

            HoverHandler {
                id: recordingClockHoverHandler
                onHoveredChanged: {
                    if (hovered)
                        islandWindow.recordingHoverExpandArmed = true
                }
            }
        }

        // ── COLLAPSED STATE: CLOCK & PASSIVE OSD ──
        Item {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            height: 32

            visible: !islandWindow.isExpanded && !islandWindow.isNotifying && !islandWindow.recordingActivityActive
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
                    font.family: Theme.fontIconss
                    font.pixelSize: 12
                    visible: dlSpeed >= 5 
                }
                
            }

            // ---------------------------------------------------------
            // MINI ONDA ONE UI EN EL BORDE INFERIOR DEL RELOJ
            // ---------------------------------------------------------
            // Sustituye a las antiguas tres barras verticales.
            //
            // Coste mínimo:
            //  - Canvas diminuto.
            //  - Sin CAVA, FFT ni procesos externos.
            //  - ~15 FPS.
            //  - Solo se anima con música reproduciéndose y la isla cerrada.
            //  - Reutiliza la paleta ya calculada de la carátula.
            Item {
                id: collapsedWaveArea
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter

                width: Math.min(parent.width * 0.62, 92)
                height: 9

                visible: islandWindow.isPlaying
                         && !islandWindow.isExpanded
                         && !islandWindow.isNotifying

                property real phase: 0

                Timer {
                    id: collapsedWaveTimer
                    interval: 66 // ~15 FPS
                    repeat: true
                    running: collapsedWaveArea.visible

                    onTriggered: {
                        collapsedWaveArea.phase += 0.095;

                        if (collapsedWaveArea.phase > 1000000)
                            collapsedWaveArea.phase = 0;

                        collapsedWaveCanvas.requestPaint();
                    }
                }

                Connections {
                    target: islandWindow

                    function onArtworkPalettePrimaryChanged() {
                        collapsedWaveCanvas.requestPaint();
                    }

                    function onArtworkPaletteSecondaryChanged() {
                        collapsedWaveCanvas.requestPaint();
                    }

                    function onArtworkPaletteAccentChanged() {
                        collapsedWaveCanvas.requestPaint();
                    }

                    function onIsPlayingChanged() {
                        collapsedWaveCanvas.requestPaint();
                    }
                }

                Canvas {
                    id: collapsedWaveCanvas
                    anchors.fill: parent

                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();

                        var w = width;
                        var h = height;

                        if (
                            w <= 0
                            || h <= 0
                            || !islandWindow.isPlaying
                        ) {
                            return;
                        }

                        // La base coincide prácticamente con el borde inferior
                        // interior de la píldora y las ondas crecen hacia arriba.
                        var baseY = h - 0.8;
                        var phase = collapsedWaveArea.phase;
                        var edgeFade = 10;

                        function drawMiniWave(
                            amplitude,
                            periodPx,
                            speedPx,
                            alpha,
                            waveColor
                        ) {
                            ctx.beginPath();
                            ctx.moveTo(0, baseY);

                            var step = 2;
                            var omega = (
                                Math.PI * 2
                            ) / Math.max(
                                1,
                                periodPx
                            );

                            var travel = (
                                phase * speedPx
                            );

                            for (
                                var x = 0;
                                x <= w;
                                x += step
                            ) {
                                // Fade interno en los dos extremos para que
                                // no aparezcan paredes verticales.
                                var fadeIn = Math.min(
                                    1,
                                    Math.max(
                                        0,
                                        x / edgeFade
                                    )
                                );

                                var fadeOut = Math.min(
                                    1,
                                    Math.max(
                                        0,
                                        (w - x) / edgeFade
                                    )
                                );

                                var envelope = (
                                    fadeIn * fadeOut
                                );

                                var s1 = (
                                    0.5
                                    + 0.5
                                    * Math.sin(
                                        (x - travel)
                                        * omega
                                    )
                                );

                                var s2 = (
                                    0.5
                                    + 0.5
                                    * Math.sin(
                                        (x - travel * 0.62)
                                        * omega
                                        * 0.58
                                        + 1.15
                                    )
                                );

                                var shape = (
                                    s1 * 0.72
                                    + s2 * 0.28
                                );

                                var y = (
                                    baseY
                                    - shape
                                    * amplitude
                                    * envelope
                                );

                                if (x === 0)
                                    ctx.moveTo(
                                        x,
                                        baseY
                                    );

                                ctx.lineTo(
                                    x,
                                    y
                                );
                            }

                            ctx.lineTo(
                                w,
                                baseY
                            );
                            ctx.closePath();

                            ctx.fillStyle = Qt.alpha(
                                waveColor,
                                alpha
                            );
                            ctx.fill();
                        }

                        // Tres capas como en el reproductor expandido,
                        // escaladas al tamaño de la isla cerrada.
                        drawMiniWave(
                            6.3,
                            66,
                            18,
                            0.36,
                            islandWindow.artworkPalettePrimary
                        );

                        drawMiniWave(
                            4.7,
                            50,
                            -13,
                            0.43,
                            islandWindow.artworkPaletteSecondary
                        );

                        drawMiniWave(
                            3.3,
                            38,
                            10,
                            0.50,
                            islandWindow.artworkPaletteAccent
                        );

                        // Cresta fina que define mejor la silueta.
                        ctx.beginPath();

                        var crestStep = 2;
                        var crestOmega = (
                            Math.PI * 2
                        ) / 50;

                        for (
                            var cx = 0;
                            cx <= w;
                            cx += crestStep
                        ) {
                            var cFadeIn = Math.min(
                                1,
                                Math.max(
                                    0,
                                    cx / edgeFade
                                )
                            );

                            var cFadeOut = Math.min(
                                1,
                                Math.max(
                                    0,
                                    (w - cx) / edgeFade
                                )
                            );

                            var cEnv = (
                                cFadeIn
                                * cFadeOut
                            );

                            var c1 = (
                                0.5
                                + 0.5
                                * Math.sin(
                                    (cx - phase * 13)
                                    * crestOmega
                                )
                            );

                            var c2 = (
                                0.5
                                + 0.5
                                * Math.sin(
                                    (cx - phase * 8)
                                    * crestOmega
                                    * 0.54
                                    + 0.9
                                )
                            );

                            var cShape = (
                                c1 * 0.72
                                + c2 * 0.28
                            );

                            var cy = (
                                baseY
                                - cShape
                                * 4.4
                                * cEnv
                            );

                            if (cx === 0)
                                ctx.moveTo(
                                    cx,
                                    baseY
                                );
                            else
                                ctx.lineTo(
                                    cx,
                                    cy
                                );
                        }

                        ctx.lineTo(
                            w,
                            baseY
                        );
                        ctx.lineWidth = 0.9;
                        ctx.lineJoin = "round";
                        ctx.lineCap = "round";

                        ctx.strokeStyle = Qt.alpha(
                            islandWindow.artworkPaletteAccent,
                            0.74
                        );

                        ctx.stroke();
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

        // ── COLLAPSED STATE: SCREEN RECORDING LIVE ACTIVITY ──
        Item {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            height: 32

            visible: !islandWindow.isExpanded
                     && !islandWindow.isNotifying
                     && islandWindow.recordingActivityActive
            opacity: (!visualBg.isAnimating && visible) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 0

                Row {
                    id: recordingActivityRow
                    spacing: 8
                    Layout.alignment: Qt.AlignVCenter

                    Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        color: islandWindow.recordingStatus === "paused"
                               ? Qt.alpha("#ff453a", 0.45)
                               : "#ff453a"
                        anchors.verticalCenter: parent.verticalCenter

                        SequentialAnimation on opacity {
                            running: islandWindow.recordingStatus === "running"
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.35; duration: 700 }
                            NumberAnimation { to: 1.0; duration: 700 }
                        }
                    }

                    Text {
                        id: recordingStatusText
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            if (islandWindow.recordingStatus === "starting") return "Select capture";
                            if (islandWindow.recordingStatus === "finalizing") return "Saving…";
                            return islandWindow.formatRecordingTime(islandWindow.recordingElapsed);
                        }
                        color: Theme.white
                        font.family: Theme.fontMain
                        font.pixelSize: 13
                        font.bold: true
                    }

                    Row {
                        id: recordingButtonsRow
                        visible: islandWindow.recordingStatus === "running" || islandWindow.recordingStatus === "paused"
                        spacing: 5
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            visible: parent.visible
                            width: 22
                            height: 22
                            radius: 11
                            color: recordingPauseMouse.containsMouse
                                   ? Qt.alpha(Theme.white, 0.18)
                                   : Qt.alpha(Theme.white, 0.09)
                            border.color: Qt.alpha(Theme.white, 0.12)
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: islandWindow.recordingStatus === "paused" ? "" : ""
                                color: Theme.white
                                font.family: Theme.fontIcons
                                font.pixelSize: 10
                            }

                            MouseArea {
                                id: recordingPauseMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: islandWindow.toggleRecordingPause()
                            }
                        }

                        Rectangle {
                            visible: parent.visible
                            width: 22
                            height: 22
                            radius: 11
                            color: recordingStopMouse.containsMouse
                                   ? Qt.alpha("#ff453a", 0.28)
                                   : Qt.alpha("#ff453a", 0.14)
                            border.color: Qt.alpha("#ff453a", 0.50)
                            border.width: 1

                            Rectangle {
                                anchors.centerIn: parent
                                width: 7
                                height: 7
                                radius: 2
                                color: "#ff453a"
                            }

                            MouseArea {
                                id: recordingStopMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: islandWindow.stopRecording()
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.minimumWidth: (islandWindow.recordingStatus === "running" || islandWindow.recordingStatus === "paused") ? 18 : 0
                }

                Item {
                    id: recordingClockHotspot
                    visible: islandWindow.recordingStatus === "running" || islandWindow.recordingStatus === "paused"
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: recordingClockText.implicitWidth + 10
                    implicitHeight: parent.height

                    Text {
                        id: recordingClockText
                        anchors.centerIn: parent
                        text: customClock.text
                        color: Qt.alpha(Theme.white, 0.62)
                        font.family: Theme.fontMain
                        font.pixelSize: 11
                        font.bold: true
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
                    font.family: Theme.fontIconss
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
                            font.family: Theme.fontIconss
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
                                    font.family: Theme.fontIconss
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
                                        font.family: Theme.fontIconss
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
                                        font.family: Theme.fontIconss
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
                                        font.family: Theme.fontIconss
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
                                    font.family: Theme.fontIconss
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
            // TAB 1: MODERN SYSTEM DASHBOARD
            // ================================
            Item {
                width: parent.width
                height: parent.height
                x: islandWindow.circularTabOffset(1) * width
                opacity: currentTab === 1 ? 1 : 0
                Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.OutQuint } }
                Behavior on opacity { NumberAnimation { duration: 250 } }
                visible: opacity > 0

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 13
                    spacing: 8

                    // Header: title + two useful context values that cost nothing extra.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 24
                        spacing: 8

                        Text {
                            text: "System"
                            color: Theme.white
                            font.family: Theme.fontMain
                            font.pixelSize: 15
                            font.bold: true
                        }

                        Rectangle {
                            Layout.preferredWidth: loadText.implicitWidth + 14
                            Layout.preferredHeight: 20
                            radius: 10
                            color: Qt.alpha(Theme.white, 0.08)
                            border.width: 1
                            border.color: Qt.alpha(Theme.white, 0.08)
                            Text {
                                id: loadText
                                anchors.centerIn: parent
                                text: "Load " + sysLoad1.toFixed(2)
                                color: Qt.alpha(Theme.white, 0.68)
                                font.family: Theme.fontMain
                                font.pixelSize: 9
                                font.bold: true
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: "Up " + sysUptime
                            color: Qt.alpha(Theme.white, 0.52)
                            font.family: Theme.fontMain
                            font.pixelSize: 9
                            font.bold: true
                        }
                    }

                    // Main row: CPU/GPU get visual priority; memory/storage stay compact.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 8

                        Repeater {
                            model: [
                                { name: "CPU", icon: "󰻠", usage: sysCpuUsage, temp: sysCpuTemp },
                                { name: "GPU", icon: "󰢮", usage: sysGpuUsage, temp: sysGpuTemp }
                            ]

                            Rectangle {
                                Layout.preferredWidth: 116
                                Layout.fillHeight: true
                                radius: 16
                                color: Qt.alpha(Theme.white, 0.075)
                                border.width: 1
                                border.color: Qt.alpha(Theme.white, 0.10)

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 4

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 5
                                        Text {
                                            text: modelData.icon
                                            color: Qt.alpha(Theme.white, 0.78)
                                            font.family: Theme.fontIcons
                                            font.pixelSize: 13
                                        }
                                        Text {
                                            text: modelData.name
                                            color: Qt.alpha(Theme.white, 0.66)
                                            font.family: Theme.fontMain
                                            font.pixelSize: 10
                                            font.bold: true
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: Math.round(modelData.temp) + "°"
                                            color: modelData.temp > maxTemp ? colorTemp : Qt.alpha(Theme.white, 0.78)
                                            font.family: Theme.fontMain
                                            font.pixelSize: 10
                                            font.bold: true
                                        }
                                    }

                                    Text {
                                        text: Math.round(modelData.usage) + "%"
                                        color: modelData.usage > maxLoad ? colorLoad : Theme.white
                                        font.family: Theme.fontMain
                                        font.pixelSize: 27
                                        font.bold: true
                                        Layout.topMargin: 1
                                    }

                                    Item { Layout.fillHeight: true }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 5
                                        radius: 2.5
                                        color: Qt.alpha(Theme.white, 0.10)
                                        Rectangle {
                                            width: parent.width * Math.max(0, Math.min(1, modelData.usage / 100))
                                            height: parent.height
                                            radius: parent.radius
                                            color: modelData.usage > maxLoad ? colorLoad : Theme.white
                                            Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                                        }
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 8

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 14
                                color: Qt.alpha(Theme.white, 0.065)
                                border.width: 1
                                border.color: Qt.alpha(Theme.white, 0.09)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 9
                                    spacing: 8

                                    Text {
                                        text: "󰍛"
                                        color: Qt.alpha(Theme.white, 0.72)
                                        font.family: Theme.fontIcons
                                        font.pixelSize: 15
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Text {
                                            text: "Memory"
                                            color: Qt.alpha(Theme.white, 0.54)
                                            font.family: Theme.fontMain
                                            font.pixelSize: 9
                                            font.bold: true
                                        }
                                        Text {
                                            text: sysRamUsage.toFixed(1) + " / " + sysRamTotal.toFixed(0) + " GB"
                                            color: sysRamPercent >= maxRam ? colorLoad : Theme.white
                                            font.family: Theme.fontMain
                                            font.pixelSize: 12
                                            font.bold: true
                                        }
                                    }
                                    Text {
                                        text: Math.round(sysRamPercent) + "%"
                                        color: sysRamPercent >= maxRam ? colorLoad : Qt.alpha(Theme.white, 0.82)
                                        font.family: Theme.fontMain
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 14
                                color: Qt.alpha(Theme.white, 0.065)
                                border.width: 1
                                border.color: Qt.alpha(Theme.white, 0.09)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 9
                                    spacing: 8

                                    Text {
                                        text: "󰋊"
                                        color: Qt.alpha(Theme.white, 0.72)
                                        font.family: Theme.fontIcons
                                        font.pixelSize: 15
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Text {
                                            text: "Storage"
                                            color: Qt.alpha(Theme.white, 0.54)
                                            font.family: Theme.fontMain
                                            font.pixelSize: 9
                                            font.bold: true
                                        }
                                        Text {
                                            // Igual que Memory: espacio usado / capacidad total.
                                            text: sysStorage
                                            color: Theme.white
                                            font.family: Theme.fontMain
                                            font.pixelSize: 12
                                            font.bold: true
                                        }
                                    }
                                    Text {
                                        text: Math.round(sysStoragePercent) + "%"
                                        color: Qt.alpha(Theme.white, 0.82)
                                        font.family: Theme.fontMain
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                }
                            }
                        }
                    }

                    // Bottom strip: network throughput. No extra command is needed;
                    // it is derived from the same /sys read as the main sampler.
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 25
                        radius: 12
                        color: Qt.alpha(Theme.white, 0.055)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 6

                            Text {
                                text: "󰇚"
                                color: dlSpeed >= 5 ? "#30d158" : Qt.alpha(Theme.white, 0.58)
                                font.family: Theme.fontIcons
                                font.pixelSize: 12
                            }
                            Text {
                                text: dlSpeed < 1 ? Math.round(dlSpeed * 1024) + " KB/s" : dlSpeed.toFixed(dlSpeed < 10 ? 1 : 0) + " MB/s"
                                color: Theme.white
                                font.family: Theme.fontMain
                                font.pixelSize: 10
                                font.bold: true
                            }
                            Text {
                                text: "Download"
                                color: Qt.alpha(Theme.white, 0.42)
                                font.family: Theme.fontMain
                                font.pixelSize: 9
                            }

                            Item { Layout.fillWidth: true }

                            Item {
                                Layout.preferredWidth: 20
                                Layout.preferredHeight: 11
                                Layout.alignment: Qt.AlignVCenter

                                property color batteryColor: batCap <= 20 && batStatus === "Discharging"
                                    ? colorTemp
                                    : Qt.alpha(Theme.white, 0.72)

                                // Cuerpo horizontal de la batería.
                                Rectangle {
                                    id: statsBatteryBody
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 17
                                    height: 9
                                    radius: 2.2
                                    color: "transparent"
                                    border.width: 1.25
                                    border.color: parent.batteryColor

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.max(1, (parent.width - 4) * Math.max(0, Math.min(1, batCap / 100)))
                                        height: parent.height - 4
                                        radius: 1
                                        color: statsBatteryBody.parent.batteryColor
                                    }
                                }

                                // Terminal positivo.
                                Rectangle {
                                    anchors.left: statsBatteryBody.right
                                    anchors.leftMargin: 1
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 2
                                    height: 4
                                    radius: 1
                                    color: parent.batteryColor
                                }
                            }
                            Text {
                                text: Math.round(batCap) + "%"
                                color: batCap <= 20 && batStatus === "Discharging" ? colorTemp : Theme.white
                                font.family: Theme.fontMain
                                font.pixelSize: 10
                                font.bold: true
                            }
                            Text {
                                text: batStatus === "Charging" ? "Charging" : "Battery"
                                color: Qt.alpha(Theme.white, 0.42)
                                font.family: Theme.fontMain
                                font.pixelSize: 9
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