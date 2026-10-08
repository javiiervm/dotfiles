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
     * Control Center
     * Primera versión inspirada en macOS Tahoe.
     *
     * Esta versión cambia principalmente el frontend y conserva la interfaz
     * que shell.qml ya utiliza para Wi-Fi, Bluetooth, Airplane, Caffeine
     * y Focus/DND. Las notificaciones ahora pertenecen a DynamicIsland.
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
    // Names and radio state arrive from shell.qml; no additional polling in this panel.
    property string wifiNetworkName: ""
    property string btDeviceName: ""
    property bool btState: false
    property bool airplaneState: false
    property bool caffeineState: false
    property bool powerSaverState: false
    property bool powerSaverAvailable: false
    property bool nightLightState: false
    property int nightLightTemperature: 4000
    property bool nightLightTemperatureOpen: false
    // Which value the shared Brightness/Night-Light slider is editing.
    // Left click on the icon toggles Night Light; right click toggles this mode.
    property bool brightnessTemperatureMode: false


    signal requestClose()
    signal toggleDndRequested()

    signal toggleWifiRequested()
    signal toggleBtRequested()
    signal toggleAirplaneRequested()
    signal toggleCaffeineRequested()
    signal togglePowerSaverRequested()
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
    property date currentLocalDay: new Date()
    // Today's events are independent of the displayed month and selected agenda day.
    readonly property var todayEvents: sortedEventsForDate(currentLocalDay)

    readonly property int panelWidth: 396
    readonly property int panelMargin: 12
    readonly property int tileGap: 10
    readonly property int topTileHeight: 64
    readonly property int calendarHeight: topTileHeight * 2 + tileGap
    readonly property int smallButtonSize: 62
    // Compact horizontal Volume/Brightness controls.
    readonly property int mediaSliderHeight: 34
    readonly property int mediaControlsHeight: mediaSliderHeight

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

    // The sync backend emits time ranges like "10:00 - 13:00".
    // Removing spaces and using an en dash saves space in narrow cards.
    // Both event views must keep the entire range on a single line.
    function compactEventTime(value) {
        return String(value || "All day").replace(/\s*[-\u2013\u2014]\s*/g, "–")
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
                    console.warn("ControlCenter: calendar backend parse error:", e)
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
            var now = new Date()
            currentLocalDay = now
            calendarTile.today = now
            contentScroll.contentY = 0
            closeTimer.stop()
            isReallyVisible = true
        } else {
            // The temperature slider is transient UI: always collapse it as
            // soon as the Control Center begins closing.
            nightLightTemperatureOpen = false
            brightnessTemperatureMode = false
            closeTimer.start()
        }
    }

    Timer {
        id: calendarDayRefresh
        interval: 60000
        repeat: true
        running: ncWindow.visible_state
        onTriggered: {
            var now = new Date()
            if (!ncWindow.sameCalendarDay(ncWindow.currentLocalDay, now)) {
                ncWindow.currentLocalDay = now
                calendarTile.today = now
            }
        }
    }

    Timer {
        id: closeTimer
        interval: 350
        onTriggered: isReallyVisible = false
    }

    // Click fuera del Control Center = cerrar.
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

        Flickable {
            id: contentScroll
            anchors.fill: parent
            contentWidth: width
            contentHeight: contentColumn.height
            flickableDirection: Flickable.VerticalFlick
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            clip: true

        Column {
            id: contentColumn

            width: parent.width
            anchors.right: parent.right
            spacing: ncWindow.tileGap

            // CONTROL CENTER — 3 rows, 2 columns. All buttons share one size.
            // Wi-Fi              | Bluetooth
            // Airplane           | Caffeine
            // Mute notifications | Power mode
            Grid {
                id: topRow
                width: parent.width
                height: 3 * ncWindow.topTileHeight + 2 * ncWindow.tileGap
                columns: 2
                columnSpacing: ncWindow.tileGap
                rowSpacing: ncWindow.tileGap

                GlassSurface {
                    id: wifiTile

                    width: (parent.width - ncWindow.tileGap) / 2
                    height: ncWindow.topTileHeight
                    glassRadius: height / 2
                    // Avoid the straight top highlight protruding past the pill's curved edge.
                    showHighlight: false
                    clip: true
                    glassOpacity:
                        ncWindow.wifiPending ? 0.45
                        : wifiMouse.containsMouse ? 0.45
                        : 0.34

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 8

                        Item {
                            width: 40
                            height: parent.height

                            Rectangle {
                                anchors.centerIn: parent
                                width: 36
                                height: 36
                                radius: width / 2

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
                                    font.pixelSize: 16
                                    color: ncWindow.wifiState && !ncWindow.wifiPending ? Theme.bg0 : Theme.white
                                }
                            }
                        }

                        Column {
                            width: parent.width - 48
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                width: parent.width
                                text: "Wi-Fi"
                                color: Theme.white
                                font.family: Theme.fontMain
                                font.pixelSize: 13
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text:
                                    ncWindow.wifiPending ? "Changing…"
                                    : !ncWindow.wifiState ? "Off"
                                    : (ncWindow.wifiNetworkName.trim() !== "" && ncWindow.wifiNetworkName.toLowerCase() !== "disconnected"
                                        ? ncWindow.wifiNetworkName : "Not connected")
                                color: Qt.alpha(Theme.white, 0.60)
                                font.family: Theme.fontMain
                                font.pixelSize: 10
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

                    width: (parent.width - ncWindow.tileGap) / 2
                    height: ncWindow.topTileHeight
                    glassRadius: height / 2
                    // Avoid the straight top highlight protruding past the pill's curved edge.
                    showHighlight: false
                    clip: true
                    glassOpacity:
                        ncWindow.btPending ? 0.45
                        : btMouse.containsMouse ? 0.45
                        : 0.34

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 8

                        Item {
                            width: 40
                            height: parent.height

                            Rectangle {
                                anchors.centerIn: parent
                                width: 36
                                height: 36
                                radius: width / 2

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
                                    font.pixelSize: 16
                                    color: ncWindow.btState && !ncWindow.btPending ? Theme.bg0 : Theme.white
                                }
                            }
                        }

                        Column {
                            width: parent.width - 48
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                width: parent.width
                                text: "Bluetooth"
                                color: Theme.white
                                font.family: Theme.fontMain
                                font.pixelSize: 13
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text:
                                    ncWindow.btPending ? "Changing…"
                                    : !ncWindow.btState ? "Off"
                                    : (ncWindow.btDeviceName.trim() !== "" && ncWindow.btDeviceName.toLowerCase() !== "none"
                                        ? ncWindow.btDeviceName : "Not connected")
                                color: Qt.alpha(Theme.white, 0.60)
                                font.family: Theme.fontMain
                                font.pixelSize: 10
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
                    id: airplaneTile

                    width: (parent.width - ncWindow.tileGap) / 2
                    height: ncWindow.topTileHeight
                    glassRadius: height / 2
                    // Avoid the straight top highlight protruding past the pill's curved edge.
                    showHighlight: false
                    clip: true
                    glassOpacity:
                        ncWindow.airplanePending ? 0.45
                        : airplaneMouse.containsMouse ? 0.45
                        : 0.34

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 8

                        Item {
                            width: 40
                            height: parent.height

                            Rectangle {
                                anchors.centerIn: parent
                                width: 36
                                height: 36
                                radius: width / 2

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
                                    font.pixelSize: 16
                                    color:
                                        ncWindow.airplaneState && !ncWindow.airplanePending
                                        ? Theme.bg0
                                        : Theme.white
                                }
                            }
                        }

                        Column {
                            width: parent.width - 48
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                width: parent.width
                                text: "Airplane"
                                color: Theme.white
                                font.family: Theme.fontMain
                                font.pixelSize: 13
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
                                font.pixelSize: 10
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

                GlassSurface {
                    id: caffeineTile

                    width: (parent.width - ncWindow.tileGap) / 2
                    height: ncWindow.topTileHeight
                    glassRadius: height / 2
                    // Avoid the straight top highlight protruding past the pill's curved edge.
                    showHighlight: false
                    clip: true
                    glassOpacity:
                        ncWindow.caffeinePending ? 0.45
                        : caffeineMouse.containsMouse ? 0.45
                        : 0.34

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 8

                        Item {
                            width: 40
                            height: parent.height

                            Rectangle {
                                anchors.centerIn: parent
                                width: 36
                                height: 36
                                radius: width / 2

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
                                    font.pixelSize: 16
                                    color:
                                        ncWindow.caffeineState && !ncWindow.caffeinePending
                                        ? Theme.bg0
                                        : Theme.white
                                }
                            }
                        }

                        Column {
                            width: parent.width - 48
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                width: parent.width
                                text: "Caffeine"
                                color: Theme.white
                                font.family: Theme.fontMain
                                font.pixelSize: 13
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
                                font.pixelSize: 10
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

                GlassSurface {
                    id: focusButton
                    width: (parent.width - ncWindow.tileGap) / 2
                    height: ncWindow.topTileHeight
                    glassRadius: height / 2
                    // Avoid the straight top highlight protruding past the pill's curved edge.
                    showHighlight: false
                    clip: true
                    glassOpacity: ncWindow.dndState ? 0.43 : focusMouse.containsMouse ? 0.45 : 0.34

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 8
                        Item {
                            width: 40
                            height: parent.height
                            Rectangle {
                                anchors.centerIn: parent
                                width: 36
                                height: 36
                                radius: width / 2
                                color: ncWindow.dndState ? Theme.white : Qt.alpha(Theme.white, 0.13)
                                Text {
                                    anchors.centerIn: parent
                                    text: "󰖔" // Crescent moon for Focus, whether enabled or disabled
                                    font.family: Theme.fontIcons
                                    font.pixelSize: 16
                                    color: ncWindow.dndState ? Theme.bg0 : Theme.white
                                }
                            }
                        }
                        Column {
                            width: parent.width - 48
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                width: parent.width
                                text: "Focus"
                                color: Theme.white
                                font.family: Theme.fontMain
                                font.pixelSize: 12
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: ncWindow.dndState ? "On" : "Off"
                                color: Qt.alpha(Theme.white, 0.60)
                                font.family: Theme.fontMain
                                font.pixelSize: 10
                            }
                        }
                    }
                    MouseArea {
                        id: focusMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ncWindow.toggleDndRequested()
                    }
                }

                GlassSurface {
                    id: powerSaverButton
                    width: (parent.width - ncWindow.tileGap) / 2
                    height: ncWindow.topTileHeight
                    glassRadius: height / 2
                    // Avoid the straight top highlight protruding past the pill's curved edge.
                    showHighlight: false
                    clip: true
                    // Power uses the same neutral glass as the remaining five buttons.
                    glassTint: Glass.tint
                    glassOpacity: powerSaverMouse.containsMouse ? 0.45 : 0.34

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 8
                        Item {
                            width: 40
                            height: parent.height
                            Rectangle {
                                anchors.centerIn: parent
                                width: 36
                                height: 36
                                radius: width / 2
                                // The circular badge carries the profile colour, not the leaf.
                                // Saver = green badge; Balanced = white badge.
                                color: ncWindow.powerSaverState ? "#2ecc71" : Theme.white
                                Text {
                                    anchors.centerIn: parent
                                    anchors.horizontalCenterOffset: 1.5
                                    text: "󰌪"
                                    font.family: Theme.fontIcons
                                    font.pixelSize: 16
                                    color: Theme.bg0
                                }
                            }
                        }
                        Column {
                            width: parent.width - 48
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                width: parent.width
                                text: "Power"
                                color: Theme.white
                                font.family: Theme.fontMain
                                font.pixelSize: 13
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: ncWindow.powerSaverState ? "Power saver" : "Balanced"
                                color: Qt.alpha(Theme.white, 0.60)
                                font.family: Theme.fontMain
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }
                        }
                    }
                    MouseArea {
                        id: powerSaverMouse
                        anchors.fill: parent
                        enabled: ncWindow.powerSaverAvailable
                        hoverEnabled: enabled
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: ncWindow.togglePowerSaverRequested()
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
                    showHighlight: false
                    clip: true
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
                    showHighlight: false
                    clip: true
                    // The surface indicates whether Night Light itself is active.
                    // Slider mode is independent and is toggled with right click.
                    glassTint: ncWindow.nightLightState ? "#ffd38a" : Glass.tint
                    glassOpacity:
                        ncWindow.nightLightState ? 0.42
                        : (brightnessModeMouse.containsMouse || brightnessControlMouse.containsMouse ? 0.43 : 0.34)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 11
                        anchors.rightMargin: 11
                        spacing: 8

                        // Shared Brightness / Night Light button:
                        //   left click  -> toggle Night Light itself
                        //   right click -> switch the slider between brightness
                        //                  and colour-temperature adjustment
                        Item {
                            id: brightnessModeButton
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: parent.height

                            Text {
                                anchors.centerIn: parent
                                text: ncWindow.nightLightState ? "󰖔" : "󰃠"
                                font.family: Theme.fontIcons
                                font.pixelSize: 15
                                color: ncWindow.nightLightState ? "#ffd38a" : Theme.white
                            }

                            MouseArea {
                                id: brightnessModeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor

                                onClicked: function(mouse) {
                                    if (mouse.button === Qt.RightButton) {
                                        ncWindow.brightnessTemperatureMode = !ncWindow.brightnessTemperatureMode
                                    } else if (mouse.button === Qt.LeftButton) {
                                        ncWindow.toggleNightLightRequested()
                                    }
                                }
                            }
                        }

                        Item {
                            id: brightnessTrackHitbox
                            Layout.fillWidth: true
                            Layout.preferredHeight: parent.height

                            readonly property real shownLevel:
                                ncWindow.brightnessTemperatureMode
                                ? Math.max(0.0, Math.min(1.0,
                                      (ncWindow.nightLightTemperature - 2500) / 3500.0))
                                : ncWindow.clamp01(ncWindow.brightnessLevel)

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
                                    width: parent.width * brightnessTrackHitbox.shownLevel
                                    color: ncWindow.brightnessTemperatureMode ? "#ffd38a" : Theme.white

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
                                    if (ncWindow.brightnessTemperatureMode) {
                                        ncWindow.setNightLightTemperatureFromX(mouse.x, width)
                                    } else {
                                        ncWindow.brightnessDragging = true
                                        ncWindow.setBrightnessPreviewFromX(mouse.x, width)
                                        ncWindow.applyBrightness()
                                    }
                                }

                                onPositionChanged: function(mouse) {
                                    if (!pressed)
                                        return

                                    if (ncWindow.brightnessTemperatureMode)
                                        ncWindow.setNightLightTemperatureFromX(mouse.x, width)
                                    else
                                        ncWindow.setBrightnessPreviewFromX(mouse.x, width)
                                }

                                onReleased: {
                                    if (!ncWindow.brightnessTemperatureMode) {
                                        ncWindow.applyBrightness()
                                        ncWindow.brightnessDragging = false
                                    }
                                }

                                onCanceled: {
                                    if (!ncWindow.brightnessTemperatureMode) {
                                        ncWindow.applyBrightness()
                                        ncWindow.brightnessDragging = false
                                    }
                                }
                            }
                        }

                        Text {
                            text: ncWindow.brightnessTemperatureMode
                                  ? ncWindow.nightLightTemperature + "K"
                                  : Math.round(ncWindow.brightnessLevel * 100) + "%"
                            color: ncWindow.brightnessTemperatureMode ? "#ffd38a" : Theme.white
                            font.family: Theme.fontMain
                            font.pixelSize: 10
                            font.bold: true
                            Layout.minimumWidth: ncWindow.brightnessTemperatureMode ? 36 : 29
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            }

            // =============================================================
            // CALENDAR — Full width, below all other panel controls.
            // =============================================================
            GlassSurface {
                id: calendarTile

                width: parent.width
                height: Math.round(width * 0.80)
                glassRadius: 22
                glassOpacity: calendarMouse.containsMouse ? 0.42 : 0.34
                clip: true

                property date today: new Date()

                // ---------------- MONTH VIEW ----------------
                Column {
                    id: monthView
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 7
                    visible: !ncWindow.agendaVisible

                    Item {
                        width: parent.width
                        height: 30

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰅁"
                            color: Qt.alpha(Theme.white, previousMonthMouse.containsMouse ? 1.0 : 0.58)
                            font.family: Theme.fontIcons
                            font.pixelSize: 15

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
                            font.pixelSize: 16
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
                            font.pixelSize: 15

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
                        height: 22
                        locale: Qt.locale("en_GB")

                        delegate: Text {
                            text: model.narrowName
                            color: Qt.alpha(Theme.white, 0.50)
                            font.family: Theme.fontMain
                            font.pixelSize: 12
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    MonthGrid {
                        id: compactMonthGrid
                        width: parent.width
                        height: parent.height - 66
                        month: ncWindow.displayMonth
                        year: ncWindow.displayYear
                        locale: Qt.locale("en_GB")

                        delegate: Item {
                            implicitWidth: compactMonthGrid.width / 7
                            implicitHeight: compactMonthGrid.height / 6
                            opacity: model.month === compactMonthGrid.month ? 1 : 0.20

                            property var dayEvents: ncWindow.getEventsForDate(model.date)
                            property bool hasEvents: dayEvents.length > 0

                            Rectangle {
                                id: todaySelectionHalo
                                anchors.centerIn: parent
                                width: Math.min(40, Math.round(compactMonthGrid.height / 6 * 1.06))
                                height: width
                                radius: width / 2
                                visible: model.today
                                color: Theme.white
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.verticalCenter: parent.verticalCenter
                                // Keep the day number in its original position; the event dot
                                // fits inside the enlarged selection circle without moving it.
                                anchors.verticalCenterOffset: -2
                                text: model.day
                                color: model.today
                                       ? Theme.bg0
                                       : Qt.alpha(Theme.white, 0.82)
                                font.family: Theme.fontMain
                                font.pixelSize: Math.max(12, Math.min(15, Math.round(compactMonthGrid.width / 27)))
                                font.bold: model.today || hasEvents
                            }

                            // For today, the event dot sits *inside* the selected-day halo.
                            // All other event dots retain their original position below the date.
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: model.today
                                   ? Math.round(parent.height / 2 + todaySelectionHalo.height * 0.24)
                                   : parent.height - height - 1
                                width: 4.5
                                height: width
                                radius: width / 2
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
                    anchors.margins: 18
                    spacing: 10
                    visible: ncWindow.agendaVisible

                    Item {
                        width: parent.width
                        height: 30

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
                            font.pixelSize: 15
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
                        height: parent.height - 50
                        visible: ncWindow.selectedEvents.length === 0
                        text: "No events this day"
                        color: Qt.alpha(Theme.white, 0.58)
                        font.family: Theme.fontMain
                        font.pixelSize: 13
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    ListView {
                        id: compactAgendaList
                        width: parent.width
                        height: parent.height - 50
                        visible: ncWindow.selectedEvents.length > 0
                        clip: true
                        spacing: 8
                        boundsBehavior: Flickable.StopAtBounds
                        model: ncWindow.selectedEvents

                        delegate: Item {
                            width: ListView.view.width
                            height: 56

                            Row {
                                anchors.fill: parent
                                spacing: 10

                                Text {
                                    id: agendaTimeText
                                    // Size this column to the actual time text. With the Row's
                                    // uniform spacing, both sides of the divider have a 10px gap.
                                    width: Math.min(104, Math.ceil(implicitWidth))
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: ncWindow.compactEventTime(modelData.time)
                                    color: Qt.alpha(Theme.white, 0.78)
                                    font.family: Theme.fontMain
                                    font.pixelSize: 12
                                    minimumPixelSize: 10
                                    fontSizeMode: Text.HorizontalFit
                                    font.bold: true
                                    wrapMode: Text.NoWrap
                                    elide: Text.ElideRight
                                }

                                Rectangle {
                                    width: 2
                                    height: 28
                                    radius: 1
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Qt.alpha(Theme.white, 0.24)
                                }

                                Text {
                                    width: Math.max(0, parent.width - agendaTimeText.width - 22)
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.title || "Untitled event"
                                    color: Theme.white
                                    font.family: Theme.fontMain
                                    font.pixelSize: 14
                                    font.bold: true
                                    maximumLineCount: 2
                                    wrapMode: Text.Wrap
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

            // TODAY'S EVENTS — only shown if the synced calendar has entries today.
            // This is independent of the selected month or the detailed agenda view.
            GlassSurface {
                id: todayEventsTile
                width: parent.width
                visible: ncWindow.todayEvents.length > 0
                height: visible ? Math.min(242, 60 + ncWindow.todayEvents.length * 48) : 0
                glassRadius: 22
                glassOpacity: 0.34
                clip: true

                Column {
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    anchors.topMargin: 12
                    anchors.bottomMargin: 10
                    spacing: 8

                    Row {
                        width: parent.width
                        height: 22
                        spacing: 8

                        Text {
                            text: "󰃭"
                            color: Theme.white
                            font.family: Theme.fontIcons
                            font.pixelSize: 15
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: "Today's events"
                            color: Theme.white
                            font.family: Theme.fontMain
                            font.pixelSize: 13
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: String(ncWindow.todayEvents.length)
                            color: Qt.alpha(Theme.white, 0.57)
                            font.family: Theme.fontMain
                            font.pixelSize: 11
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Qt.alpha(Theme.white, 0.10)
                    }

                    ListView {
                        id: todayEventsList
                        width: parent.width
                        height: Math.max(0, parent.height - 39)
                        clip: true
                        spacing: 4
                        boundsBehavior: Flickable.StopAtBounds
                        model: ncWindow.todayEvents

                        delegate: Item {
                            width: ListView.view.width
                            height: 44

                            Row {
                                anchors.fill: parent
                                spacing: 10
                                Text {
                                    id: todayEventTimeText
                                    // Avoid unused space before the divider for short labels
                                    // such as 'All day', while retaining single-line times.
                                    width: Math.min(104, Math.ceil(implicitWidth))
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: ncWindow.compactEventTime(modelData.time)
                                    color: Qt.alpha(Theme.white, 0.73)
                                    font.family: Theme.fontMain
                                    font.pixelSize: 11
                                    minimumPixelSize: 10
                                    fontSizeMode: Text.HorizontalFit
                                    font.bold: true
                                    wrapMode: Text.NoWrap
                                    elide: Text.ElideRight
                                }
                                Rectangle {
                                    width: 2
                                    height: 24
                                    radius: 1
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Qt.alpha(Theme.white, 0.30)
                                }
                                Text {
                                    width: Math.max(0, parent.width - todayEventTimeText.width - 22)
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.title || "Untitled event"
                                    color: Theme.white
                                    font.family: Theme.fontMain
                                    font.pixelSize: 12
                                    font.bold: true
                                    maximumLineCount: 2
                                    wrapMode: Text.Wrap
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }

        }
        } // contentScroll

    }
}
