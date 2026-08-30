import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import ".."

PanelWindow {
    id: ncWindow

    /*
     * Notification Center / Control Center
     * Primera versión inspirada en macOS Tahoe.
     *
     * Esta versión cambia principalmente el frontend y conserva la interfaz
     * que shell.qml ya utiliza para Wi-Fi, Bluetooth, Airplane, Caffeine,
     * Focus/DND y notificaciones.
     */

    // ---------------------------------------------------------------------
    // API pública que ya consume shell.qml
    // ---------------------------------------------------------------------

    property bool visible_state: false
    property bool isReallyVisible: false

    // Configurable from shell.qml so the panel can use different
    // top/right offsets on the external monitor in clamshell mode.
    property int panelTopMargin: 2
    property int panelRightMargin: 12

    property bool dndState: false
    property bool wifiState: false
    property bool btState: false
    property bool airplaneState: false
    property bool caffeineState: false
    property bool nightLightState: false
    property int nightLightTemperature: 4000
    property bool nightLightTemperatureOpen: false

    property ListModel modelData

    signal requestClose()
    signal toggleDndRequested()
    signal clearRequested()

    signal toggleWifiRequested()
    signal toggleBtRequested()
    signal toggleAirplaneRequested()
    signal toggleCaffeineRequested()
    signal toggleNightLightRequested()
    signal setNightLightTemperatureRequested(int temperature)

    // Se conserva por compatibilidad con shell.qml aunque esta primera
    // versión ya no muestra un botón de power.
    signal powerRequested()

    // ---------------------------------------------------------------------
    // Estado UI
    // ---------------------------------------------------------------------

    property bool wifiPending: false
    property bool btPending: false
    property bool airplanePending: false
    property bool caffeinePending: false

    // Mes/año mostrado por el calendario compacto.
    // Se mantienen separados de "today" para poder navegar entre meses.
    property int displayMonth: new Date().getMonth()
    property int displayYear: new Date().getFullYear()

    // Calendar / agenda state.
    // The monthly view is the default; selecting a day opens the daily agenda.
    property bool agendaVisible: false
    property var selectedDateObj: new Date()
    property var selectedEvents: []
    property var notionEventsData: []

    readonly property int panelWidth: 420
    readonly property int panelMargin: 12
    readonly property int tileGap: 12
    readonly property int topTileHeight: 78
    readonly property int calendarHeight: topTileHeight * 2 + tileGap
    readonly property int smallButtonSize: 62
    readonly property int notificationHeight: 86
    // Compact horizontal Volume/Brightness controls. They deliberately use
    // almost the same height as the "Clear All" pill so this row feels
    // lighter than the large connectivity tiles above it.
    readonly property int mediaSliderHeight: 34
    readonly property int mediaControlsHeight: mediaSliderHeight

    readonly property int notificationCount:
        ncWindow.modelData ? ncWindow.modelData.count : 0

    // Height occupied before the notifications section. Besides the original
    // top grid, this now includes the Volume/Brightness controls and the gap
    // that separates both blocks.
    readonly property int topControlsHeight:
        calendarHeight + tileGap + topTileHeight
        + tileGap + mediaControlsHeight

    // ---------------------------------------------------------------------
    // Helpers / backend bridge
    // ---------------------------------------------------------------------

    Process {
        id: ncCommand
    }

    function execCmd(cmd) {
        ncCommand.command = ["bash", "-c", cmd]
        ncCommand.running = true
    }

    function setNightLightTemperatureFromX(x, width) {
        if (width <= 0)
            return

        var ratio = Math.max(0, Math.min(1, x / width))
        // 100 K steps keep dragging smooth without spawning excessive IPC calls.
        var temperature = Math.round((2500 + ratio * 3500) / 100) * 100
        temperature = Math.max(2500, Math.min(6000, temperature))

        if (temperature !== ncWindow.nightLightTemperature) {
            ncWindow.nightLightTemperature = temperature
            ncWindow.setNightLightTemperatureRequested(temperature)
        }
    }

    // -----------------------------------------------------------------
    // Calendar backend (restored from the previous .bak implementation)
    // -----------------------------------------------------------------

    function sameCalendarDay(a, b) {
        return a.getFullYear() === b.getFullYear()
            && a.getMonth() === b.getMonth()
            && a.getDate() === b.getDate()
    }

    function getEventsForDate(date) {
        if (!notionEventsData || notionEventsData.length === 0)
            return []

        // Match the exact ISO date produced by notion_sync.py.
        // This prevents "2 Sep" from matching "12 Sep", "6 Aug" from
        // matching "26 Aug", etc.
        var dateKey = Qt.formatDate(date, "yyyy-MM-dd")

        for (var i = 0; i < notionEventsData.length; i++) {
            if ((notionEventsData[i].date_key || "") === dateKey)
                return notionEventsData[i].events || []
        }

        return []
    }

    function eventStartMinutes(eventObject) {
        var value = (eventObject && eventObject.time) ? String(eventObject.time) : ""
        var match = value.match(/(\d{1,2}):(\d{2})\s*(AM|PM)?/i)

        if (!match)
            return 24 * 60

        var hours = parseInt(match[1])
        var minutes = parseInt(match[2])
        var suffix = match[3] ? match[3].toUpperCase() : ""

        if (suffix === "PM" && hours < 12)
            hours += 12
        else if (suffix === "AM" && hours === 12)
            hours = 0

        return hours * 60 + minutes
    }

    function sortedEventsForDate(date) {
        var events = getEventsForDate(date)
        var copy = []

        for (var i = 0; i < events.length; i++)
            copy.push(events[i])

        copy.sort(function(a, b) {
            var aAllDay = a && String(a.time).toLowerCase() === "all day"
            var bAllDay = b && String(b.time).toLowerCase() === "all day"

            // All-day events always come first.
            if (aAllDay !== bAllDay)
                return aAllDay ? -1 : 1

            // Timed events remain ordered chronologically by start time.
            return eventStartMinutes(a) - eventStartMinutes(b)
        })

        return copy
    }

    function selectAgendaDate(date) {
        selectedDateObj = new Date(
            date.getFullYear(),
            date.getMonth(),
            date.getDate()
        )
        selectedEvents = sortedEventsForDate(selectedDateObj)
        agendaVisible = true
    }

    function goToPreviousAgendaDay() {
        var date = new Date(selectedDateObj)
        date.setDate(date.getDate() - 1)
        selectAgendaDate(date)
    }

    function goToNextAgendaDay() {
        var date = new Date(selectedDateObj)
        date.setDate(date.getDate() + 1)
        selectAgendaDate(date)
    }

    function handleAgendaDateClick() {
        var now = new Date()

        if (sameCalendarDay(selectedDateObj, now)) {
            // On today, clicking the date toggles back to the month view.
            agendaVisible = false
            displayMonth = now.getMonth()
            displayYear = now.getFullYear()
        } else {
            // On any other day, the date label jumps back to today's agenda.
            selectAgendaDate(now)
            displayMonth = now.getMonth()
            displayYear = now.getFullYear()
        }
    }

    Process {
        id: notionSyncProc
        running: ncWindow.visible_state
        command: [
            "bash", "-c",
            "source ~/.config/quickshell/secrets.env 2>/dev/null; " +
            "python3 ~/.config/quickshell/scripts/notion_sync.py; " +
            "cat ~/.cache/qs_notion.json 2>/dev/null || " +
            "echo '{\"header\": \"Not Configured\", \"events\": []}'"
        ]

        stdout: SplitParser {
            onRead: function(data) {
                try {
                    var parsed = JSON.parse(data.trim())
                    ncWindow.notionEventsData = parsed.days || []

                    if (ncWindow.agendaVisible)
                        ncWindow.selectedEvents =
                            ncWindow.sortedEventsForDate(ncWindow.selectedDateObj)
                } catch (e) {
                    console.warn("NotificationCenter: calendar backend parse error:", e)
                }
            }
        }
    }

    // -----------------------------------------------------------------
    // Volume / brightness backend
    // -----------------------------------------------------------------

    property real volumeLevel: 0.0
    property bool volumeMuted: false
    property real brightnessLevel: 0.0
    property bool volumeDragging: false
    property bool brightnessDragging: false
    property bool volumeApplyPending: false
    property bool brightnessApplyPending: false

    function clamp01(value) {
        return Math.max(0.0, Math.min(1.0, value))
    }

    function setVolumePreviewFromX(mouseX, trackWidth) {
        if (trackWidth <= 0)
            return

        volumeLevel = clamp01(mouseX / trackWidth)
    }

    function setBrightnessPreviewFromX(mouseX, trackWidth) {
        if (trackWidth <= 0)
            return

        // Keep a tiny non-zero floor. Many laptop backlights accept 0%, but
        // on some panels that effectively turns the screen completely black.
        brightnessLevel = Math.max(0.01, clamp01(mouseX / trackWidth))
    }

    function applyVolume() {
        if (volumeSetProc.running) {
            volumeApplyPending = true
            return
        }

        volumeApplyPending = false
        volumeSetProc.command = [
            "bash", "-c",
            "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ "
            + volumeLevel.toFixed(3)
            + "; wpctl set-mute @DEFAULT_AUDIO_SINK@ 0"
        ]
        volumeSetProc.running = true
    }

    function applyBrightness() {
        if (brightnessSetProc.running) {
            brightnessApplyPending = true
            return
        }

        brightnessApplyPending = false
        var percent = Math.max(1, Math.min(100, Math.round(brightnessLevel * 100)))
        brightnessSetProc.command = [
            "brightnessctl", "set", percent + "%"
        ]
        brightnessSetProc.running = true
    }

    Process {
        id: volumeSetProc
        onRunningChanged: {
            if (!running && ncWindow.volumeApplyPending)
                Qt.callLater(ncWindow.applyVolume)
        }
    }

    Process {
        id: brightnessSetProc
        onRunningChanged: {
            if (!running && ncWindow.brightnessApplyPending)
                Qt.callLater(ncWindow.applyBrightness)
        }
    }

    Process {
        id: volumeMuteProc
    }

    // Event-driven monitor, deliberately alive only while the Notification
    // Center is open. It performs one initial read and then sleeps until
    // PipeWire/PulseAudio or the kernel backlight emits a change event.
    Process {
        id: mediaControlsMonitor
        running: ncWindow.visible_state
        command: [
            "bash", "-c",
            "LC_ALL=C; " +
            "F=\"${XDG_RUNTIME_DIR:-/tmp}/qs_nc_media_$$\"; " +
            "rm -f \"$F\"; mkfifo \"$F\"; exec 3<>\"$F\"; " +
            "pactl subscribe 2>/dev/null | grep --line-buffered -E '(sink|server)' | while read -r _; do echo SND >&3; done & " +
            "udevadm monitor --subsystem-match=backlight 2>/dev/null | grep --line-buffered 'change' | while read -r _; do echo BRI >&3; done & " +
            "trap 'kill $(jobs -p) 2>/dev/null; rm -f \"$F\"' EXIT; " +
            "read_values() { " +
            "  vf=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || echo 'Volume: 0'); " +
            "  vol=${vf#* }; vol=${vol% \\[MUTED\\]}; " +
            "  [[ \"$vf\" == *MUTED* ]] && muted=1 || muted=0; " +
            "  b_raw=$(brightnessctl -m 2>/dev/null || echo 'backlight,backlight,0,0%'); " +
            "  IFS=, read -r _ _ _ pct _ <<< \"$b_raw\"; bri=${pct%%%}; " +
            "  echo \"$vol;$muted;$bri\"; " +
            "}; " +
            "read_values; while read -r _ <&3; do read_values; done"
        ]

        stdout: SplitParser {
            onRead: function(data) {
                var fields = data.trim().split(";")
                if (fields.length < 3)
                    return

                var newVolume = parseFloat(fields[0])
                var newBrightness = parseFloat(fields[2]) / 100.0

                if (!ncWindow.volumeDragging && !isNaN(newVolume))
                    ncWindow.volumeLevel = ncWindow.clamp01(newVolume)

                ncWindow.volumeMuted = fields[1] === "1"

                if (!ncWindow.brightnessDragging && !isNaN(newBrightness))
                    ncWindow.brightnessLevel = ncWindow.clamp01(newBrightness)
            }
        }
    }

    // These timers only exist while the user is actively dragging a slider.
    // They make the controls feel live without introducing periodic work in
    // the background when the panel is idle or closed.
    Timer {
        id: volumeDragApplyTimer
        interval: 45
        repeat: true
        running: ncWindow.volumeDragging
        onTriggered: ncWindow.applyVolume()
    }

    Timer {
        id: brightnessDragApplyTimer
        interval: 45
        repeat: true
        running: ncWindow.brightnessDragging
        onTriggered: ncWindow.applyBrightness()
    }

    onWifiStateChanged: wifiPending = false
    onBtStateChanged: btPending = false
    onAirplaneStateChanged: airplanePending = false
    onCaffeineStateChanged: caffeinePending = false

    Timer {
        id: wifiTimer
        interval: 3000
        onTriggered: ncWindow.wifiPending = false
    }

    Timer {
        id: btTimer
        interval: 3000
        onTriggered: ncWindow.btPending = false
    }

    Timer {
        id: airplaneTimer
        interval: 3000
        onTriggered: ncWindow.airplanePending = false
    }

    Timer {
        id: caffeineTimer
        interval: 3000
        onTriggered: ncWindow.caffeinePending = false
    }

    // ---------------------------------------------------------------------
    // Window
    // ---------------------------------------------------------------------

    screen: Quickshell.screens[0]

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    exclusiveZone: 0
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus:
        visible_state ? WlrLayershell.OnDemand : WlrLayershell.None

    visible: isReallyVisible
    color: "transparent"

    /*
     * Un único backdrop blur para la zona visual del Control Center.
     * Las tarjetas internas usan GlassSurface para tint/border/highlight.
     */
    BackgroundEffect.blurRegion:
        Glass.blurEnabled ? controlCenterBlurRegion : null

    Region {
        id: controlCenterBlurRegion

        x: Math.round(
            ncWindow.width
            - animationContainer.anchors.rightMargin
            - contentColumn.width
            + panelSlide.x
        )

        y: 0

        width: Math.round(contentColumn.width)

        height: Math.round(
            Math.min(
                contentColumn.height,
                ncWindow.height
            )
        )

        radius: Math.round(Glass.radiusLarge)
    }

    onVisible_stateChanged: {
        if (visible_state) {
            closeTimer.stop()
            isReallyVisible = true
        } else {
            // The temperature slider is transient UI: always collapse it as
            // soon as the Notification Center begins closing.
            nightLightTemperatureOpen = false
            closeTimer.start()
        }
    }

    Timer {
        id: closeTimer
        interval: 350
        onTriggered: isReallyVisible = false
    }

    // Click fuera del panel = cerrar.
    MouseArea {
        anchors.fill: parent
        onClicked: ncWindow.requestClose()
    }

    // ---------------------------------------------------------------------
    // Animated right-side container
    // ---------------------------------------------------------------------

    Item {
        id: animationContainer

        width: ncWindow.panelWidth
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.rightMargin: ncWindow.panelRightMargin
        anchors.topMargin: ncWindow.panelTopMargin

        transform: Translate {
            id: panelSlide

            x: ncWindow.visible_state ? 0 : ncWindow.panelWidth + 30

            Behavior on x {
                NumberAnimation {
                    duration: 350
                    easing.type: Easing.OutQuart
                }
            }
        }

        opacity: ncWindow.visible_state ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: 230
            }
        }

        Column {
            id: contentColumn

            width: parent.width
            anchors.right: parent.right
            spacing: ncWindow.tileGap

            // =============================================================
            // TOP CONTROLS
            // Left:  Wi-Fi / Bluetooth / Caffeine
            // Right: Calendar / Airplane Mode
            // =============================================================

            Row {
                id: topRow

                width: parent.width
                height: ncWindow.calendarHeight + ncWindow.tileGap + ncWindow.topTileHeight
                spacing: ncWindow.tileGap

                // ---------------------------------------------------------
                // LEFT COLUMN: Wi-Fi / Bluetooth / Caffeine
                // ---------------------------------------------------------

                Column {
                    width: (parent.width - ncWindow.tileGap) / 2
                    height: parent.height
                    spacing: ncWindow.tileGap

                    GlassSurface {
                        id: wifiTile

                        width: parent.width
                        height: ncWindow.topTileHeight
                        glassRadius: 22
                        glassOpacity:
                            ncWindow.wifiPending ? 0.45
                            : wifiMouse.containsMouse ? 0.45
                            : 0.34

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 12
                            spacing: 12

                            Item {
                                width: 46
                                height: parent.height

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 42
                                    height: 42
                                    radius: 21

                                    color:
                                        ncWindow.wifiPending
                                        ? Qt.alpha(Theme.white, 0.16)
                                        : ncWindow.wifiState
                                          ? Theme.white
                                          : Qt.alpha(Theme.white, 0.13)

                                    Text {
                                        anchors.centerIn: parent
                                        text: ""
                                        font.family: Theme.fontIcons
                                        font.pixelSize: 18
                                        color: ncWindow.wifiState && !ncWindow.wifiPending ? Theme.bg0 : Theme.white
                                    }
                                }
                            }

                            Column {
                                width: parent.width - 58
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Text {
                                    width: parent.width
                                    text: "Wi-Fi"
                                    color: Theme.white
                                    font.family: Theme.fontMain
                                    font.pixelSize: 15
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text:
                                        ncWindow.wifiPending ? "Changing…"
                                        : ncWindow.wifiState ? "On" : "Off"
                                    color: Qt.alpha(Theme.white, 0.60)
                                    font.family: Theme.fontMain
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        MouseArea {
                            id: wifiMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            onClicked: {
                                if (!ncWindow.wifiPending) {
                                    ncWindow.wifiPending = true
                                    wifiTimer.restart()
                                    ncWindow.toggleWifiRequested()
                                }
                            }
                        }
                    }

                    GlassSurface {
                        id: bluetoothTile

                        width: parent.width
                        height: ncWindow.topTileHeight
                        glassRadius: 22
                        glassOpacity:
                            ncWindow.btPending ? 0.45
                            : btMouse.containsMouse ? 0.45
                            : 0.34

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 12
                            spacing: 12

                            Item {
                                width: 46
                                height: parent.height

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 42
                                    height: 42
                                    radius: 21

                                    color:
                                        ncWindow.btPending
                                        ? Qt.alpha(Theme.white, 0.16)
                                        : ncWindow.btState
                                          ? Theme.white
                                          : Qt.alpha(Theme.white, 0.13)

                                    Text {
                                        anchors.centerIn: parent
                                        text: ""
                                        font.family: Theme.fontIcons
                                        font.pixelSize: 18
                                        color: ncWindow.btState && !ncWindow.btPending ? Theme.bg0 : Theme.white
                                    }
                                }
                            }

                            Column {
                                width: parent.width - 58
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Text {
                                    width: parent.width
                                    text: "Bluetooth"
                                    color: Theme.white
                                    font.family: Theme.fontMain
                                    font.pixelSize: 14
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text:
                                        ncWindow.btPending ? "Changing…"
                                        : ncWindow.btState ? "On" : "Off"
                                    color: Qt.alpha(Theme.white, 0.60)
                                    font.family: Theme.fontMain
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        MouseArea {
                            id: btMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            onClicked: {
                                if (!ncWindow.btPending) {
                                    ncWindow.btPending = true
                                    btTimer.restart()
                                    ncWindow.toggleBtRequested()
                                }
                            }
                        }
                    }

                    GlassSurface {
                        id: caffeineTile

                        width: parent.width
                        height: ncWindow.topTileHeight
                        glassRadius: 22
                        glassOpacity:
                            ncWindow.caffeinePending ? 0.45
                            : caffeineMouse.containsMouse ? 0.45
                            : 0.34

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 12
                            spacing: 12

                            Item {
                                width: 46
                                height: parent.height

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 42
                                    height: 42
                                    radius: 21

                                    color:
                                        ncWindow.caffeinePending
                                        ? Qt.alpha(Theme.white, 0.16)
                                        : ncWindow.caffeineState
                                          ? Theme.white
                                          : Qt.alpha(Theme.white, 0.13)

                                    Text {
                                        anchors.centerIn: parent
                                        text: ncWindow.caffeineState ? "" : ""
                                        font.family: Theme.fontIcons
                                        font.pixelSize: 18
                                        color:
                                            ncWindow.caffeineState && !ncWindow.caffeinePending
                                            ? Theme.bg0
                                            : Theme.white
                                    }
                                }
                            }

                            Column {
                                width: parent.width - 58
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Text {
                                    width: parent.width
                                    text: "Caffeine"
                                    color: Theme.white
                                    font.family: Theme.fontMain
                                    font.pixelSize: 14
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text:
                                        ncWindow.caffeinePending ? "Changing…"
                                        : ncWindow.caffeineState ? "On" : "Off"
                                    color: Qt.alpha(Theme.white, 0.60)
                                    font.family: Theme.fontMain
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        MouseArea {
                            id: caffeineMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            onClicked: {
                                if (!ncWindow.caffeinePending) {
                                    ncWindow.caffeinePending = true
                                    caffeineTimer.restart()
                                    ncWindow.toggleCaffeineRequested()
                                }
                            }
                        }
                    }
                }

                // ---------------------------------------------------------
                // RIGHT COLUMN: Calendar / Airplane Mode
                // ---------------------------------------------------------

                Column {
                    width: (parent.width - ncWindow.tileGap) / 2
                    height: parent.height
                    spacing: ncWindow.tileGap

                    GlassSurface {
                        id: calendarTile

                        width: parent.width
                        height: ncWindow.calendarHeight
                        glassRadius: 22
                        glassOpacity: calendarMouse.containsMouse ? 0.42 : 0.34
                        clip: true

                        property date today: new Date()

                        // ---------------- MONTH VIEW ----------------
                        Column {
                            id: monthView
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 5
                            visible: !ncWindow.agendaVisible

                            Item {
                                width: parent.width
                                height: 21

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "󰅁"
                                    color: Qt.alpha(Theme.white, previousMonthMouse.containsMouse ? 1.0 : 0.58)
                                    font.family: Theme.fontIcons
                                    font.pixelSize: 13

                                    MouseArea {
                                        id: previousMonthMouse
                                        anchors.fill: parent
                                        anchors.margins: -5
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor

                                        onClicked: {
                                            if (ncWindow.displayMonth === 0) {
                                                ncWindow.displayMonth = 11
                                                ncWindow.displayYear--
                                            } else {
                                                ncWindow.displayMonth--
                                            }
                                        }
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: Qt.formatDateTime(
                                        new Date(ncWindow.displayYear, ncWindow.displayMonth, 1),
                                        "MMMM yyyy"
                                    )
                                    color: Theme.white
                                    font.family: Theme.fontMain
                                    font.pixelSize: 11
                                    font.bold: true

                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -5
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor

                                        onClicked: {
                                            var now = new Date()
                                            calendarTile.today = now
                                            ncWindow.displayMonth = now.getMonth()
                                            ncWindow.displayYear = now.getFullYear()
                                        }
                                    }
                                }

                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "󰅂"
                                    color: Qt.alpha(Theme.white, nextMonthMouse.containsMouse ? 1.0 : 0.58)
                                    font.family: Theme.fontIcons
                                    font.pixelSize: 13

                                    MouseArea {
                                        id: nextMonthMouse
                                        anchors.fill: parent
                                        anchors.margins: -5
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor

                                        onClicked: {
                                            if (ncWindow.displayMonth === 11) {
                                                ncWindow.displayMonth = 0
                                                ncWindow.displayYear++
                                            } else {
                                                ncWindow.displayMonth++
                                            }
                                        }
                                    }
                                }
                            }

                            DayOfWeekRow {
                                width: parent.width
                                height: 15
                                locale: Qt.locale("en_GB")

                                delegate: Text {
                                    text: model.narrowName
                                    color: Qt.alpha(Theme.white, 0.50)
                                    font.family: Theme.fontMain
                                    font.pixelSize: 8
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }

                            MonthGrid {
                                id: compactMonthGrid
                                width: parent.width
                                height: parent.height - 43
                                month: ncWindow.displayMonth
                                year: ncWindow.displayYear
                                locale: Qt.locale("en_GB")

                                delegate: Item {
                                    implicitWidth: 20
                                    implicitHeight: 18
                                    opacity: model.month === compactMonthGrid.month ? 1 : 0.20

                                    property var dayEvents: ncWindow.getEventsForDate(model.date)
                                    property bool hasEvents: dayEvents.length > 0

                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.verticalCenterOffset: -1
                                        width: 19
                                        height: 19
                                        radius: 9.5
                                        visible: model.today
                                        color: Theme.white
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.verticalCenterOffset: -1
                                        text: model.day
                                        color: model.today
                                               ? Theme.bg0
                                               : Qt.alpha(Theme.white, 0.82)
                                        font.family: Theme.fontMain
                                        font.pixelSize: 8
                                        font.bold: model.today || hasEvents
                                    }

                                    // White dot under every day that contains events.
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 0
                                        width: 2.5
                                        height: 2.5
                                        radius: 1.25
                                        color: model.today ? Theme.bg0 : Theme.white
                                        visible: hasEvents
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor

                                        onClicked: {
                                            ncWindow.selectAgendaDate(model.date)
                                        }
                                    }
                                }
                            }
                        }

                        // ---------------- DAILY AGENDA VIEW ----------------
                        Column {
                            id: agendaView
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 7
                            visible: ncWindow.agendaVisible

                            Item {
                                width: parent.width
                                height: 22

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "󰅁"
                                    color: Qt.alpha(Theme.white, previousDayMouse.containsMouse ? 1.0 : 0.58)
                                    font.family: Theme.fontIcons
                                    font.pixelSize: 13

                                    MouseArea {
                                        id: previousDayMouse
                                        anchors.fill: parent
                                        anchors.margins: -5
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: ncWindow.goToPreviousAgendaDay()
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: Qt.formatDateTime(
                                        ncWindow.selectedDateObj,
                                        "MMMM d, yyyy"
                                    )
                                    color: Theme.white
                                    font.family: Theme.fontMain
                                    font.pixelSize: 10
                                    font.bold: true

                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -5
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: ncWindow.handleAgendaDateClick()
                                    }
                                }

                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "󰅂"
                                    color: Qt.alpha(Theme.white, nextDayMouse.containsMouse ? 1.0 : 0.58)
                                    font.family: Theme.fontIcons
                                    font.pixelSize: 13

                                    MouseArea {
                                        id: nextDayMouse
                                        anchors.fill: parent
                                        anchors.margins: -5
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: ncWindow.goToNextAgendaDay()
                                    }
                                }
                            }

                            Rectangle {
                                width: parent.width
                                height: 1
                                color: Qt.alpha(Theme.white, 0.10)
                            }

                            Text {
                                width: parent.width
                                height: parent.height - 30
                                visible: ncWindow.selectedEvents.length === 0
                                text: "No events this day"
                                color: Qt.alpha(Theme.white, 0.48)
                                font.family: Theme.fontMain
                                font.pixelSize: 9
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            ListView {
                                id: compactAgendaList
                                width: parent.width
                                height: parent.height - 30
                                visible: ncWindow.selectedEvents.length > 0
                                clip: true
                                spacing: 6
                                boundsBehavior: Flickable.StopAtBounds
                                model: ncWindow.selectedEvents

                                delegate: Item {
                                    width: ListView.view.width
                                    height: 30

                                    Row {
                                        anchors.fill: parent
                                        spacing: 8

                                        Text {
                                            width: 54
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.time || ""
                                            color: Theme.white
                                            opacity: 0.68
                                            font.family: Theme.fontMain
                                            font.pixelSize: 7
                                            font.bold: true
                                            wrapMode: Text.Wrap
                                            maximumLineCount: 2
                                            elide: Text.ElideRight
                                        }

                                        Rectangle {
                                            width: 1
                                            height: 20
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: Qt.alpha(Theme.white, 0.14)
                                        }

                                        Text {
                                            width: parent.width - 63
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.title || "Untitled event"
                                            color: Theme.white
                                            font.family: Theme.fontMain
                                            font.pixelSize: 9
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: calendarMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                        }
                    }

                    GlassSurface {
                        id: airplaneTile

                        width: parent.width
                        height: ncWindow.topTileHeight
                        glassRadius: 22
                        glassOpacity:
                            ncWindow.airplanePending ? 0.45
                            : airplaneMouse.containsMouse ? 0.45
                            : 0.34

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 12
                            spacing: 12

                            Item {
                                width: 46
                                height: parent.height

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 42
                                    height: 42
                                    radius: 21

                                    color:
                                        ncWindow.airplanePending
                                        ? Qt.alpha(Theme.white, 0.16)
                                        : ncWindow.airplaneState
                                          ? Theme.white
                                          : Qt.alpha(Theme.white, 0.13)

                                    Text {
                                        anchors.centerIn: parent
                                        text: ""
                                        font.family: Theme.fontIcons
                                        font.pixelSize: 18
                                        color:
                                            ncWindow.airplaneState && !ncWindow.airplanePending
                                            ? Theme.bg0
                                            : Theme.white
                                    }
                                }
                            }

                            Column {
                                width: parent.width - 58
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Text {
                                    width: parent.width
                                    text: "Airplane"
                                    color: Theme.white
                                    font.family: Theme.fontMain
                                    font.pixelSize: 14
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text:
                                        ncWindow.airplanePending ? "Changing…"
                                        : ncWindow.airplaneState ? "On" : "Off"
                                    color: Qt.alpha(Theme.white, 0.60)
                                    font.family: Theme.fontMain
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        MouseArea {
                            id: airplaneMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            onClicked: {
                                if (!ncWindow.airplanePending) {
                                    ncWindow.airplanePending = true
                                    airplaneTimer.restart()
                                    ncWindow.toggleAirplaneRequested()
                                }
                            }
                        }
                    }
                }
            }

            // =============================================================
            // VOLUME / BRIGHTNESS
            // Two compact pills side by side. They keep Dynamic Island's OSD
            // language: icon, thin rounded progress track and percentage.
            // =============================================================

            Row {
                id: mediaControls
                width: parent.width
                height: ncWindow.mediaControlsHeight
                spacing: ncWindow.tileGap

                GlassSurface {
                    id: volumeControl
                    width: (parent.width - ncWindow.tileGap) / 2
                    height: ncWindow.mediaSliderHeight
                    glassRadius: height / 2
                    glassOpacity: volumeControlMouse.containsMouse ? 0.43 : 0.34

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 11
                        anchors.rightMargin: 11
                        spacing: 8

                        Item {
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: parent.height

                            Text {
                                anchors.centerIn: parent
                                text: ncWindow.volumeMuted || ncWindow.volumeLevel <= 0.001
                                      ? "󰝟" : "󰕾"
                                font.family: Theme.fontIcons
                                font.pixelSize: 15
                                color: ncWindow.volumeMuted
                                       ? Qt.alpha(Theme.white, 0.42)
                                       : Theme.white
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!volumeMuteProc.running) {
                                        volumeMuteProc.command = [
                                            "wpctl", "set-mute",
                                            "@DEFAULT_AUDIO_SINK@", "toggle"
                                        ]
                                        volumeMuteProc.running = true
                                    }
                                }
                            }
                        }

                        Item {
                            id: volumeTrackHitbox
                            Layout.fillWidth: true
                            Layout.preferredHeight: parent.height

                            Rectangle {
                                id: volumeTrack
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                height: 5
                                radius: height / 2
                                color: Qt.alpha(Theme.white, 0.20)

                                Rectangle {
                                    height: parent.height
                                    radius: height / 2
                                    width: parent.width * ncWindow.clamp01(ncWindow.volumeLevel)
                                    color: ncWindow.volumeMuted
                                           ? Qt.alpha(Theme.white, 0.42)
                                           : Theme.white

                                    Behavior on width {
                                        enabled: !ncWindow.volumeDragging
                                        NumberAnimation {
                                            duration: 150
                                            easing.type: Easing.OutQuad
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: volumeControlMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor

                                onPressed: function(mouse) {
                                    ncWindow.volumeDragging = true
                                    ncWindow.setVolumePreviewFromX(mouse.x, width)
                                    ncWindow.volumeMuted = false
                                    ncWindow.applyVolume()
                                }

                                onPositionChanged: function(mouse) {
                                    if (pressed)
                                        ncWindow.setVolumePreviewFromX(mouse.x, width)
                                }

                                onReleased: {
                                    ncWindow.applyVolume()
                                    ncWindow.volumeDragging = false
                                }

                                onCanceled: {
                                    ncWindow.applyVolume()
                                    ncWindow.volumeDragging = false
                                }
                            }
                        }

                        Text {
                            text: Math.round(ncWindow.volumeLevel * 100) + "%"
                            color: ncWindow.volumeMuted
                                   ? Qt.alpha(Theme.white, 0.60)
                                   : Theme.white
                            font.family: Theme.fontMain
                            font.pixelSize: 10
                            font.bold: true
                            Layout.minimumWidth: 29
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }

                GlassSurface {
                    id: brightnessControl
                    width: (parent.width - ncWindow.tileGap) / 2
                    height: ncWindow.mediaSliderHeight
                    glassRadius: height / 2
                    glassOpacity: brightnessControlMouse.containsMouse ? 0.43 : 0.34

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 11
                        anchors.rightMargin: 11
                        spacing: 8

                        Item {
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: parent.height

                            Text {
                                anchors.centerIn: parent
                                text: "󰃠"
                                font.family: Theme.fontIcons
                                font.pixelSize: 15
                                color: Theme.white
                            }
                        }

                        Item {
                            id: brightnessTrackHitbox
                            Layout.fillWidth: true
                            Layout.preferredHeight: parent.height

                            Rectangle {
                                id: brightnessTrack
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                height: 5
                                radius: height / 2
                                color: Qt.alpha(Theme.white, 0.20)

                                Rectangle {
                                    height: parent.height
                                    radius: height / 2
                                    width: parent.width * ncWindow.clamp01(ncWindow.brightnessLevel)
                                    color: Theme.white

                                    Behavior on width {
                                        enabled: !ncWindow.brightnessDragging
                                        NumberAnimation {
                                            duration: 150
                                            easing.type: Easing.OutQuad
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: brightnessControlMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor

                                onPressed: function(mouse) {
                                    ncWindow.brightnessDragging = true
                                    ncWindow.setBrightnessPreviewFromX(mouse.x, width)
                                    ncWindow.applyBrightness()
                                }

                                onPositionChanged: function(mouse) {
                                    if (pressed)
                                        ncWindow.setBrightnessPreviewFromX(mouse.x, width)
                                }

                                onReleased: {
                                    ncWindow.applyBrightness()
                                    ncWindow.brightnessDragging = false
                                }

                                onCanceled: {
                                    ncWindow.applyBrightness()
                                    ncWindow.brightnessDragging = false
                                }
                            }
                        }

                        Text {
                            text: Math.round(ncWindow.brightnessLevel * 100) + "%"
                            color: Theme.white
                            font.family: Theme.fontMain
                            font.pixelSize: 10
                            font.bold: true
                            Layout.minimumWidth: 29
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            }

            // =============================================================
            // NOTIFICATIONS
            // Header always visible; when there are no notifications, an
            // empty-state message is shown below it.
            // =============================================================

            Item {
                id: notificationsSection

                readonly property int topInset: 6
                readonly property int bodyHeight:
                    ncWindow.notificationCount > 0
                    ? Math.min(
                          notificationsList.contentHeight,
                          Math.max(
                              120,
                              ncWindow.height
                              - ncWindow.topControlsHeight
                              - topInset
                              - notificationsHeader.height
                              - 40
                          )
                      )
                    : 62

                width: parent.width
                height:
                    topInset
                    + notificationsHeader.height
                    + 8
                    + bodyHeight

                // Header ----------------------------------------------------
                Item {
                    id: notificationsHeader

                    y: notificationsSection.topInset
                    width: parent.width
                    height: 30

                    GlassSurface {
                        id: notificationsTitle

                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 126
                        height: 30
                        glassRadius: 12
                        glassOpacity: 0.28
                        showHighlight: false

                        Text {
                            anchors.centerIn: parent
                            text: "Notifications"
                            color: Qt.alpha(Theme.white, 0.88)
                            font.family: Theme.fontMain
                            font.pixelSize: 13
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    // Focus / Do Not Disturb, moved next to the title.
                    GlassSurface {
                        id: focusButton

                        anchors.left: notificationsTitle.right
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30
                        height: 30
                        glassRadius: 15
                        glassTint:
                            ncWindow.dndState ? Theme.white : Glass.tint
                        glassOpacity:
                            ncWindow.dndState ? 0.92
                            : focusMouse.containsMouse ? 0.46
                            : 0.34
                        showHighlight: false

                        Text {
                            anchors.centerIn: parent
                            text: ncWindow.dndState ? "󰂛" : "󰂚"
                            font.family: Theme.fontIcons
                            font.pixelSize: 15
                            color: ncWindow.dndState ? Theme.bg0 : Theme.white
                        }

                        MouseArea {
                            id: focusMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ncWindow.toggleDndRequested()
                        }
                    }

                    // Night Light / blue-light filter. A secondary click or
                    // long press expands this same pill in-place, keeping the
                    // temperature control in the header instead of covering
                    // the panel content.
                    GlassSurface {
                        id: nightLightButton

                        anchors.left: focusButton.right
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: ncWindow.nightLightTemperatureOpen ? 154 : 30
                        height: 30
                        glassRadius: 15
                        glassTint:
                            ncWindow.nightLightState ? "#ffd38a" : Glass.tint
                        glassOpacity:
                            ncWindow.nightLightState ? 0.92
                            : nightLightToggleMouse.containsMouse ? 0.46
                            : 0.34
                        showHighlight: false
                        clip: true

                        Behavior on width {
                            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                        }

                        // The icon remains the normal left-click toggle.
                        Item {
                            id: nightLightToggleArea
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 30

                            Text {
                                anchors.centerIn: parent
                                text: ncWindow.nightLightState ? "󰖔" : "󰖙"
                                font.family: Theme.fontIcons
                                font.pixelSize: 15
                                color: ncWindow.nightLightState ? Theme.bg0 : Theme.white
                            }

                            MouseArea {
                                id: nightLightToggleMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                property bool longPressHandled: false

                                onPressed: longPressHandled = false

                                onClicked: function(mouse) {
                                    if (longPressHandled) {
                                        longPressHandled = false
                                        return
                                    }

                                    if (mouse.button === Qt.RightButton) {
                                        ncWindow.nightLightTemperatureOpen =
                                            !ncWindow.nightLightTemperatureOpen
                                    } else {
                                        ncWindow.toggleNightLightRequested()
                                    }
                                }

                                onPressAndHold: {
                                    longPressHandled = true
                                    ncWindow.nightLightTemperatureOpen = true
                                }
                            }
                        }

                        // Inline temperature slider, only revealed as the pill
                        // grows. Moving it still activates Night Light if needed.
                        Item {
                            anchors.left: nightLightToggleArea.right
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            visible: ncWindow.nightLightTemperatureOpen
                            opacity: ncWindow.nightLightTemperatureOpen ? 1 : 0

                            Behavior on opacity {
                                NumberAnimation { duration: 120 }
                            }

                            Item {
                                id: inlineNightLightTrackHitbox
                                anchors.left: parent.left
                                anchors.leftMargin: 5
                                anchors.verticalCenter: parent.verticalCenter
                                width: 70
                                height: 24

                                Rectangle {
                                    id: inlineNightLightTrack
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 5
                                    radius: height / 2
                                    color: ncWindow.nightLightState
                                        ? Qt.alpha(Theme.bg0, 0.25)
                                        : Qt.alpha(Theme.white, 0.20)

                                    Rectangle {
                                        height: parent.height
                                        radius: height / 2
                                        width: parent.width *
                                            ((ncWindow.nightLightTemperature - 2500) / 3500)
                                        color: ncWindow.nightLightState
                                            ? Qt.alpha(Theme.bg0, 0.72)
                                            : "#ffd38a"
                                    }

                                    Rectangle {
                                        width: 11
                                        height: 11
                                        radius: width / 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: ncWindow.nightLightState ? Theme.bg0 : Theme.white
                                        x: Math.max(0, Math.min(parent.width - width,
                                            parent.width *
                                            ((ncWindow.nightLightTemperature - 2500) / 3500)
                                            - width / 2))
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onPressed: function(mouse) {
                                        ncWindow.setNightLightTemperatureFromX(mouse.x, width)
                                    }
                                    onPositionChanged: function(mouse) {
                                        if (pressed)
                                            ncWindow.setNightLightTemperatureFromX(mouse.x, width)
                                    }
                                }
                            }

                            Text {
                                anchors.left: inlineNightLightTrackHitbox.right
                                anchors.leftMargin: 6
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: ncWindow.nightLightTemperature + "K"
                                color: ncWindow.nightLightState ? Theme.bg0 : "#ffd38a"
                                font.family: Theme.fontMain
                                font.pixelSize: 10
                                font.bold: true
                                horizontalAlignment: Text.AlignRight
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    GlassSurface {
                        id: clearAllButton

                        readonly property bool hasNotifications:
                            ncWindow.notificationCount > 0

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 82
                        height: 30
                        glassRadius: 15
                        glassOpacity:
                            hasNotifications
                            ? (clearMouse.containsMouse ? 0.48 : 0.34)
                            : 0.18
                        showHighlight: false
                        opacity: hasNotifications ? 1.0 : 0.62

                        Row {
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Clear All"
                                font.family: Theme.fontMain
                                font.pixelSize: 11
                                font.bold: true
                                color:
                                    clearAllButton.hasNotifications
                                    ? Theme.white
                                    : Qt.alpha(Theme.white, 0.45)
                            }
                        }

                        MouseArea {
                            id: clearMouse
                            anchors.fill: parent
                            hoverEnabled: clearAllButton.hasNotifications
                            cursorShape:
                                clearAllButton.hasNotifications
                                ? Qt.PointingHandCursor
                                : Qt.ArrowCursor
                            onClicked: {
                                if (clearAllButton.hasNotifications)
                                    ncWindow.clearRequested()
                            }
                        }
                    }
                }

                Text {
                    id: emptyNotificationsText

                    anchors.top: notificationsHeader.bottom
                    anchors.topMargin: 8
                    width: parent.width
                    height: notificationsSection.bodyHeight
                    visible: ncWindow.notificationCount === 0

                    text: "No new notifications"
                    color: Qt.alpha(Theme.white, 0.46)
                    font.family: Theme.fontMain
                    font.pixelSize: 13
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                ListView {
                    id: notificationsList

                    anchors.top: notificationsHeader.bottom
                    anchors.topMargin: 8
                    width: parent.width

                    height: notificationsSection.bodyHeight
                    visible: ncWindow.notificationCount > 0

                    model: ncWindow.modelData
                    spacing: 9
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: GlassSurface {
                        id: notificationPopup

                        // IMPORTANT:
                        // Do not declare `required property int index` here.
                        // Doing so changes delegate role injection in QML and
                        // breaks the existing `model.<role>` accesses used by
                        // the notification daemon model.
                        width: ListView.view.width
                        height: ncWindow.notificationHeight
                        glassRadius: 20
                        showHighlight: false

                        glassTint:
                            model.urgency === 2
                            ? Theme.red
                            : Glass.tint

                        glassOpacity:
                            model.urgency === 2
                            ? 0.24
                            : notificationMouse.containsMouse ? 0.46 : 0.36

                        MouseArea {
                            id: notificationMouse

                            anchors.fill: parent
                            z: 0
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            onClicked: {
                                ncWindow.requestClose()

                                ncWindow.execCmd(
                                    "echo 'ACTION|"
                                    + model.id
                                    + "|default' > /tmp/qs_notif_cmd"
                                )

                                ncWindow.execCmd(
                                    "echo 'REMOVE|"
                                    + model.id
                                    + "' > /tmp/qs_notif_cmd"
                                )
                            }
                        }

                        RowLayout {
                            z: 1
                            anchors.fill: parent
                            anchors.leftMargin: 13
                            anchors.rightMargin: 11
                            anchors.topMargin: 10
                            anchors.bottomMargin: 10
                            spacing: 11

                            // Application icon --------------------------------
                            Item {
                                Layout.preferredWidth: 42
                                Layout.preferredHeight: 42

                                Image {
                                    id: rawNotificationIcon
                                    anchors.fill: parent

                                    source:
                                        model.icon
                                        ? (
                                            String(model.icon).startsWith("/")
                                            ? "file://" + model.icon
                                            : "image://icon/" + model.icon
                                          )
                                        : ""

                                    fillMode: Image.PreserveAspectCrop
                                    visible: false
                                }

                                Rectangle {
                                    id: notificationIconMask
                                    anchors.fill: parent
                                    radius: 12
                                    visible: false
                                }

                                OpacityMask {
                                    anchors.fill: parent
                                    source: rawNotificationIcon
                                    maskSource: notificationIconMask
                                    visible: rawNotificationIcon.status === Image.Ready
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 12
                                    visible: rawNotificationIcon.status !== Image.Ready
                                    color: Qt.alpha(Theme.white, 0.11)

                                    Text {
                                        anchors.centerIn: parent
                                        text: ""
                                        font.family: Theme.fontIcons
                                        font.pixelSize: 16
                                        color: Theme.white
                                    }
                                }
                            }

                            // Text --------------------------------------------
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        Layout.fillWidth: true

                                        text:
                                            model.app
                                            + (
                                                model.urgency === 2
                                                ? "  •  CRITICAL"
                                                : ""
                                              )

                                        color:
                                            model.urgency === 2
                                            ? Theme.red
                                            : Qt.alpha(Theme.white, 0.62)

                                        font.family: Theme.fontMain
                                        font.pixelSize: 9
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true

                                    text: model.title
                                    color: Theme.white
                                    font.family: Theme.fontMain
                                    font.pixelSize: 12
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true

                                    text: model.body
                                    color: Qt.alpha(Theme.white, 0.60)
                                    font.family: Theme.fontMain
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                            }

                            // Dismiss -----------------------------------------
                            Item {
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                Layout.alignment: Qt.AlignTop

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 12
                                    color:
                                        dismissMouse.containsMouse
                                        ? Qt.alpha(Theme.white, 0.15)
                                        : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰅖"
                                        font.family: Theme.fontIcons
                                        font.pixelSize: 13
                                        color: Qt.alpha(Theme.white, 0.70)
                                    }
                                }

                                MouseArea {
                                    id: dismissMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor

                                    onClicked: {
                                        ncWindow.execCmd(
                                            "echo 'REMOVE|"
                                            + model.id
                                            + "' > /tmp/qs_notif_cmd"
                                        )
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
