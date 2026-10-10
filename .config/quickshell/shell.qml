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

    // ============================================================
    // PRIMARY QUICKSHELL UI SCREEN
    // ============================================================
    //
    // Normal dual-monitor mode:
    //   eDP-1 exists -> all singleton Quickshell UI stays on the laptop.
    //
    // Clamshell mode:
    //   eDP-1 is disabled by lid_switch.sh -> HDMI-A-1 becomes the UI screen.
    //
    // Quickshell.screens is updated by Wayland output events, so this adds no
    // polling, timer or background process.
    readonly property var primaryUiScreen: {
        var screens = Quickshell.screens

        for (var i = 0; i < screens.length; ++i) {
            if (screens[i].name === "eDP-1")
                return screens[i]
        }

        for (var j = 0; j < screens.length; ++j) {
            if (screens[j].name === "HDMI-A-1")
                return screens[j]
        }

        return screens.length > 0 ? screens[0] : null
    }

    property int batCap: 0
    property string batStat: ""
    property int vol: 0
    property bool volMute: false
    property string volDesc: ""
    property string wifiSsid: ""
    property bool wifiRadioEnabled: false
    property string wifiSig: ""
    property string wifiFreq: ""
    property string btStat: "off"
    property string btDev: ""
    property string perfMode: "balanced"
    property bool dnd: false
 
    property int notifCount: 0
    property bool hasUnread: false
    property int lastNotifId: -1
    property int cpuUsage: 0
    property int memUsage: 0

    // Estados del panel lateral (ControlCenter)
    property bool airplaneMode: false
    property bool caffeineMode: false
    property bool onAcPower: false
    property bool nightLightMode: false
    property int nightLightTemperature: 4000
    property bool nightLightSetPending: false
    property int nightLightPendingTemperature: 4000

    property bool isNotifOpen: false
    property string activeMenuTitle: ""
    property string activeMenuInfo1: ""
    property string activeMenuInfo2: ""
    property color activeMenuAccent: "#ffffff"
    property int activeMenuOffset: 52 
    property bool isMenuOpen: false
    property bool isMenuVisible: false

    // --- ESTADOS LÓGICOS PARA EL MENÚ DEL PORTAPAPELES ---
    property bool isClipIconHovered: false
    property bool isClipMenuHovered: false
    property bool isClipMenuOpen: false

    Timer {
        id: clipHideTimer
        interval: 150
        onTriggered: {
            if (!root.isClipIconHovered && !root.isClipMenuHovered) {
                root.isClipMenuOpen = false;
            }
        }
    }

    function enterClipIcon() {
        root.isClipIconHovered = true;
        root.isClipMenuOpen = true;
        clipHideTimer.stop();

        if (!clipProc.running)
            clipProc.running = true;
    }

    function startClipHideTimer() {
        root.isClipIconHovered = false;
        clipHideTimer.start();
    }

    // --- ESTADOS PARA CAVA VISUALIZER ---
    property bool isPlayingMedia: false

    // Native, reactive Hyprland state.
    // No bash/socat/hyprctl watcher is needed.
    readonly property bool isWorkspaceEmpty:
        !Hyprland.focusedWorkspace
        || Hyprland.focusedWorkspace.toplevels.values.length === 0

    property bool showCavaVisualizer: false 

    property string cavaColor: Theme.blue 

    // --- ESTADOS DEL DOCK DINÁMICO ---
    property int bottomGap: 12
    property bool isDockHovered: false
    property bool isMacosMode: false

    // --- ESTADOS DE ALT+TAB NATIVO ---
    property bool isAltTabVisible: false
    property var altTabList: []
    property int altTabCurrentIndex: 0

    // --- ESTADOS DE PANTALLA COMPLETA ---
    // Native reactive state from Quickshell.Hyprland.
    readonly property bool isFullscreen:
        Hyprland.focusedWorkspace
        ? Hyprland.focusedWorkspace.hasFullscreen
        : false

    property bool isTopHovered: false

    property alias sharedNotifModel: sharedNotifModel
    ListModel { id: sharedNotifModel }
    ListModel {
        id: cavaModel
        Component.onCompleted: {
            for (var i = 0; i < 120; i++) {
                append({"barHeight": 0});
            }
        }
    }
    
    // --- MODELO PORTAPAPELES ---
    property alias clipboardModel: clipboardModel
    ListModel { id: clipboardModel }

    // Serialize writes to the notification daemon FIFO. The Notification
    // Center, the Dynamic Island notifications tab and the transient island
    // presentation may all request actions close together.
    property var notifCommandQueue: []

    function pumpNotifCommandQueue() {
        if (notifActionProc.running || notifCommandQueue.length === 0)
            return

        var queue = notifCommandQueue.slice(0)
        var command = queue.shift()
        notifCommandQueue = queue

        notifActionProc.command = [
            "bash", "-c",
            "printf '%s\\n' '" + command + "' > /tmp/qs_notif_cmd"
        ]
        notifActionProc.running = true
    }

    function sendNotifCommand(command) {
        var queue = notifCommandQueue.slice(0)
        queue.push(String(command))
        notifCommandQueue = queue
        pumpNotifCommandQueue()
    }

    function clearNotifications() { sendNotifCommand("CLEAR") }
    function toggleDnd() { sendNotifCommand("TOGGLE_DND") }
    function removeNotification(notifId) {
        var id = Number(notifId)
        if (!isNaN(id) && id >= 0)
            sendNotifCommand("REMOVE|" + id)
    }
    
    // Funciones del Portapapeles
    function refreshClipboard() {
        if (!clipProc.running)
            clipProc.running = true;
    }

    function copyClipItem(id) {
        clipActionProc.command = ["bash", "-c", "cliphist decode " + id + " | wl-copy"]
        clipActionProc.running = true
        clipRefreshTimer.restart()
    }

    function deleteClipItem(id) {
        clipActionProc.command = [
            "bash", "-c",
            "cliphist list | awk -F '\t' -v id='" + id + "' '$1 == id { print; exit }' | cliphist delete"
        ]
        clipActionProc.running = true
        clipRefreshTimer.restart()
    }

    function clearClipHistory() {
        clipActionProc.command = ["bash", "-c", "cliphist wipe"]
        clipActionProc.running = true
        clipRefreshTimer.restart()
    }

    Timer {
        id: clipRefreshTimer
        interval: 150
        repeat: false
        onTriggered: root.refreshClipboard()
    }
    
    // Procesos separados
    Process { id: cmdProc }
    Process {
        id: notifActionProc
        onRunningChanged: {
            if (!running)
                Qt.callLater(root.pumpNotifCommandQueue)
        }
    }
    Process {
        id: wifiProc
        command: ["sh", "-c", "nmcli radio wifi | grep -q 'enabled' && nmcli radio wifi off || nmcli radio wifi on"]
        onRunningChanged: {
            if (!running)
                Qt.callLater(root.refreshWifiRadioState)
        }
    }
    // Event-triggered radio probe: a connected SSID alone cannot tell us
    // whether Wi-Fi is enabled but not yet connected to a network.
    Process {
        id: wifiRadioStateProc
        running: true
        command: ["sh", "-c", "LC_ALL=C nmcli radio wifi 2>/dev/null"]
        stdout: SplitParser {
            onRead: function(line) {
                var status = line.trim()
                if (status === "enabled" || status === "disabled")
                    root.wifiRadioEnabled = (status === "enabled")
            }
        }
    }
    function refreshWifiRadioState() {
        if (!wifiRadioStateProc.running)
            wifiRadioStateProc.running = true
    }
    onWifiSsidChanged: {
        if (isNotifOpen)
            Qt.callLater(root.refreshWifiRadioState)
    }
    Process { id: btProc; command: ["sh", "-c", "rfkill toggle bluetooth"] }
    Process { id: airplaneProc; command: ["sh", "-c", "rfkill list all | grep -q 'Soft blocked: no' && rfkill block all || rfkill unblock all"] }
    Process { id: caffeineProc; command: ["sh", "-c", "pidof hypridle > /dev/null && killall hypridle || hypridle &"] }

    // Manual Power Saver override. power_mode.sh still owns the automatic
    // AC policy: battery -> power-saver, AC -> balanced. While on battery,
    // this button may temporarily switch between those two profiles.
    Process {
        id: powerSaverProc
        command: [
            "bash", "-c",
            "ac=0; " +
            "for f in /sys/class/power_supply/AC*/online /sys/class/power_supply/ADP*/online; do " +
            "  [ -r \"$f\" ] || continue; read -r v < \"$f\"; [ \"$v\" = 1 ] && ac=1 && break; " +
            "done; " +
            "if [ \"$ac\" = 1 ]; then echo ac; exit 0; fi; " +
            "current=$(powerprofilesctl get 2>/dev/null || echo balanced); " +
            "if [ \"$current\" = power-saver ]; then target=balanced; else target=power-saver; fi; " +
            "if powerprofilesctl set \"$target\" >/dev/null 2>&1; then echo \"$target\"; else echo error; fi"
        ]
        stdout: SplitParser {
            onRead: function(data) {
                var value = data.trim()
                if (value === "power-saver" || value === "balanced")
                    root.perfMode = value
                else if (value === "error")
                    console.warn("Power Saver: could not change power profile")
            }
        }
    }

    // Night Light: hyprsunset is Hyprland's native blue-light filter.
    // A tiny marker in /tmp keeps Quickshell's visual state across shell reloads.
    // No polling/timer is used: state only changes on startup or when clicked.
    Process {
        id: nightLightStateReader
        running: true
        command: [
            "bash", "-c",
            "temp=$(cat /tmp/qs_night_light_temperature 2>/dev/null || echo 4000); " +
            "case $temp in ''|*[!0-9]*) temp=4000;; esac; " +
            "if [ -f /tmp/qs_night_light ] && pgrep -x hyprsunset >/dev/null 2>&1; " +
            "then state=1; else rm -f /tmp/qs_night_light; state=0; fi; " +
            "echo \"$state;$temp\""
        ]
        stdout: SplitParser {
            onRead: function(data) {
                var fields = data.trim().split(";")
                if (fields.length >= 1 && (fields[0] === "1" || fields[0] === "0"))
                    root.nightLightMode = (fields[0] === "1")
                if (fields.length >= 2) {
                    var temperature = parseInt(fields[1])
                    if (!isNaN(temperature))
                        root.nightLightTemperature = Math.max(2500, Math.min(6000, temperature))
                }
            }
        }
    }

    Process {
        id: nightLightProc
        command: [
            "bash", "-c",
            "if ! command -v hyprsunset >/dev/null 2>&1; then echo missing; exit 127; fi; " +
            "if ! pgrep -x hyprsunset >/dev/null 2>&1; then " +
            "  nohup hyprsunset >/dev/null 2>&1 & " +
            "  for i in $(seq 1 20); do " +
            "    hyprctl hyprsunset identity >/dev/null 2>&1 && break; " +
            "    sleep 0.05; " +
            "  done; " +
            "fi; " +
            "if [ -f /tmp/qs_night_light ]; then " +
            "  if hyprctl hyprsunset identity >/dev/null 2>&1; then rm -f /tmp/qs_night_light; echo 0; else echo error; fi; " +
            "else " +
            "  if hyprctl hyprsunset temperature " + root.nightLightTemperature + " >/dev/null 2>&1; then " +
            "    printf '%s' '" + root.nightLightTemperature + "' > /tmp/qs_night_light_temperature; touch /tmp/qs_night_light; echo 1; " +
            "  else echo error; fi; " +
            "fi"
        ]
        stdout: SplitParser {
            onRead: function(data) {
                var value = data.trim()
                if (value === "1" || value === "0")
                    root.nightLightMode = (value === "1")
                else if (value === "missing")
                    console.warn("Night Light: hyprsunset is not installed")
                else if (value === "error")
                    console.warn("Night Light: could not talk to hyprsunset")
            }
        }
    }

    function setNightLightTemperature(temperature) {
        temperature = Math.max(2500, Math.min(6000, Math.round(temperature / 100) * 100))
        root.nightLightTemperature = temperature
        root.nightLightPendingTemperature = temperature

        if (nightLightSetProc.running) {
            root.nightLightSetPending = true
            return
        }

        root.nightLightSetPending = false
        nightLightSetProc.command = [
            "bash", "-c",
            "if ! command -v hyprsunset >/dev/null 2>&1; then echo missing; exit 127; fi; " +
            "if ! pgrep -x hyprsunset >/dev/null 2>&1; then " +
            "  nohup hyprsunset >/dev/null 2>&1 & " +
            "  for i in $(seq 1 20); do hyprctl hyprsunset identity >/dev/null 2>&1 && break; sleep 0.05; done; " +
            "fi; " +
            "if hyprctl hyprsunset temperature " + temperature + " >/dev/null 2>&1; then " +
            "  printf '%s' '" + temperature + "' > /tmp/qs_night_light_temperature; " +
            "  touch /tmp/qs_night_light; echo ok; " +
            "else echo error; fi"
        ]
        nightLightSetProc.running = true
    }

    Process {
        id: nightLightSetProc

        stdout: SplitParser {
            onRead: function(data) {
                var value = data.trim()
                if (value === "ok")
                    root.nightLightMode = true
                else if (value === "missing")
                    console.warn("Night Light: hyprsunset is not installed")
                else if (value === "error")
                    console.warn("Night Light: could not set temperature")
            }
        }

        onRunningChanged: {
            if (!running && root.nightLightSetPending) {
                root.nightLightSetPending = false
                root.setNightLightTemperature(root.nightLightPendingTemperature)
            }
        }
    }

    Process { id: clipActionProc } // Para comandos del portapapeles

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

    // --- MONITOR DE MEDIOS ---
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
        // The ControlCenter no longer displays pending notifications, so
        // opening it must NOT mark them as read. Only the island's native
        // Notifications tab acknowledges them. Keep the existing popup
        // dismissal and Wi-Fi state refresh when ControlCenter opens.
        if (isNotifOpen) {
            islandNotification.dismissAll()
            Qt.callLater(root.refreshWifiRadioState)
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
        screen: root.primaryUiScreen
        onRequestIslandMsg: function(icon, color, text) {
            if (typeof islandWidget !== "undefined") {
                islandWidget.triggerMsg(icon, color, text);
            }
        }
    }

    // --- XAVION CHAT ---
    XavionService {
        id: xavionService
    }

    LazyLoader {
        id: xavionPanelLoader
        active: xavionService.panelOpen

        XavionPanel {
            screen: root.primaryUiScreen
            service: xavionService
        }
    }

    ControlCenter {
        id: controlCenterPanel
        screen: root.primaryUiScreen

        // Laptop keeps the original position. The HDMI value is used only
        // when eDP-1 is disabled and HDMI-A-1 becomes primaryUiScreen.
        panelTopMargin: root.primaryUiScreen
            && root.primaryUiScreen.name === "HDMI-A-1"
            ? 10
            : 2

        panelRightMargin: root.primaryUiScreen
            && root.primaryUiScreen.name === "HDMI-A-1"
            ? 10
            : 12

        visible_state: root.isNotifOpen
        dndState: root.dnd
        
        wifiState: root.wifiRadioEnabled
        wifiNetworkName: root.wifiSsid
        btDeviceName: root.btDev
        btState: root.btStat === "on"
        airplaneState: root.airplaneMode
        caffeineState: root.caffeineMode
        powerSaverState: root.perfMode === "power-saver"
        powerSaverAvailable: !root.onAcPower
        nightLightState: root.nightLightMode
        nightLightTemperature: root.nightLightTemperature
        
        onRequestClose: { root.isNotifOpen = false }
        onToggleDndRequested: { root.toggleDnd() }

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
        onTogglePowerSaverRequested: {
            if (!root.onAcPower && !powerSaverProc.running)
                powerSaverProc.running = true
        }
        onToggleNightLightRequested: {
            if (!nightLightProc.running)
                nightLightProc.running = true
        }
        onSetNightLightTemperatureRequested: function(temperature) {
            root.setNightLightTemperature(temperature)
        }
        onPowerRequested: { console.log("Acción de power pulsada") }
    }

    GlobalShortcut {
        name: "launcher"
        onPressed: { mainLauncher.toggle() }
    }

    GlobalShortcut {
        name: "xavion"
        onPressed: {
            xavionService.togglePanel()
        }
    }

    Process {
        id: backendProc
        command: ["/home/javier/.config/quickshell/scripts/backend_daemon.sh"]
        running: true
        stdout: SplitParser {
            onRead: (data) => {
                var fields = data.trim().split("|")
                if (fields.length >= 16) {
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
                    root.onAcPower = (fields[15].trim() === "1")
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
                    var previousCount = root.notifCount
                    var newTopId = state.notifications.length > 0
                        ? Number(state.notifications[0].id)
                        : -1
                    // A lower count can expose a different top ID when an
                    // item was removed; that is not a new unread notification.
                    var isNewNotification = state.count > previousCount
                        || (state.count > 0 && state.count >= previousCount
                            && newTopId !== root.lastNotifId)

                    root.dnd = state.dnd
                    root.notifCount = state.count

                    // The unread indicator now lives on the Dynamic Island.
                    // The ControlCenter is NOT a notification reader. DND may
                    // suppress the popup, but the incoming item is still unread.
                    if (state.count === 0) {
                        root.hasUnread = false
                    } else if (!islandWidget.viewingNotifications
                               && isNewNotification) {
                        root.hasUnread = true
                    }

                    root.lastNotifId = newTopId

                    sharedNotifModel.clear()
                    for (var i = 0; i < state.notifications.length; i++) {
                        sharedNotifModel.append(state.notifications[i])
                    }
                    // A newly arrived notification must be visible at the top
                    // even if the user previously scrolled down in the tab.
                    if (isNewNotification && islandWidget.viewingNotifications)
                        Qt.callLater(islandWidget.showLatestNotificationFromTab)
                } else if (line.startsWith("POPUP|")) {
                    // Never interrupt an expanded Dynamic Island tab (Music,
                    // System, App Usage or Notifications) with a transient popup.
                    // STATE always updates sharedNotifModel, so the new item is
                    // available in Notifications even when the popup is skipped.
                    // The daemon owns the notification sound; this only skips
                    // the visual popup, without changing the sound behaviour.
                    if (!root.isNotifOpen && !root.dnd
                            && !islandWidget.isExpanded) {
                        root.hasUnread = true
                        var n = JSON.parse(line.substring(6))
                        islandNotification.enqueue(n)
                    }
                }
            }
        }
    }

    // --- PORTAPAPELES ---
    Process {
        id: clipProc

        command: [
            "bash",
            "-c",
            "cliphist list | head -n 25"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                clipboardModel.clear()

                var lines = text.split("\n")

                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i]

                    if (!line.trim())
                        continue

                    var tabIndex = line.indexOf("\t")

                    if (tabIndex === -1)
                        continue

                    var clipId = line.substring(0, tabIndex)
                    var clipContent = line.substring(tabIndex + 1)

                    clipboardModel.append({
                        clipId: clipId,
                        clipContent: clipContent
                    })
                }

                console.log(
                    "[Clipboard] Loaded " +
                    clipboardModel.count +
                    " entries"
                )
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0)
                    console.warn("[Clipboard] " + text.trim())
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
        if (!root.isAltTabVisible)
            return;

        if (root.altTabList.length > 0 && root.altTabCurrentIndex >= 0
                && root.altTabCurrentIndex < root.altTabList.length) {
            var target = root.altTabList[root.altTabCurrentIndex];

            if (target && target.address) {
                if (target.minimized) {
                    // Las ventanas "minimizadas" por nuestros scripts necesitan restaurarse
                    // primero; el script se ocupa de devolverlas a su workspace y enfocarlas.
                    altTabFocusProc.command = [
                        "bash", "-c",
                        "~/.config/hypr/scripts/macos_restore_minimized.sh '" + target.address + "'"
                    ];
                } else {
                    // Hyprland >= 0.55 usa dispatchers Lua. focus() acepta un selector
                    // address:0x... y cambia automáticamente al workspace/monitor de la
                    // ventana antes de enfocarla. Después la elevamos por si es flotante.
                    //
                    // Se conserva un fallback al dispatcher legacy para que el Alt+Tab
                    // siga funcionando si se arranca temporalmente una versión antigua.
                    var selector = "address:" + target.address;
                    altTabFocusProc.command = [
                        "bash", "-c",
                        "selector='" + selector + "'; "
                        + "out=$(hyprctl dispatch \"hl.dsp.focus({ window = '$selector' })\" 2>&1); "
                        + "rc=$?; "
                        + "if [ $rc -eq 0 ] && ! printf '%s' \"$out\" | grep -qiE 'invalid dispatcher|error'; then "
                        + "  hyprctl dispatch \"hl.dsp.window.bring_to_top()\" >/dev/null 2>&1 || true; "
                        + "else "
                        + "  hyprctl dispatch focuswindow \"$selector\" >/dev/null 2>&1; "
                        + "fi"
                    ];
                }

                // El mismo Process se reutiliza en cada cambio. Solo arrancamos una nueva
                // ejecución cuando la anterior ya ha terminado (normalmente es instantáneo).
                if (!altTabFocusProc.running)
                    altTabFocusProc.running = true;
            }
        }

        root.isAltTabVisible = false;
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

    PanelWindow {
        id: topBar
        screen: root.primaryUiScreen
        anchors { top: true; left: true; right: true }
        implicitHeight: 44
        // Keep the laptop exactly as before. The HDMI value is used only
        // while eDP-1 is disabled (clamshell mode). Tune 38 if desired.
        exclusiveZone: screen && screen.name === "HDMI-A-1" ? 38 : 44
        color: "transparent"

        BackgroundEffect.blurRegion: Glass.blurEnabled ? topBarBlurRegion : null

        Region {
            id: topBarBlurRegion
            item: leftBarGlass
            radius: leftBarGlass.radius

            Region {
                item: rightBarGlass
                radius: rightBarGlass.radius
            }
        }

        Item {
            id: topBarContent
            anchors.fill: parent
            opacity: 0
            NumberAnimation on opacity { from: 0; to: 1; duration: 400; easing.type: Easing.OutCubic; running: true }

            // ============================================================
            // XAVION IDLE ANIMATION
            // ============================================================
            // Event-driven only: one low-frequency QML timer schedules a very
            // short sprite animation every 25-70 seconds. No polling, shell
            // process, daemon or continuously running animation is involved.
            function scheduleNextXavionAnimation() {
                xavionIdleTimer.interval = 25000 + Math.floor(Math.random() * 45001)
                xavionIdleTimer.restart()
            }

            function playRandomXavionAnimation() {
                var animation = Math.floor(Math.random() * 3)

                switch (animation) {
                case 0:
                    xavionBlinkAnimation.restart()
                    break
                case 1:
                    xavionLookAroundAnimation.restart()
                    break
                case 2:
                    xavionLookRightAnimation.restart()
                    break
                case 3:
                    xavionLookLeftAnimation.restart()
                    break
                default:
                    xavionHappyAnimation.restart()
                    break
                }
            }

            Component.onCompleted: scheduleNextXavionAnimation()

            Timer {
                id: xavionIdleTimer
                repeat: false

                onTriggered: {
                    // Do not animate while a fullscreen application is active.
                    if (root.isFullscreen) {
                        topBarContent.scheduleNextXavionAnimation()
                        return
                    }

                    topBarContent.playRandomXavionAnimation()
                }
            }

            SequentialAnimation {
                id: xavionBlinkAnimation
                ScriptAction { script: xavionIcon.source = "assets/xavion/blink.png" }
                PauseAnimation { duration: 110 }
                ScriptAction { script: xavionIcon.source = "assets/xavion/idle.png" }
                onFinished: topBarContent.scheduleNextXavionAnimation()
            }

            SequentialAnimation {
                id: xavionLookLeftAnimation
                ScriptAction { script: xavionIcon.source = "assets/xavion/look-left.png" }
                PauseAnimation { duration: 220 }
                ScriptAction { script: xavionIcon.source = "assets/xavion/idle.png" }
                onFinished: topBarContent.scheduleNextXavionAnimation()
            }

            SequentialAnimation {
                id: xavionLookRightAnimation
                ScriptAction { script: xavionIcon.source = "assets/xavion/look-right.png" }
                PauseAnimation { duration: 220 }
                ScriptAction { script: xavionIcon.source = "assets/xavion/idle.png" }
                onFinished: topBarContent.scheduleNextXavionAnimation()
            }

            SequentialAnimation {
                id: xavionLookAroundAnimation
                ScriptAction { script: xavionIcon.source = "assets/xavion/look-left.png" }
                PauseAnimation { duration: 150 }
                ScriptAction { script: xavionIcon.source = "assets/xavion/idle.png" }
                PauseAnimation { duration: 90 }
                ScriptAction { script: xavionIcon.source = "assets/xavion/look-right.png" }
                PauseAnimation { duration: 150 }
                ScriptAction { script: xavionIcon.source = "assets/xavion/idle.png" }
                onFinished: topBarContent.scheduleNextXavionAnimation()
            }

            SequentialAnimation {
                id: xavionHappyAnimation
                ScriptAction { script: xavionIcon.source = "assets/xavion/happy.png" }
                PauseAnimation { duration: 300 }
                ScriptAction { script: xavionIcon.source = "assets/xavion/idle.png" }
                onFinished: topBarContent.scheduleNextXavionAnimation()
            }
            
            // ============================================================
            // OLD ARCH LAUNCHER ICON
            // ============================================================
            /*Text {
                text: ""; color: Theme.white; font.family: Theme.fontIcons; font.pixelSize: 22;
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { mainLauncher.toggle() } }
            }*/

            // ============================================================
            // XAVION
            // ============================================================
            Image {
                id: xavionIcon
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter

                width: 30
                height: 30

                source: "assets/xavion/idle.png"
                sourceSize.width: 30
                sourceSize.height: 30

                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                cache: true

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onClicked: {
                        xavionService.togglePanel()
                    }
                }
            }

            GlassSurface {
                id: leftBarGlass
                anchors.left: xavionIcon.right
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                height: 34
                width: leftRow.implicitWidth + 30
                glassRadius: height / 2

                RowLayout {
                    id: leftRow
                    anchors.centerIn: parent

                    Workspaces { showContainer: false }
                }
            }

            GlassSurface {
                id: rightBarGlass
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                height: 34
                width: rightRow.implicitWidth + 30
                glassRadius: height / 2

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
                    Battery {
                        percentage: root.batCap
                        charging: (root.batStat === "Charging" || root.batStat === "Full")
                        onAcPower: root.onAcPower
                        batteryStatus: root.batStat
                        powerSaverMode: root.perfMode === "power-saver"
                    }
                    // El ControlCenter vuelve a usar el logo original de Arch.
                    // La accion sigue siendo abrir/cerrar el ControlCenter;
                    // no depende del estado de Focus ni de las notificaciones.
                    MouseArea {
                        id: controlCenterToggleArea
                        width: 26
                        height: 26
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.isNotifOpen = !root.isNotifOpen

                        Text {
                            anchors.centerIn: parent
                            text: ""
                            color: Theme.white
                            font.family: Theme.fontIcons
                            font.pixelSize: 22
                        }
                    }
                }
            }
        }

        PanelWindow {
            id: popupMenuWindow
            screen: root.primaryUiScreen
            anchors { top: true; right: true }
            WlrLayershell.layer: WlrLayershell.Overlay
            implicitHeight: root.isMenuVisible ? 90 : 0
            implicitWidth: 200
            margins { right: root.activeMenuOffset }
            exclusiveZone: 0
            color: "transparent"

            /*
             * SysMenu is a reusable GlassSurface, not a PanelWindow itself.
             * The parent window therefore owns the backdrop blur request.
             *
             * A separate geometry target is used instead of the animated
             * SysMenu surface, keeping the blur region stable while the menu
             * fades/scales in and out.
             */
            BackgroundEffect.blurRegion: Glass.blurEnabled ? sysMenuBlurRegion : null

            Item {
                id: sysMenuBlurTarget
                anchors.fill: parent
            }

            Region {
                id: sysMenuBlurRegion
                item: sysMenuBlurTarget
                radius: 12
            }

            SysMenu {
                id: sysMenu
                title: root.activeMenuTitle
                info1: root.activeMenuInfo1
                info2: root.activeMenuInfo2
                accent: root.activeMenuAccent
                isOpen: root.isMenuOpen
            }
        }

        // --- VENTANA DEL MENÚ DEL PORTAPAPELES ---
        PanelWindow {
            id: clipMenuWindow
            screen: root.primaryUiScreen
            anchors { top: true; right: true }
            WlrLayershell.layer: WlrLayershell.Overlay
            implicitWidth: 260
            implicitHeight: root.isClipMenuOpen
                ? Math.min(320, 63 + (root.clipboardModel.count * 32))
                : 0
            margins { right: 22 } // Alineado bajo el icono
            exclusiveZone: 0
            color: "transparent"

            BackgroundEffect.blurRegion: Glass.blurEnabled ? clipBlurRegion : null

            Region {
                id: clipBlurRegion
                item: clipGlass
                radius: clipGlass.radius
            }

            GlassSurface {
                id: clipGlass
                anchors.fill: parent
                glassRadius: 12
                clip: true

                opacity: root.isClipMenuOpen ? 1.0 : 0.0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                transform: Translate {
                    y: root.isClipMenuOpen ? 0 : -10
                    Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                }

                HoverHandler {
                    onHoveredChanged: {
                        if (hovered) {
                            root.isClipMenuHovered = true;
                            clipHideTimer.stop();
                        } else {
                            root.isClipMenuHovered = false;
                            clipHideTimer.start();
                        }
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 20

                        Text {
                            text: "Clipboard"
                            color: Theme.white
                            font.family: Theme.fontMain
                            font.pixelSize: 12
                            font.bold: true
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            Layout.preferredWidth: 55
                            Layout.preferredHeight: 18
                            radius: 4
                            color: clearMouse.containsMouse ? Qt.alpha(Theme.red, 0.2) : "transparent"
                            border.color: clearMouse.containsMouse ? Theme.red : Qt.alpha(Theme.white, 0.2)
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: "Clear"
                                color: clearMouse.containsMouse ? Theme.red : Theme.grey1
                                font.pixelSize: 9
                            }

                            MouseArea {
                                id: clearMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: root.clipboardModel.count > 0
                                onClicked: root.clearClipHistory()
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Qt.alpha(Theme.white, 0.1)
                    }

                    Text {
                        visible: root.clipboardModel.count === 0
                        text: "No clipboard history"
                        color: Theme.grey1
                        font.family: Theme.fontMain
                        font.pixelSize: 10
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                    }

                    ListView {
                        id: clipboardList
                        visible: root.clipboardModel.count > 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 4
                        model: root.clipboardModel

                        delegate: Rectangle {
                            required property string clipId
                            required property string clipContent

                            width: ListView.view.width
                            height: 28
                            radius: 6
                            color: rowMouse.containsMouse ? Qt.alpha(Theme.white, 0.10) : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                spacing: 6

                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    Text {
                                        anchors.fill: parent
                                        anchors.rightMargin: 4
                                        text: clipContent
                                        color: Theme.white
                                        font.family: Theme.fontMain
                                        font.pixelSize: 11
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }

                                    MouseArea {
                                        id: rowMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.copyClipItem(clipId)
                                    }
                                }

                                Item {
                                    Layout.preferredWidth: 18
                                    Layout.preferredHeight: 18

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰅖"
                                        font.family: Theme.fontIcons
                                        font.pixelSize: 12
                                        color: delArea.containsMouse ? Theme.red : Theme.grey1
                                    }

                                    MouseArea {
                                        id: delArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                      
   cursorShape: Qt.PointingHandCursor
                                        onClicked: root.deleteClipItem(clipId)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        DynamicIsland {
            id: islandWidget

            // Notifications are now a native optional DynamicIsland tab.
            // DynamicIsland owns the carousel, hover lifecycle and closing
            // behaviour; shell.qml only supplies the shared data/actions.
            notificationModel: sharedNotifModel
            pendingNotificationCount: root.notifCount
            hasUnreadNotifications: root.hasUnread
            focusModeActive: root.dnd

            onRemoveNotificationRequested: function(notificationId) {
                root.removeNotification(notificationId)
            }

            onClearNotificationsRequested: {
                root.hasUnread = false
                root.clearNotifications()
            }

            onNotificationsViewed: root.hasUnread = false

            // Keep the real Dynamic Island permanently in its normal Wayland
            // position. Moving the PanelWindow itself to -500 while a
            // notification was visible made Hyprland animate it back down from
            // the top edge when the notification finished.
            topMargin: root.primaryUiScreen
                && root.primaryUiScreen.name === "HDMI-A-1"
                ? -32
                : -38

            // Hide only the QQuickItem tree inside the already-mapped
            // PanelWindow. The layer-shell surface itself never moves, unmaps
            // or changes margin, so Hyprland has nothing to animate back from
            // the top edge when the notification finishes.
            contentItem.opacity: islandNotification.notificationActive ? 0 : 1
            contentItem.enabled: !islandNotification.notificationActive

            isFullscreen: root.isFullscreen
            isBtConnected: {
                var dev = root.btDev ? root.btDev.toLowerCase().trim() : "";
                return root.btStat === "on" && dev !== "" && dev !== "disconnected" && dev !== "none" && dev !== "null" && dev !== "off";
            }
        }

        // Keep this surface declared after DynamicIsland so, while its input
        // mask is active, it is the topmost layer-shell surface in this slot.
        // When inactive its mask is empty and input falls through to the real
        // island underneath.
        IslandNotification {
            id: islandNotification
            screen: root.primaryUiScreen

            // Exactly the same resting position as DynamicIsland, including
            // the clamshell HDMI adjustment.
            topMargin: root.primaryUiScreen
                && root.primaryUiScreen.name === "HDMI-A-1"
                ? -32
                : -38

            // The X removes every notification currently grouped in the
            // transient island stack. Use the same serialized FIFO queue as
            // the Notification Center and the persistent island tab.
            onRemoveManyRequested: function(notificationIds) {
                if (!notificationIds || notificationIds.length === 0)
                    return

                for (var i = 0; i < notificationIds.length; ++i) {
                    var id = Number(notificationIds[i])
                    if (!isNaN(id) && id >= 0)
                        root.sendNotifCommand("REMOVE|" + id)
                }
            }
        }
    }

    // --- ZONA DE GATILLO SUPERIOR (detecta el ratón en una franja central del borde superior) ---
    PanelWindow {
        id: topTriggerZone
        screen: root.primaryUiScreen
        // Sin left/right: se centra horizontalmente sola (igual que la isla fantasma),
        // formando una franja ancha en la zona superior-central, no un punto único
        // ni todo el borde de la pantalla.
        anchors { top: true }
        implicitWidth: 460
        implicitHeight: 14
        color: "transparent"
        WlrLayershell.layer: WlrLayershell.Top
        exclusiveZone: 0
        visible: root.isFullscreen

        MouseArea {
            id: topTriggerArea
            anchors.fill: parent
            hoverEnabled: true
            onEntered: {
                root.isTopHovered = true
                topHideTimer.stop()
            }
            onExited: topHideTimer.start()
        }
    }

    // One-shot debounce only used while the pointer travels between the
    // invisible top trigger and the clock+battery pill. It does not poll.
    Timer {
        id: topHideTimer
        interval: 180
        repeat: false
        onTriggered: {
            if (!topTriggerArea.containsMouse && !fsGhostMouseArea.containsMouse) {
                root.isTopHovered = false
            }
        }
    }

    // Do not carry the fullscreen reveal state into normal desktop mode.
    onIsFullscreenChanged: {
        if (!isFullscreen) {
            isTopHovered = false
            topHideTimer.stop()
        }
    }

    // --- WIDGET FULLSCREEN: solo reloj + batería ---
    // It is a separate, non-expandable pill; the real Dynamic Island stays
    // hidden in fullscreen through DynamicIsland.isFullscreen.
    PanelWindow {
        id: fullscreenGhostIsland
        screen: root.primaryUiScreen
        anchors { top: true }

        WlrLayershell.layer: WlrLayershell.Overlay
        exclusiveZone: 0
        color: "transparent"

        // Important: do not keep the pill permanently mapped and merely move
        // it above the screen. It exists visually only while the pointer is in
        // the top-centre reveal area (or over the pill itself).
        visible: root.isFullscreen && root.isTopHovered && !islandNotification.notificationActive

        implicitWidth: fsGhostLayout.implicitWidth + 36
        implicitHeight: 32

        // Same resting position as the normal island. Keep the clamshell HDMI
        // adjustment in sync with DynamicIsland.topMargin above.
        margins {
            top: root.primaryUiScreen
                && root.primaryUiScreen.name === "HDMI-A-1"
                ? -32
                : -38
        }

        BackgroundEffect.blurRegion: Glass.blurEnabled ? ghostBlurRegion : null

        Region {
            id: ghostBlurRegion
            item: ghostGlass
            radius: ghostGlass.radius
        }

        GlassSurface {
            id: ghostGlass
            anchors.fill: parent
            glassRadius: height / 2

            // Hovering the pill keeps it visible, but never opens or expands it.
            MouseArea {
                id: fsGhostMouseArea
                anchors.fill: parent
                hoverEnabled: true
                onEntered: {
                    root.isTopHovered = true
                    topHideTimer.stop()
                }
                onExited: topHideTimer.start()
            }

            RowLayout {
                id: fsGhostLayout
                anchors.centerIn: parent
                spacing: 10

                Text {
                    id: fsGhostClockText
                    color: Theme.white
                    font.family: Theme.fontMain
                    font.pixelSize: 14
                    font.bold: true
                }

                Battery {
                    percentage: root.batCap
                    charging: (root.batStat === "Charging" || root.batStat === "Full")
                    onAcPower: root.onAcPower
                    batteryStatus: root.batStat
                    powerSaverMode: root.perfMode === "power-saver"
                }
            }
        }

        Timer {
            interval: 2000
            running: root.isFullscreen && root.isTopHovered
            repeat: true
            triggeredOnStart: true
            onTriggered: {
                var timeStr = new Date().toLocaleTimeString(Qt.locale("en_US"), "hh:mm A");
                if (fsGhostClockText.text !== timeStr) fsGhostClockText.text = timeStr;
            }
        }
    }

    PanelWindow {
        id: cavaWindow
        screen: root.primaryUiScreen
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
        screen: root.primaryUiScreen
    }

    GlobalShortcut {
        name: "wallpaper_menu"
        onPressed: { wallCarouselWidget.toggle() }
    }

    // --- ZONA DE GATILLO DEL DOCK ---
    PanelWindow {
        id: dockTriggerZone
        screen: root.primaryUiScreen
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
        screen: root.primaryUiScreen
        anchors { bottom: true }
        margins { bottom: root.bottomGap }

        WlrLayershell.layer: WlrLayershell.Overlay
        exclusiveZone: 0
        color: "transparent"

        // Same position/behaviour as before, just a little larger visually.
        implicitWidth: dockLayout.implicitWidth + 34
        implicitHeight: 66

        // IMPORTANT: a transparent PanelWindow is still an input surface.
        // When the dock is hidden, use an empty input mask so clicks pass
        // straight through to the application underneath. When visible, only
        // the actual dock surface is clickable.
        mask: dockVisual.showDock ? dockInputRegion : emptyDockInputRegion

        Region {
            id: dockInputRegion
            item: dockGlass
            radius: dockGlass.radius
        }

        Region {
            id: emptyDockInputRegion
        }

        BackgroundEffect.blurRegion: Glass.blurEnabled ? dockBlurRegion : null

        Region {
            id: dockBlurRegion
            item: dockGlass
            radius: dockGlass.radius
        }

        Item {
            id: dockVisual
            anchors.fill: parent

            property bool showDock: root.isMacosMode || root.isWorkspaceEmpty || root.isDockHovered

            opacity: showDock ? 1 : 0
            visible: opacity > 0

            transform: Translate {
                y: dockVisual.showDock ? 0 : 25
                Behavior on y {
                    NumberAnimation { duration: 400; easing.type: Easing.OutQuint }
                }
            }

            Behavior on opacity {
                NumberAnimation { duration: 300; easing.type: Easing.OutQuint }
            }

            GlassSurface {
                id: dockGlass
                anchors.fill: parent
                glassRadius: 18

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
                    spacing: 9

                    Repeater {
                        model: DockConfig.apps

                        DockItem {
                            required property var modelData
                            app: modelData

                            onActivated: function(app) {
                                // Internal action: reuse the Launcher instance that is
                                // already alive in this ShellRoot. No second launcher
                                // process/window is created.
                                if (app.action === "launcher") {
                                    mainLauncher.toggle()
                                    return
                                }

                                if (app.command && app.command.length > 0) {
                                    dockLauncherProc.command = [
                                        "bash",
                                        "-c",
                                        app.command + " & disown"
                                    ]
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
        screen: root.primaryUiScreen
    }
}
