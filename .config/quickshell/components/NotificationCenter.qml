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

    property bool dndState: false
    property bool wifiState: false
    property bool btState: false
    property bool airplaneState: false
    property bool caffeineState: false

    property ListModel modelData

    signal requestClose()
    signal toggleDndRequested()
    signal clearRequested()

    signal toggleWifiRequested()
    signal toggleBtRequested()
    signal toggleAirplaneRequested()
    signal toggleCaffeineRequested()

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

    readonly property int notificationCount:
        ncWindow.modelData ? ncWindow.modelData.count : 0

    readonly property int topControlsHeight:
        calendarHeight + tileGap + topTileHeight

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
        anchors.rightMargin: ncWindow.panelMargin

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
