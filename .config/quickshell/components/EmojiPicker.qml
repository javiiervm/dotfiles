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

    // Keep the layer-shell surface stationary and fullscreen. The emoji card
    // itself moves inside this surface. This is crucial for smooth dragging:
    // changing layer-shell margins every pointer event makes the compositor
    // reposition the Wayland surface asynchronously, which lags behind the
    // physical mouse.
    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    property int popupX: edgePadding
    property int popupY: edgePadding
    property bool isOpen: false

    // During a drag, freeze the compositor input region at the press position.
    // The implicit pointer grab keeps delivering motion events anyway. On
    // release the mask jumps once to the final card position instead of being
    // recommitted to Wayland for every single mouse event.
    property bool draggingCard: false
    property int dragMaskX: popupX
    property int dragMaskY: popupY

    visible: true
    color: "transparent"

    // Search owns keyboard focus only while the picker is actually open.
    property bool searchMode: false
    focusable: searchMode

    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore

    // Everything outside the card is click-through. This preserves the current
    // outside-click dismissal behavior even though the backing surface fills
    // the monitor.
    mask: Region {
        x: pickerWindow.draggingCard
            ? pickerWindow.dragMaskX
            : pickerWindow.popupX
        y: pickerWindow.draggingCard
            ? pickerWindow.dragMaskY
            : pickerWindow.popupY
        width: pickerWindow.isOpen ? pickerWindow.popupWidth : 0
        height: pickerWindow.isOpen ? pickerWindow.popupHeight : 0
        radius: 20
    }

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

    // Prebuilt browse model: section header rows + rows of up to 7 emojis.
    // ListView virtualizes these rows, so all categories can live in one
    // continuous scroll without instantiating ~1800 emoji delegates at once.
    property var browseRows: []
    property var browseEmojis: []
    property var browseEmojiIndexToRow: []
    property var displayRows: []
    property var emojiIndexToRow: []
    property var categoryStartRows: ({})
    property var categoryStartY: ({})
    property int currentEmojiIndex: -1
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

    function appendEmojiRows(rows, flat, indexToRow, items, categoryId) {
        for (var offset = 0; offset < items.length; offset += gridColumns) {
            var chunk = items.slice(
                offset,
                Math.min(items.length, offset + gridColumns)
            )
            var rowIndex = rows.length
            var startIndex = flat.length

            rows.push({
                kind: "emojis",
                category: categoryId,
                startIndex: startIndex,
                items: chunk
            })

            for (var i = 0; i < chunk.length; ++i) {
                flat.push(chunk[i])
                indexToRow.push(rowIndex)
            }
        }
    }

    function buildBrowseRows() {
        var grouped = ({})

        for (var c = 0; c < categories.length; ++c)
            grouped[categories[c].id] = []

        for (var i = 0; i < allEmojis.length; ++i) {
            var item = allEmojis[i]

            if (grouped[item.category] !== undefined)
                grouped[item.category].push(item)
        }

        var rows = []
        var flat = []
        var indexToRow = []
        var starts = ({})
        var startsY = ({})
        var runningY = 0

        // Keep the geometry constants in sync with the ListView delegate.
        var headerHeight = 30
        var emojiRowHeight = 48
        var emptyRecentHeight = 34

        for (var categoryIndex = 0;
                categoryIndex < categories.length;
                ++categoryIndex) {
            var category = categories[categoryIndex]
            var sectionItems = []

            starts[category.id] = rows.length
            startsY[category.id] = runningY

            rows.push({
                kind: "header",
                category: category.id,
                label: category.label
            })
            runningY += headerHeight

            if (category.id === "recent") {
                for (var r = 0; r < recentEmojis.length; ++r)
                    sectionItems.push(emojiObjectFor(recentEmojis[r]))
            } else {
                sectionItems = grouped[category.id] || []
            }

            if (category.id === "recent" && sectionItems.length === 0) {
                rows.push({
                    kind: "emptyRecent",
                    category: "recent",
                    label: "No recent emojis"
                })
                runningY += emptyRecentHeight
                continue
            }

            var rowsBefore = rows.length
            appendEmojiRows(
                rows,
                flat,
                indexToRow,
                sectionItems,
                category.id
            )
            runningY += (rows.length - rowsBefore) * emojiRowHeight
        }

        browseRows = rows
        browseEmojis = flat
        browseEmojiIndexToRow = indexToRow
        categoryStartRows = starts
        categoryStartY = startsY

        if (query.trim().length === 0) {
            displayRows = browseRows
            filteredEmojis = browseEmojis
            emojiIndexToRow = browseEmojiIndexToRow
            currentEmojiIndex = filteredEmojis.length > 0 ? 0 : -1
        }
    }

    function buildSearchRows(results) {
        var rows = [{
            kind: "header",
            category: "search",
            label: "Search results"
        }]
        var flat = []
        var indexToRow = []

        appendEmojiRows(
            rows,
            flat,
            indexToRow,
            results,
            "search"
        )

        displayRows = rows
        filteredEmojis = flat
        emojiIndexToRow = indexToRow
        currentEmojiIndex = flat.length > 0 ? 0 : -1
    }

    function updateFiltered() {
        var needle = normalized(query).trim()

        if (needle.length === 0) {
            displayRows = browseRows
            filteredEmojis = browseEmojis
            emojiIndexToRow = browseEmojiIndexToRow
            currentEmojiIndex = filteredEmojis.length > 0 ? 0 : -1
            return
        }

        var result = []

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

        buildSearchRows(result)

        if (emojiList)
            emojiList.positionViewAtBeginning()
    }

    function jumpToCategory(categoryId) {
        if (query.length > 0 || searchInput.text.length > 0) {
            searchInput.text = ""
            query = ""
            updateFiltered()
        }

        var rowIndex = categoryStartRows[categoryId]

        if (rowIndex === undefined)
            return

        selectedCategory = categoryId
        emojiList.positionViewAtIndex(rowIndex, ListView.Beginning)

        if (searchMode)
            searchInput.forceActiveFocus()
    }

    function selectCategory(categoryId) {
        jumpToCategory(categoryId)
    }

    function syncCategoryFromScroll() {
        if (query.length > 0 || displayRows.length === 0)
            return

        var probeY = emojiList.contentY + 8
        var active = categories[0].id

        for (var i = 0; i < categories.length; ++i) {
            var id = categories[i].id
            var startY = categoryStartY[id]

            if (startY !== undefined && startY <= probeY)
                active = id
            else
                break
        }

        selectedCategory = active
    }

    function positionEmojiIndex(index) {
        if (index < 0 || index >= emojiIndexToRow.length)
            return

        var rowIndex = emojiIndexToRow[index]

        if (rowIndex !== undefined)
            emojiList.positionViewAtIndex(rowIndex, ListView.Contain)
    }

    function rememberEmoji(character) {
        var next = [character]

        for (var i = 0; i < recentEmojis.length && next.length < maxRecents; ++i) {
            if (recentEmojis[i] !== character)
                next.push(recentEmojis[i])
        }

        recentEmojis = next
        recentFile.setText(JSON.stringify(next))
        browseRebuildTimer.restart()
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

        // Empty-query browsing is already precomputed. Opening only swaps
        // references and picks the initial scroll position.
        displayRows = browseRows
        filteredEmojis = browseEmojis
        emojiIndexToRow = browseEmojiIndexToRow
        currentEmojiIndex = filteredEmojis.length > 0 ? 0 : -1
    }

    function openPicker() {
        if (isOpen || pendingOpen)
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
        isOpen = true

        var initialRow = categoryStartRows[selectedCategory]
        if (initialRow !== undefined)
            emojiList.positionViewAtIndex(initialRow, ListView.Beginning)

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

        if (!isOpen)
            return

        isOpen = false
        draggingCard = false
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
        if (!isOpen || searchMode)
            return

        searchMode = true

        // Let layer-shell update keyboard interactivity first, then ask the
        // TextInput for focus.
        searchFocusTimer.restart()
    }

    function togglePicker() {
        if (isOpen)
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

        isOpen = false
        draggingCard = false
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

        var next = currentEmojiIndex

        if (next < 0)
            next = 0
        else
            next = Math.max(
                0,
                Math.min(filteredEmojis.length - 1, next + delta)
            )

        currentEmojiIndex = next
        positionEmojiIndex(next)
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

        buildBrowseRows()
        selectedCategory = recentEmojis.length > 0 ? "recent" : "smileys"
        updateFiltered()
    }

    Timer {
        id: browseRebuildTimer
        interval: 0
        repeat: false

        onTriggered: {
            buildBrowseRows()

            // The picker is normally already closing when recents change.
            // If it is still visible for any reason, preserve the live view.
            if (pickerWindow.isOpen && pickerWindow.query.length === 0)
                pickerWindow.syncCategoryFromScroll()
        }
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
            if (pickerWindow.isOpen)
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
            if (!pickerWindow.isOpen)
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

    // The backing PanelWindow now fills the monitor, so the blur region must
    // follow the card's actual position inside that window. Keeping it at (0,0)
    // would leave a permanent blurred rectangle in the top-left and would make
    // the moved card itself look transparent.
    //
    // Disable the compositor blur region completely while the picker is closed,
    // so the always-alive transparent backing surface has zero visual cost.
    BackgroundEffect.blurRegion:
        Glass.blurEnabled && pickerWindow.isOpen
            ? pickerBlurRegion
            : null

    Region {
        id: pickerBlurRegion
        x: Math.round(card.x)
        y: Math.round(card.y)
        width: Math.round(card.width)
        height: Math.round(card.height)
        radius: Math.round(card.radius)
    }

    GlassSurface {
        id: card

        x: pickerWindow.popupX
        y: pickerWindow.popupY

        width: pickerWindow.popupWidth
        height: pickerWindow.popupHeight
        visible: pickerWindow.isOpen

        glassRadius: 20
        showBorder: true
        showHighlight: true
        clip: true

        // --------------------------------------------------------
        // Tiny header: handle + close, similar visual weight to Win11
        // --------------------------------------------------------

        Item {
            id: dragHandleArea

            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
            }

            width: 100
            height: 31

            Rectangle {
                anchors.centerIn: parent

                width: 38
                height: dragMouse.pressed ? 5 : 4
                radius: 2.5

                color: dragMouse.containsMouse || dragMouse.pressed
                    ? Qt.alpha(Theme.white, 0.88)
                    : Qt.alpha(Theme.white, 0.60)

                Behavior on color {
                    ColorAnimation { duration: 90 }
                }

                Behavior on height {
                    NumberAnimation { duration: 90 }
                }
            }

            MouseArea {
                id: dragMouse

                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                hoverEnabled: true
                preventStealing: true
                cursorShape: pressed
                    ? Qt.ClosedHandCursor
                    : Qt.OpenHandCursor

                property real pressPointerX: 0
                property real pressPointerY: 0
                property real pressPopupX: 0
                property real pressPopupY: 0

                function pointInBackingWindow(mouse) {
                    // The fullscreen PanelWindow never moves, so these are
                    // stable logical-pixel coordinates for the entire gesture.
                    // No physical/logical scaling conversion is necessary.
                    return pickerWindow.mapFromItem(
                        dragHandleArea,
                        mouse.x,
                        mouse.y
                    )
                }

                onPressed: function(mouse) {
                    var point = pointInBackingWindow(mouse)

                    pressPointerX = point.x
                    pressPointerY = point.y
                    pressPopupX = pickerWindow.popupX
                    pressPopupY = pickerWindow.popupY

                    pickerWindow.dragMaskX = pickerWindow.popupX
                    pickerWindow.dragMaskY = pickerWindow.popupY
                    pickerWindow.draggingCard = true

                    mouse.accepted = true
                }

                onPositionChanged: function(mouse) {
                    if (!pressed || !pickerWindow.targetScreen)
                        return

                    var point = pointInBackingWindow(mouse)

                    var maxX = Math.max(
                        pickerWindow.edgePadding,
                        pickerWindow.width
                            - pickerWindow.popupWidth
                            - pickerWindow.edgePadding
                    )

                    var maxY = Math.max(
                        pickerWindow.edgePadding,
                        pickerWindow.height
                            - pickerWindow.popupHeight
                            - pickerWindow.edgePadding
                    )

                    // Pure QML item movement: no hyprctl, no timer and no
                    // layer-shell surface repositioning in the hot path.
                    pickerWindow.popupX = pickerWindow.clamp(
                        Math.round(
                            pressPopupX + point.x - pressPointerX
                        ),
                        pickerWindow.edgePadding,
                        maxX
                    )

                    pickerWindow.popupY = pickerWindow.clamp(
                        Math.round(
                            pressPopupY + point.y - pressPointerY
                        ),
                        pickerWindow.edgePadding,
                        maxY
                    )
                }

                onReleased: {
                    pickerWindow.draggingCard = false
                }

                onCanceled: {
                    pickerWindow.draggingCard = false
                }
            }
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
                        pickerWindow.currentEmojiIndex = Math.max(
                            0,
                            pickerWindow.currentEmojiIndex
                        )
                        emojiList.forceActiveFocus()
                        pickerWindow.positionEmojiIndex(
                            pickerWindow.currentEmojiIndex
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
        // Continuous category list
        // --------------------------------------------------------

        ListView {
            id: emojiList

            anchors {
                left: parent.left
                right: parent.right
                top: searchBox.bottom
                bottom: parent.bottom
                leftMargin: 15
                rightMargin: 15
                topMargin: 7
                bottomMargin: 11
            }

            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: 2600
            spacing: 0
            model: pickerWindow.displayRows
            reuseItems: true

            onContentYChanged: pickerWindow.syncCategoryFromScroll()

            delegate: Item {
                id: rowRoot

                required property var modelData
                required property int index

                width: emojiList.width
                height: modelData.kind === "header"
                    ? 30
                    : (modelData.kind === "emptyRecent" ? 34 : 48)

                Text {
                    visible: rowRoot.modelData.kind === "header"

                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                        leftMargin: 3
                    }

                    text: rowRoot.modelData.label || ""
                    color: Qt.alpha(Theme.white, 0.93)
                    font.family: Theme.fontMain
                    font.pixelSize: 13
                    font.bold: true
                }

                Text {
                    visible: rowRoot.modelData.kind === "emptyRecent"

                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                        leftMargin: 3
                    }

                    text: "No recent emojis"
                    color: Qt.alpha(Theme.fg, 0.55)
                    font.family: Theme.fontMain
                    font.pixelSize: 12
                }

                Row {
                    visible: rowRoot.modelData.kind === "emojis"
                    anchors.fill: parent
                    spacing: 0

                    Repeater {
                        model: rowRoot.modelData.items || []

                        Item {
                            required property var modelData
                            required property int index

                            width: emojiList.width / pickerWindow.gridColumns
                            height: 48

                            readonly property int emojiIndex:
                                rowRoot.modelData.startIndex + index

                            Rectangle {
                                anchors.centerIn: parent
                                width: 43
                                height: 43
                                radius: 10

                                property bool selected:
                                    pickerWindow.currentEmojiIndex
                                    === parent.emojiIndex

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

                                    onEntered:
                                        pickerWindow.currentEmojiIndex
                                        = parent.parent.emojiIndex

                                    onClicked:
                                        pickerWindow.chooseEmoji(modelData.emoji)
                                }
                            }
                        }
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
                    searchInput.forceActiveFocus()
                    searchInput.selectAll()
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
                    if (pickerWindow.currentEmojiIndex
                            < pickerWindow.gridColumns) {
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
                    if (pickerWindow.currentEmojiIndex >= 0
                            && pickerWindow.currentEmojiIndex
                                < pickerWindow.filteredEmojis.length) {
                        pickerWindow.chooseEmoji(
                            pickerWindow.filteredEmojis[
                                pickerWindow.currentEmojiIndex
                            ].emoji
                        )
                    }

                    event.accepted = true
                }
            }
        }

        // Search-only empty state. Normal browsing always has category headers.
        Column {
            anchors.centerIn: emojiList
            spacing: 6
            visible: pickerWindow.query.length > 0
                && pickerWindow.filteredEmojis.length === 0

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "󰍉"
                color: Qt.alpha(Theme.fg, 0.70)
                font.family: Theme.fontIcons
                font.pixelSize: 26
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "No emojis found"
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

            visible: emojiList.contentHeight > emojiList.height + 1

            anchors.right: parent.right
            anchors.rightMargin: 5

            width: 3
            radius: 1.5
            color: Qt.alpha(Theme.white, 0.48)

            readonly property real viewportRatio:
                Math.min(1, emojiList.height / Math.max(1, emojiList.contentHeight))

            readonly property real trackHeight: emojiList.height
            readonly property real maxTravel: Math.max(0, trackHeight - height)

            readonly property real scrollRatio:
                emojiList.contentHeight <= emojiList.height
                ? 0
                : emojiList.contentY
                    / (emojiList.contentHeight - emojiList.height)

            height: Math.max(30, trackHeight * viewportRatio)

            y: emojiList.y
                + Math.max(
                    0,
                    Math.min(maxTravel, maxTravel * scrollRatio)
                )
        }
    }
}
