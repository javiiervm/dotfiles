import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import ".."

PanelWindow {
    id: pickerWindow

    // ============================================================
    // Window / mouse-relative placement
    // ============================================================

    readonly property int popupWidth: 390
    readonly property int popupHeight: 468

    // Keep a little more breathing room than Windows so the rounded card,
    // border and shadow never touch or cross a monitor edge.
    readonly property int edgePadding: 18
    readonly property int cursorGapX: 14
    readonly property int cursorGapY: 18

    property var targetScreen: {
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

    screen: targetScreen

    implicitWidth: popupWidth
    implicitHeight: popupHeight

    // A PanelWindow is positioned in logical pixels relative to its current
    // ShellScreen. The cursor from Hyprland is converted to screen-local
    // coordinates before these margins are assigned.
    anchors {
        left: true
        top: true
    }

    margins {
        left: popupX
        top: popupY
    }

    property int popupX: edgePadding
    property int popupY: edgePadding

    visible: false

    // While the picker is visible it owns keyboard focus, with Search focused
    // automatically. The original Hyprland window is remembered and explicitly
    // focused again before committing an emoji.
    property bool searchMode: false
    focusable: true
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.namespace: "quickshell:emoji"

    function clamp(value, minimum, maximum) {
        if (maximum < minimum)
            return minimum

        return Math.max(minimum, Math.min(value, maximum))
    }

    function squaredDistanceToScreen(screenObject, globalX, globalY) {
        var nearestX = clamp(globalX, screenObject.x, screenObject.x + screenObject.width)
        var nearestY = clamp(globalY, screenObject.y, screenObject.y + screenObject.height)
        var dx = globalX - nearestX
        var dy = globalY - nearestY
        return dx * dx + dy * dy
    }

    function screenAt(globalX, globalY) {
        var screens = Quickshell.screens

        // Exact hit first.
        for (var i = 0; i < screens.length; ++i) {
            var s = screens[i]

            if (globalX >= s.x
                    && globalX < s.x + s.width
                    && globalY >= s.y
                    && globalY < s.y + s.height) {
                return s
            }
        }

        // Fractional scaling / rounding can put the reported pointer one
        // logical pixel outside Qt's screen rectangle. Pick the closest
        // monitor instead of falling back to the laptop screen.
        var closest = null
        var bestDistance = Number.MAX_VALUE

        for (var j = 0; j < screens.length; ++j) {
            var candidate = screens[j]
            var distance = squaredDistanceToScreen(candidate, globalX, globalY)

            if (distance < bestDistance) {
                closest = candidate
                bestDistance = distance
            }
        }

        return closest || targetScreen
    }

    function placeAtPointer(globalX, globalY) {
        var s = screenAt(globalX, globalY)

        if (!s)
            return false

        var screenWidth = Math.max(1, s.width)
        var screenHeight = Math.max(1, s.height)

        var localX = globalX - s.x
        var localY = globalY - s.y
        var lineHeight = 0

        localX = clamp(localX, 0, screenWidth - 1)
        localY = clamp(localY, 0, screenHeight - 1)

        // Put the panel just below and slightly to the right of the mouse
        // pointer. Flip above/left when required, then hard-clamp it to the
        // current monitor so the widget can never be cut off.
        var rightX = localX + 12
        var leftX = localX - popupWidth - 12
        var belowY = localY + lineHeight + 14
        var aboveY = localY - popupHeight - 14

        var x
        var y

        if (rightX + popupWidth <= screenWidth - edgePadding)
            x = rightX
        else if (leftX >= edgePadding)
            x = leftX
        else
            x = clamp(
                rightX,
                edgePadding,
                screenWidth - popupWidth - edgePadding
            )

        if (belowY + popupHeight <= screenHeight - edgePadding)
            y = belowY
        else if (aboveY >= edgePadding)
            y = aboveY
        else
            y = clamp(
                belowY,
                edgePadding,
                screenHeight - popupHeight - edgePadding
            )

        x = clamp(
            Math.round(x),
            edgePadding,
            Math.max(edgePadding, screenWidth - popupWidth - edgePadding)
        )

        y = clamp(
            Math.round(y),
            edgePadding,
            Math.max(edgePadding, screenHeight - popupHeight - edgePadding)
        )

        targetScreen = s
        popupX = x
        popupY = y

        return true
    }


    Process {
        id: pointerProbe

        // Capture BOTH pieces of state before the picker can steal keyboard
        // focus: the exact Hyprland client address and the mouse position.
        command: [
            "bash",
            "-lc",
            "addr=\"$(hyprctl -j activewindow 2>/dev/null | "
                + "python3 -c 'import json,sys; "
                + "d=json.load(sys.stdin); "
                + "print(d.get(\"address\", \"\"))' 2>/dev/null)\"; "
                + "pos=\"$(hyprctl cursorpos 2>/dev/null || true)\"; "
                + "printf '%s\\n%s\\n' \"$addr\" \"$pos\""
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                if (!pickerWindow.pendingOpen)
                    return

                var lines = text.trim().split("\n")
                var address = lines.length > 0 ? lines[0].trim() : ""
                var value = lines.length > 1 ? lines[1].trim() : ""

                if (/^0x[0-9a-fA-F]+$/.test(address))
                    pickerWindow.previousWindowAddress = address
                else
                    pickerWindow.previousWindowAddress = ""

                var parts = value.split(",")

                if (parts.length === 2) {
                    var x = Number(parts[0].trim())
                    var y = Number(parts[1].trim())

                    if (Number.isFinite(x)
                            && Number.isFinite(y)
                            && pickerWindow.placeAtPointer(x, y)) {
                        console.log(
                            "EmojiPicker anchor: mouse",
                            Math.round(x),
                            Math.round(y),
                            "target:",
                            pickerWindow.previousWindowAddress
                        )
                        pickerWindow.finishOpen()
                        return
                    }
                }

                console.warn(
                    "EmojiPicker: could not read mouse position:",
                    value
                )
                pickerWindow.openFallback()
            }
        }
    }

    // ============================================================
    // Data / state
    // ============================================================

    property var allEmojis: []
    property var filteredEmojis: []
    property var recentEmojis: []
    property var previousToplevel: null
    property string previousWindowAddress: ""

    property bool pendingOpen: false
    property bool typeNeedsFocusRestoreAfterTyping: false
    property bool followMouseOverridden: false
    property bool restoringOriginalFocus: false
    property string selectedCategory: "smileys"
    property string query: ""
    property string pendingEmoji: ""

    readonly property int maxRecents: 35
    readonly property int gridColumns: 7

    readonly property var categories: [
        { id: "recent",     icon: "◷",  label: "Recent" },
        { id: "smileys",   icon: "☺️", label: "Smileys & Emotion" },
        { id: "people",     icon: "🧑", label: "People & Body" },
        { id: "animals",    icon: "🐱", label: "Animals & Nature" },
        { id: "food",       icon: "🍕", label: "Food & Drink" },
        { id: "activities", icon: "⚽", label: "Activities" },
        { id: "travel",     icon: "🚗", label: "Travel & Places" },
        { id: "objects",    icon: "💡", label: "Objects" },
        { id: "symbols",    icon: "♥️", label: "Symbols" },
        { id: "flags",      icon: "🏳️", label: "Flags" }
    ]

    function categoryLabel(categoryId) {
        for (var i = 0; i < categories.length; ++i) {
            if (categories[i].id === categoryId)
                return categories[i].label
        }

        return "Emojis"
    }

    function normalized(value) {
        return (value || "").toString().toLowerCase()
    }

    function emojiObjectFor(character) {
        for (var i = 0; i < allEmojis.length; ++i) {
            if (allEmojis[i].emoji === character)
                return allEmojis[i]
        }

        return {
            emoji: character,
            name: character,
            keywords: "",
            category: "recent",
            subgroup: ""
        }
    }

    function updateFiltered() {
        var result = []
        var needle = normalized(query).trim()

        if (needle.length > 0) {
            for (var i = 0; i < allEmojis.length; ++i) {
                var item = allEmojis[i]
                var haystack = normalized(
                    item.emoji + " "
                    + item.name + " "
                    + item.keywords + " "
                    + item.subgroup
                )

                if (haystack.indexOf(needle) !== -1)
                    result.push(item)
            }
        } else if (selectedCategory === "recent") {
            for (var r = 0; r < recentEmojis.length; ++r)
                result.push(emojiObjectFor(recentEmojis[r]))
        } else {
            for (var j = 0; j < allEmojis.length; ++j) {
                if (allEmojis[j].category === selectedCategory)
                    result.push(allEmojis[j])
            }
        }

        filteredEmojis = result
        emojiGrid.currentIndex = result.length > 0 ? 0 : -1

        if (result.length > 0)
            emojiGrid.positionViewAtBeginning()
    }

    function selectCategory(categoryId) {
        selectedCategory = categoryId

        if (searchInput.text.length > 0)
            searchInput.text = ""

        query = ""
        updateFiltered()

        if (searchMode)
            searchInput.forceActiveFocus()
    }

    function rememberEmoji(character) {
        var next = [character]

        for (var i = 0; i < recentEmojis.length && next.length < maxRecents; ++i) {
            if (recentEmojis[i] !== character)
                next.push(recentEmojis[i])
        }

        recentEmojis = next
        recentFile.setText(JSON.stringify(next))
    }

    function freezeKeyboardFocusOnCurrentApp() {
        if (followMouseOverridden)
            return

        followMouseOverridden = true

        // The user's normal Hyprland setup uses follow_mouse=1. While the
        // picker is open, mode 2 detaches pointer focus from keyboard focus:
        // merely crossing another tiled window cannot steal the text caret.
        followMouseFreezeProc.running = true
    }

    function restoreNormalFollowMouse() {
        if (!followMouseOverridden)
            return

        followMouseOverridden = false
        followMouseRestoreProc.running = true
    }

    function prepareOpenState() {
        previousToplevel = Hyprland.activeToplevel
        previousWindowAddress = ""
        pendingEmoji = ""
        typeNeedsFocusRestoreAfterTyping = false
        restoringOriginalFocus = false
        searchMode = false
        focusGrab.active = false

        if (searchInput.text.length > 0)
            searchInput.text = ""

        query = ""
        selectedCategory = recentEmojis.length > 0 ? "recent" : "smileys"
        updateFiltered()
    }

    function openPicker() {
        if (visible || pendingOpen)
            return

        prepareOpenState()
        pendingOpen = true

        // Position from the mouse pointer. This is deliberately independent
        // of text accessibility APIs: it works the same way in Firefox,
        // Kitty, VS Code and any other application.
        pointerProbe.running = true
    }

    function finishOpen() {
        if (!pendingOpen)
            return

        pendingOpen = false
        searchMode = true
        visible = true
        searchFocusTimer.restart()
    }

    function openFallback() {
        if (!pendingOpen)
            return

        var s = targetScreen
        if (!s && Quickshell.screens.length > 0)
            s = Quickshell.screens[0]

        if (s) {
            targetScreen = s

            // Last-resort fallback if hyprctl cannot report the pointer: keep it
            // in the lower-right corner rather than jumping to the center.
            popupX = Math.max(
                edgePadding,
                Math.round(s.width - card.width - edgePadding)
            )
            popupY = Math.max(
                edgePadding,
                Math.round(s.height - card.height - edgePadding)
            )
        }

        finishOpen()
    }

    function closePicker(restorePreviousFocus) {
        pendingOpen = false

        if (!visible)
            return

        visible = false
        focusGrab.active = false
        searchMode = false
        pendingEmoji = ""
        restoringOriginalFocus = false
        focusCommitTimer.stop()

        restoreNormalFollowMouse()

        // For Escape / X, returning to the old app is convenient. For an
        // outside click, false is passed so the clicked destination keeps focus.
        if (restorePreviousFocus !== false && previousToplevel)
            previousToplevel.activate()
    }

    function enterSearchMode() {
        if (!visible || searchMode)
            return

        searchMode = true

        // Let layer-shell update keyboard interactivity first, then ask the
        // TextInput for focus.
        searchFocusTimer.restart()
    }

    function togglePicker() {
        if (visible)
            closePicker(true)
        else if (pendingOpen)
            pendingOpen = false
        else
            openPicker()
    }

    function chooseEmoji(character) {
        if (!character || character.length === 0)
            return

        pendingEmoji = character
        rememberEmoji(character)
        typeNeedsFocusRestoreAfterTyping = true
        restoringOriginalFocus = true

        // Only freeze hover-focus for the tiny handoff window. This prevents
        // the pointer (which is currently over the picker) from causing some
        // neighbouring tiled window to become the keyboard target as the
        // layer surface disappears.
        freezeKeyboardFocusOnCurrentApp()

        visible = false
        focusGrab.active = false
        searchMode = false

        if (/^0x[0-9a-fA-F]+$/.test(previousWindowAddress)) {
            var code =
                'hl.dispatch(hl.dsp.focus({ window = "address:'
                + previousWindowAddress
                + '" }))'

            focusOriginalProcess.command = [
                "hyprctl",
                "eval",
                code
            ]
            focusOriginalProcess.running = true
            return
        }

        // Fallback for the unlikely case in which activewindow could not be
        // captured. Toplevel activation is less deterministic, so give it a
        // slightly longer settle time.
        if (previousToplevel)
            previousToplevel.activate()

        focusCommitTimer.interval = 170
        focusCommitTimer.restart()
    }

    function moveGridSelection(delta) {
        if (filteredEmojis.length === 0)
            return

        var next = emojiGrid.currentIndex

        if (next < 0)
            next = 0
        else
            next = Math.max(0, Math.min(filteredEmojis.length - 1, next + delta))

        emojiGrid.currentIndex = next
        emojiGrid.positionViewAtIndex(next, GridView.Contain)
    }

    // ============================================================
    // Dataset and persistent recents
    // ============================================================

    FileView {
        id: emojiDataFile
        path: Qt.resolvedUrl("../assets/emoji/emojis.json")
        blockLoading: true
        printErrors: true
    }

    FileView {
        id: recentFile
        path: Quickshell.statePath("emoji-picker-recents.json")
        blockLoading: true
        printErrors: false
    }

    Component.onCompleted: {
        try {
            var parsed = JSON.parse(emojiDataFile.text())
            allEmojis = parsed instanceof Array ? parsed : []
        } catch (error) {
            console.error("EmojiPicker: could not parse emojis.json:", error)
            allEmojis = []
        }

        try {
            var stored = JSON.parse(recentFile.text())
            recentEmojis = stored instanceof Array ? stored.slice(0, maxRecents) : []
        } catch (error) {
            recentEmojis = []
        }

        selectedCategory = recentEmojis.length > 0 ? "recent" : "smileys"
        updateFiltered()
    }

    // ============================================================
    // Focus / direct Unicode typing
    // ============================================================

    HyprlandFocusGrab {
        id: focusGrab
        windows: [ pickerWindow ]

        onCleared: {
            // The compositor clears the grab when the user clicks/touches
            // outside this popup. Pointer movement by itself does not close it.
            if (pickerWindow.visible)
                pickerWindow.closePicker(false)
        }
    }

    Process {
        id: typeProcess

        onRunningChanged: {
            if (!running && pickerWindow.typeNeedsFocusRestoreAfterTyping) {
                pickerWindow.typeNeedsFocusRestoreAfterTyping = false
                pickerWindow.restoreNormalFollowMouse()
            }
        }
    }

    Process {
        id: focusOriginalProcess

        onRunningChanged: {
            if (!running
                    && pickerWindow.restoringOriginalFocus
                    && pickerWindow.pendingEmoji) {
                // hyprctl is synchronous; after the focus dispatcher returns,
                // allow one short compositor/toolkit settle interval before
                // sending Unicode input.
                focusCommitTimer.interval = 90
                focusCommitTimer.restart()
            }
        }
    }

    // Runtime Hyprland focus policy override. It is used only for the brief
    // picker -> original application handoff.
    Process {
        id: followMouseFreezeProc
        command: ["hyprctl", "keyword", "input:follow_mouse", "2"]
    }

    Process {
        id: followMouseRestoreProc
        command: ["hyprctl", "keyword", "input:follow_mouse", "1"]
    }

    Timer {
        id: searchFocusTimer
        interval: 30
        repeat: false

        onTriggered: {
            if (!pickerWindow.visible)
                return

            focusGrab.active = true
            searchInput.forceActiveFocus()
            searchInput.cursorPosition = searchInput.text.length
        }
    }

    Timer {
        id: focusCommitTimer
        interval: 90
        repeat: false

        onTriggered: {
            if (!pickerWindow.pendingEmoji) {
                pickerWindow.restoringOriginalFocus = false
                pickerWindow.restoreNormalFollowMouse()
                return
            }

            // The picker is hidden and Hyprland has explicitly focused the
            // saved client window before this timer fires.
            typeProcess.command = ["wtype", pickerWindow.pendingEmoji]
            typeProcess.running = true

            pickerWindow.pendingEmoji = ""
            pickerWindow.restoringOriginalFocus = false
            focusRestoreSafetyTimer.restart()
        }
    }

    Timer {
        id: focusRestoreSafetyTimer
        interval: 500
        repeat: false

        onTriggered: {
            if (pickerWindow.followMouseOverridden) {
                pickerWindow.typeNeedsFocusRestoreAfterTyping = false
                pickerWindow.restoreNormalFollowMouse()
            }
        }
    }

    // ============================================================
    // Compact Windows-like panel
    // ============================================================

    BackgroundEffect.blurRegion: Glass.blurEnabled ? pickerBlurRegion : null

    Region {
        id: pickerBlurRegion
        x: 0
        y: 0
        width: Math.round(card.width)
        height: Math.round(card.height)
        radius: Math.round(card.radius)
    }

    GlassSurface {
        id: card

        width: pickerWindow.popupWidth
        height: pickerWindow.popupHeight
        glassRadius: 20
        showBorder: true
        showHighlight: true
        clip: true

        // --------------------------------------------------------
        // Tiny header: handle + close, similar visual weight to Win11
        // --------------------------------------------------------

        Rectangle {
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
                topMargin: 12
            }

            width: 38
            height: 4
            radius: 2
            color: Qt.alpha(Theme.white, 0.60)
        }

        Rectangle {
            id: closeButton

            anchors {
                right: parent.right
                top: parent.top
                rightMargin: 8
                topMargin: 7
            }

            width: 28
            height: 28
            radius: 8

            color: closeMouse.containsMouse
                ? Qt.alpha(Theme.white, 0.12)
                : "transparent"

            Text {
                anchors.centerIn: parent
                text: "×"
                color: Qt.alpha(Theme.white, 0.88)
                font.family: Theme.fontMain
                font.pixelSize: 20
            }

            MouseArea {
                id: closeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: pickerWindow.closePicker(true)
            }
        }

        // --------------------------------------------------------
        // Category strip
        // --------------------------------------------------------

        Row {
            id: categoryRow

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                leftMargin: 16
                rightMargin: 16
                topMargin: 43
            }

            height: 35
            spacing: 4

            Repeater {
                model: pickerWindow.categories

                Rectangle {
                    required property var modelData

                    width: 32
                    height: 34
                    radius: 9

                    property bool selected:
                        pickerWindow.query.length === 0
                        && pickerWindow.selectedCategory === modelData.id

                    color: selected
                        ? Qt.alpha(Theme.white, 0.12)
                        : (categoryMouse.containsMouse
                            ? Qt.alpha(Theme.white, 0.07)
                            : "transparent")

                    Rectangle {
                        anchors {
                            horizontalCenter: parent.horizontalCenter
                            bottom: parent.bottom
                        }

                        width: 16
                        height: 2.5
                        radius: 1.25
                        visible: parent.selected
                        color: Theme.blue
                    }

                    Text {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -1

                        text: modelData.icon
                        color: Theme.white

                        font.family: modelData.id === "recent"
                            ? Theme.fontMain
                            : "Noto Color Emoji"

                        font.pixelSize: modelData.id === "recent" ? 20 : 18
                    }

                    MouseArea {
                        id: categoryMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pickerWindow.selectCategory(modelData.id)
                    }
                }
            }
        }

        // --------------------------------------------------------
        // Search
        // --------------------------------------------------------

        Rectangle {
            id: searchBox

            anchors {
                left: parent.left
                right: parent.right
                top: categoryRow.bottom
                leftMargin: 16
                rightMargin: 16
                topMargin: 9
            }

            height: 41
            radius: 10
            color: Qt.alpha(Theme.white, 0.055)

            border.width: searchInput.activeFocus ? 1.5 : 1
            border.color: searchInput.activeFocus
                ? Theme.blue
                : Qt.alpha(Theme.white, 0.11)

            Text {
                id: searchIcon

                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                }

                text: "󰍉"
                color: searchInput.activeFocus ? Theme.blue : Theme.fg
                font.family: Theme.fontIcons
                font.pixelSize: 16
            }

            Text {
                anchors {
                    left: searchIcon.right
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 9
                    rightMargin: 10
                }

                visible: searchInput.text.length === 0
                text: "Search emojis"
                color: Qt.alpha(Theme.fg, 0.60)
                font.family: Theme.fontMain
                font.pixelSize: 14
            }

            TextInput {
                id: searchInput

                anchors {
                    left: searchIcon.right
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 9
                    rightMargin: 10
                }

                height: 27
                verticalAlignment: TextInput.AlignVCenter

                color: Theme.white
                selectionColor: Qt.alpha(Theme.blue, 0.45)
                selectedTextColor: Theme.white
                font.family: Theme.fontMain
                font.pixelSize: 14
                clip: true

                onTextChanged: {
                    pickerWindow.query = text
                    pickerWindow.updateFiltered()
                }

                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                        pickerWindow.closePicker(true)
                        event.accepted = true
                        return
                    }

                    if (event.key === Qt.Key_Down
                            && pickerWindow.filteredEmojis.length > 0) {
                        emojiGrid.currentIndex = Math.max(0, emojiGrid.currentIndex)
                        emojiGrid.forceActiveFocus()
                        emojiGrid.positionViewAtIndex(
                            emojiGrid.currentIndex,
                            GridView.Contain
                        )
                        event.accepted = true
                        return
                    }

                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                            && pickerWindow.filteredEmojis.length > 0) {
                        pickerWindow.chooseEmoji(
                            pickerWindow.filteredEmojis[0].emoji
                        )
                        event.accepted = true
                    }
                }
            }
        }

        // --------------------------------------------------------
        // Section title
        // --------------------------------------------------------

        Text {
            id: sectionTitle

            anchors {
                left: parent.left
                top: searchBox.bottom
                leftMargin: 18
                topMargin: 12
            }

            text: pickerWindow.query.length > 0
                ? "Search results"
                : pickerWindow.categoryLabel(pickerWindow.selectedCategory)

            color: Qt.alpha(Theme.white, 0.93)
            font.family: Theme.fontMain
            font.pixelSize: 13
            font.bold: true
        }

        // --------------------------------------------------------
        // Emoji grid
        // --------------------------------------------------------

        GridView {
            id: emojiGrid

            anchors {
                left: parent.left
                right: parent.right
                top: sectionTitle.bottom
                bottom: parent.bottom
                leftMargin: 15
                rightMargin: 15
                topMargin: 6
                bottomMargin: 11
            }

            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: 2600

            cellWidth: width / pickerWindow.gridColumns
            cellHeight: 48
            model: pickerWindow.filteredEmojis
            currentIndex: model.length > 0 ? 0 : -1

            delegate: Item {
                required property var modelData
                required property int index

                width: emojiGrid.cellWidth
                height: emojiGrid.cellHeight

                Rectangle {
                    anchors.centerIn: parent
                    width: 43
                    height: 43
                    radius: 10

                    property bool selected: emojiGrid.currentIndex === index

                    color: selected
                        ? Qt.alpha(Theme.white, 0.13)
                        : (emojiMouse.containsMouse
                            ? Qt.alpha(Theme.white, 0.07)
                            : "transparent")

                    border.width: selected ? 1 : 0
                    border.color: selected
                        ? Qt.alpha(Theme.blue, 0.82)
                        : "transparent"

                    scale: emojiMouse.pressed ? 0.91 : 1.0

                    Behavior on scale {
                        NumberAnimation {
                            duration: 80
                            easing.type: Easing.OutCubic
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: modelData.emoji
                        font.family: "Noto Color Emoji"
                        font.pixelSize: 26
                    }

                    MouseArea {
                        id: emojiMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        onEntered: emojiGrid.currentIndex = index
                        onClicked: pickerWindow.chooseEmoji(modelData.emoji)
                    }
                }
            }

            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                    pickerWindow.closePicker(true)
                    event.accepted = true
                    return
                }

                if ((event.modifiers & Qt.ControlModifier)
                        && event.key === Qt.Key_F) {
                    if (!pickerWindow.searchMode)
                        pickerWindow.enterSearchMode()
                    else {
                        searchInput.forceActiveFocus()
                        searchInput.selectAll()
                    }
                    event.accepted = true
                    return
                }

                if (event.key === Qt.Key_Left) {
                    pickerWindow.moveGridSelection(-1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Right) {
                    pickerWindow.moveGridSelection(1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Up) {
                    if (emojiGrid.currentIndex < pickerWindow.gridColumns) {
                        searchInput.forceActiveFocus()
                    } else {
                        pickerWindow.moveGridSelection(
                            -pickerWindow.gridColumns
                        )
                    }

                    event.accepted = true
                } else if (event.key === Qt.Key_Down) {
                    pickerWindow.moveGridSelection(pickerWindow.gridColumns)
                    event.accepted = true
                } else if (event.key === Qt.Key_Return
                        || event.key === Qt.Key_Enter) {
                    if (emojiGrid.currentIndex >= 0
                            && emojiGrid.currentIndex
                                < pickerWindow.filteredEmojis.length) {
                        pickerWindow.chooseEmoji(
                            pickerWindow.filteredEmojis[
                                emojiGrid.currentIndex
                            ].emoji
                        )
                    }

                    event.accepted = true
                }
            }
        }

        // --------------------------------------------------------
        // Empty state
        // --------------------------------------------------------

        Column {
            anchors.centerIn: emojiGrid
            spacing: 6
            visible: pickerWindow.filteredEmojis.length === 0

            Text {
                anchors.horizontalCenter: parent.horizontalCenter

                text: pickerWindow.selectedCategory === "recent"
                    && pickerWindow.query.length === 0
                    ? "◷"
                    : "󰍉"

                color: Qt.alpha(Theme.fg, 0.70)

                font.family: pickerWindow.selectedCategory === "recent"
                    && pickerWindow.query.length === 0
                    ? Theme.fontMain
                    : Theme.fontIcons

                font.pixelSize: 26
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter

                text: pickerWindow.selectedCategory === "recent"
                    && pickerWindow.query.length === 0
                    ? "No recent emojis"
                    : "No emojis found"

                color: Qt.alpha(Theme.fg, 0.70)
                font.family: Theme.fontMain
                font.pixelSize: 13
            }
        }

        // --------------------------------------------------------
        // Minimal scrollbar
        // --------------------------------------------------------

        Rectangle {
            id: scrollThumb

            visible: emojiGrid.contentHeight > emojiGrid.height + 1

            anchors.right: parent.right
            anchors.rightMargin: 5

            width: 3
            radius: 1.5
            color: Qt.alpha(Theme.white, 0.48)

            readonly property real viewportRatio:
                Math.min(1, emojiGrid.height / Math.max(1, emojiGrid.contentHeight))

            readonly property real trackHeight: emojiGrid.height
            readonly property real maxTravel: Math.max(0, trackHeight - height)

            readonly property real scrollRatio:
                emojiGrid.contentHeight <= emojiGrid.height
                ? 0
                : emojiGrid.contentY
                    / (emojiGrid.contentHeight - emojiGrid.height)

            height: Math.max(30, trackHeight * viewportRatio)

            y: emojiGrid.y
                + Math.max(
                    0,
                    Math.min(maxTravel, maxTravel * scrollRatio)
                )
        }
    }
}
