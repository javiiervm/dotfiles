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

    // Keep one transparent layer surface alive at all times. Creating and
    // destroying the layer surface on every SUPER+. press was a measurable
    // part of the perceived opening delay.
    //
    // The window itself covers the screen, but `mask` makes every pixel
    // outside the emoji card click-through.
    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    visible: true
    color: "transparent"
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore

    property int popupX: edgePadding
    property int popupY: edgePadding

    property bool isOpen: false

    // QUICK MODE (default): the picker accepts pointer input but does not
    // take keyboard focus, so the original text field keeps the caret.
    // SEARCH MODE: clicking the search box temporarily enables keyboard focus.
    property bool searchMode: false
    focusable: searchMode

    // When closed the fullscreen backing surface has an empty input region,
    // so it behaves as though it were not there at all.
    mask: Region {
        x: Math.round(card.x)
        y: Math.round(card.y)
        width: pickerWindow.isOpen ? Math.round(card.width) : 0
        height: pickerWindow.isOpen ? Math.round(card.height) : 0
        radius: Math.round(card.radius)
    }

    // Keep rendering enabled. The backing surface is transparent and the card
    // is hidden when closed, so there is virtually nothing to draw. More
    // importantly, this guarantees that the "closed" frame is actually
    // presented; disabling updates in the same state change could freeze the
    // last visible card on screen and make SUPER+. appear unable to close it.
    updatesEnabled: true

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


    // -----------------------------------------------------------------
    // Fast cursor-position request
    // -----------------------------------------------------------------
    Process {
        id: pointerProbe

        // Proven reliable path: this is the same Hyprland cursor query that
        // correctly followed the mouse in the earlier working version.
        //
        // We call hyprctl directly (no bash wrapper) and react to the first
        // line immediately with SplitParser. The persistent backing surface
        // means this process launch is now the only asynchronous step left in
        // opening the picker.
        command: ["hyprctl", "cursorpos"]

        stdout: SplitParser {
            onRead: function(data) {
                if (!pickerWindow.pendingOpen
                        || pickerWindow.pointerProbeSucceeded) {
                    return
                }

                var value = data.trim()
                var parts = value.split(",")

                if (parts.length !== 2)
                    return

                var x = Number(parts[0].trim())
                var y = Number(parts[1].trim())

                if (!Number.isFinite(x) || !Number.isFinite(y))
                    return

                if (!pickerWindow.placeAtPointer(x, y))
                    return

                pickerWindow.lastPointerX = x
                pickerWindow.lastPointerY = y
                pickerWindow.hasLastPointer = true
                pickerWindow.pointerProbeSucceeded = true

                pointerTimeout.stop()
                pickerWindow.finishOpen()
            }
        }

        onRunningChanged: {
            if (running
                    || !pickerWindow.pendingOpen
                    || pickerWindow.pointerProbeSucceeded) {
                return
            }

            // Process finished without a usable coordinate.
            if (pickerWindow.hasLastPointer
                    && pickerWindow.placeAtPointer(
                        pickerWindow.lastPointerX,
                        pickerWindow.lastPointerY
                    )) {
                pickerWindow.finishOpen()
            } else {
                pickerWindow.openFallback()
            }
        }
    }

    Timer {
        id: pointerTimeout
        interval: 120
        repeat: false

        onTriggered: {
            if (!pickerWindow.pendingOpen
                    || pickerWindow.pointerProbeSucceeded) {
                return
            }

            // Safety net only. Under normal conditions hyprctl cursorpos
            // returns in a few milliseconds.
            if (pickerWindow.hasLastPointer
                    && pickerWindow.placeAtPointer(
                        pickerWindow.lastPointerX,
                        pickerWindow.lastPointerY
                    )) {
                pickerWindow.finishOpen()
            } else {
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

    property bool pendingOpen: false
    property bool openingVisual: false
    property bool pointerProbeSucceeded: false

    property bool hasLastPointer: false
    property real lastPointerX: 0
    property real lastPointerY: 0
    property bool typeNeedsFocusRestore: false
    property bool typeNeedsFocusRestoreAfterTyping: false
    property bool followMouseOverridden: false
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

    function categoryItems(categoryId) {
        var result = []

        if (categoryId === "recent") {
            for (var r = 0; r < recentEmojis.length; ++r)
                result.push(emojiObjectFor(recentEmojis[r]))

            return result
        }

        for (var i = 0; i < allEmojis.length; ++i) {
            if (allEmojis[i].category === categoryId)
                result.push(allEmojis[i])
        }

        return result
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
        }

        filteredEmojis = result
        searchGrid.currentIndex = result.length > 0 ? 0 : -1

        if (result.length > 0)
            searchGrid.positionViewAtBeginning()
    }

    function leaveSearchModeForBrowsing() {
        if (!searchMode)
            return

        searchMode = false
        focusGrab.active = false

        if (previousToplevel)
            previousToplevel.activate()
    }

    function scrollToCategory(categoryId) {
        selectedCategory = categoryId

        Qt.callLater(function() {
            for (var i = 0; i < sectionRepeater.count; ++i) {
                var section = sectionRepeater.itemAt(i)

                if (!section || section.sectionId !== categoryId)
                    continue

                var maximum = Math.max(
                    0,
                    emojiScroll.contentHeight - emojiScroll.height
                )

                var destination = Math.max(
                    0,
                    Math.min(maximum, section.y - 4)
                )

                categoryScrollAnimation.stop()
                categoryScrollAnimation.from = emojiScroll.contentY
                categoryScrollAnimation.to = destination
                categoryScrollAnimation.start()
                break
            }
        })
    }

    function updateCategoryFromScroll() {
        if (query.length > 0)
            return

        var marker = emojiScroll.contentY + 28
        var current = selectedCategory

        for (var i = 0; i < sectionRepeater.count; ++i) {
            var section = sectionRepeater.itemAt(i)

            if (!section)
                continue

            if (section.y <= marker)
                current = section.sectionId
            else
                break
        }

        selectedCategory = current
    }

    function selectCategory(categoryId) {
        if (searchInput.text.length > 0)
            searchInput.text = ""

        query = ""
        updateFiltered()
        leaveSearchModeForBrowsing()
        scrollToCategory(categoryId)
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
        pendingEmoji = ""
        typeNeedsFocusRestore = false
        typeNeedsFocusRestoreAfterTyping = false
        searchMode = false
        focusGrab.active = false

        if (searchInput.text.length > 0)
            searchInput.text = ""

        query = ""
        selectedCategory = recentEmojis.length > 0 ? "recent" : "smileys"
        updateFiltered()
    }

    function requestPointerPosition() {
        pointerProbeSucceeded = false
        pointerTimeout.restart()

        // Process is reusable. If a stale invocation is somehow still alive,
        // wait one event-loop turn after stopping it before starting the fresh
        // request for this opening.
        if (pointerProbe.running) {
            pointerProbe.running = false

            Qt.callLater(function() {
                if (pickerWindow.pendingOpen)
                    pointerProbe.running = true
            })
        } else {
            pointerProbe.running = true
        }
    }


    function openPicker() {
        if (isOpen || pendingOpen)
            return

        prepareOpenState()
        pendingOpen = true
        openingVisual = false

        requestPointerPosition()
    }

    function finishOpen() {
        if (!pendingOpen)
            return

        pointerTimeout.stop()
        pendingOpen = false
        searchMode = false

        freezeKeyboardFocusOnCurrentApp()

        // The backing surface already exists. Showing the picker now is only
        // a local QML state change, so there is no layer-surface creation
        // round-trip here.
        isOpen = true
        openingVisual = false

        Qt.callLater(function() {
            pickerWindow.openingVisual = true
            emojiScroll.contentY = 0
            pickerWindow.updateCategoryFromScroll()
        })
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
                Math.round(s.width - popupWidth - edgePadding)
            )
            popupY = Math.max(
                edgePadding,
                Math.round(s.height - popupHeight - edgePadding)
            )
        }

        finishOpen()
    }

    function closePicker(restorePreviousFocus) {
        pendingOpen = false
        pointerTimeout.stop()

        if (pointerProbe.running)
            pointerProbe.running = false

        if (!isOpen)
            return

        var hadSearchFocus = searchMode

        isOpen = false
        openingVisual = false
        focusGrab.active = false
        searchMode = false
        pendingEmoji = ""

        restoreNormalFollowMouse()

        // In quick mode the original application never lost keyboard focus.
        // Only search mode needs an explicit focus handoff back.
        if (hadSearchFocus
                && restorePreviousFocus !== false
                && previousToplevel) {
            previousToplevel.activate()
        }
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
        if (isOpen) {
            closePicker(true)
        } else if (pendingOpen) {
            pendingOpen = false
            pointerTimeout.stop()

            if (pointerProbe.running)
                pointerProbe.running = false
        } else {
            openPicker()
        }
    }

    function chooseEmoji(character) {
        if (!character || character.length === 0)
            return

        pendingEmoji = character
        rememberEmoji(character)

        var hadSearchFocus = searchMode
        typeNeedsFocusRestore = hadSearchFocus
        typeNeedsFocusRestoreAfterTyping = true

        isOpen = false
        openingVisual = false
        focusGrab.active = false
        searchMode = false

        if (hadSearchFocus && previousToplevel)
            previousToplevel.activate()

        // In quick mode the original field still owns focus, so only a tiny
        // delay is needed to let the pointer click finish. Search mode needs
        // time for the previous application to regain keyboard focus.
        typeTimer.interval = hadSearchFocus ? 160 : 30
        typeTimer.restart()
    }

    function moveGridSelection(delta) {
        if (filteredEmojis.length === 0)
            return

        var next = searchGrid.currentIndex

        if (next < 0)
            next = 0
        else
            next = Math.max(0, Math.min(filteredEmojis.length - 1, next + delta))

        searchGrid.currentIndex = next
        searchGrid.positionViewAtIndex(next, GridView.Contain)
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
            // This is used only while search mode owns the keyboard.
            if (pickerWindow.isOpen && pickerWindow.searchMode)
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

    // Runtime Hyprland focus policy override. The user's configuration is
    // Lua-based, so use `hyprctl eval` rather than `hyprctl keyword`. Mode 2
    // keeps keyboard focus on the original editor while the pointer travels
    // across other windows.
    Process {
        id: followMouseFreezeProc
        command: [
            "hyprctl",
            "eval",
            "hl.config({ input = { follow_mouse = 2 } })"
        ]
    }

    Process {
        id: followMouseRestoreProc
        command: [
            "hyprctl",
            "eval",
            "hl.config({ input = { follow_mouse = 1 } })"
        ]
    }

    Timer {
        id: searchFocusTimer
        interval: 35
        repeat: false

        onTriggered: {
            if (!pickerWindow.isOpen || !pickerWindow.searchMode)
                return

            focusGrab.active = true
            searchInput.forceActiveFocus()
            searchInput.selectAll()
        }
    }

    Timer {
        id: typeTimer
        interval: 30
        repeat: false

        onTriggered: {
            if (!pickerWindow.pendingEmoji) {
                pickerWindow.restoreNormalFollowMouse()
                return
            }

            // Direct Unicode typing: the clipboard is never touched.
            typeProcess.command = ["wtype", pickerWindow.pendingEmoji]
            typeProcess.running = true
            pickerWindow.pendingEmoji = ""
            pickerWindow.typeNeedsFocusRestore = false
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
        x: Math.round(card.x)
        y: Math.round(card.y)
        width: pickerWindow.isOpen ? Math.round(card.width) : 0
        height: pickerWindow.isOpen ? Math.round(card.height) : 0
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

        opacity: pickerWindow.openingVisual ? 1.0 : 0.0
        scale: pickerWindow.openingVisual ? 1.0 : 0.965

        Behavior on opacity {
            NumberAnimation {
                duration: 95
                easing.type: Easing.OutCubic
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutBack
            }
        }

        // --------------------------------------------------------
        // Draggable handle
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

                width: 42
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
                hoverEnabled: true
                preventStealing: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                property real startPointerX: 0
                property real startPointerY: 0
                property real startPopupX: 0
                property real startPopupY: 0

                function pointInWindow(mouse) {
                    // The fullscreen backing PanelWindow never moves, so this
                    // coordinate system is stable for the whole drag gesture.
                    return pickerWindow.mapFromItem(
                        dragHandleArea,
                        mouse.x,
                        mouse.y
                    )
                }

                onPressed: function(mouse) {
                    var point = pointInWindow(mouse)

                    startPointerX = point.x
                    startPointerY = point.y
                    startPopupX = pickerWindow.popupX
                    startPopupY = pickerWindow.popupY
                }

                onPositionChanged: function(mouse) {
                    if (!pressed || !pickerWindow.targetScreen)
                        return

                    var point = pointInWindow(mouse)

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

                    pickerWindow.popupX = pickerWindow.clamp(
                        Math.round(
                            startPopupX + point.x - startPointerX
                        ),
                        pickerWindow.edgePadding,
                        maxX
                    )

                    pickerWindow.popupY = pickerWindow.clamp(
                        Math.round(
                            startPopupY + point.y - startPointerY
                        ),
                        pickerWindow.edgePadding,
                        maxY
                    )
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
        // Category shortcuts
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

                    property bool recentUnavailable:
                        modelData.id === "recent"
                        && pickerWindow.recentEmojis.length === 0

                    opacity: recentUnavailable ? 0.42 : 1.0

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
                        enabled: !parent.recentUnavailable
                        cursorShape: enabled
                            ? Qt.PointingHandCursor
                            : Qt.ArrowCursor

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
                        searchGrid.currentIndex = Math.max(
                            0,
                            searchGrid.currentIndex
                        )
                        searchGrid.forceActiveFocus()
                        searchGrid.positionViewAtIndex(
                            searchGrid.currentIndex,
                            GridView.Contain
                        )
                        event.accepted = true
                        return
                    }

                    if ((event.key === Qt.Key_Return
                            || event.key === Qt.Key_Enter)
                            && pickerWindow.filteredEmojis.length > 0) {
                        pickerWindow.chooseEmoji(
                            pickerWindow.filteredEmojis[0].emoji
                        )
                        event.accepted = true
                    }
                }
            }

            // Quick mode normally leaves keyboard focus in the original app.
            // Clicking Search explicitly switches the picker into focus mode.
            MouseArea {
                anchors.fill: parent
                visible: !pickerWindow.searchMode
                cursorShape: Qt.IBeamCursor
                onClicked: pickerWindow.enterSearchMode()
            }
        }

        // --------------------------------------------------------
        // Continuous category list
        // --------------------------------------------------------

        Flickable {
            id: emojiScroll

            visible: pickerWindow.query.length === 0

            anchors {
                left: parent.left
                right: parent.right
                top: searchBox.bottom
                bottom: parent.bottom
                leftMargin: 15
                rightMargin: 15
                topMargin: 10
                bottomMargin: 11
            }

            clip: true
            contentWidth: width
            contentHeight: sectionsColumn.height
            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: 2600

            onContentYChanged: pickerWindow.updateCategoryFromScroll()

            NumberAnimation {
                id: categoryScrollAnimation
                target: emojiScroll
                property: "contentY"
                duration: 180
                easing.type: Easing.OutCubic
            }

            Column {
                id: sectionsColumn

                width: emojiScroll.width
                spacing: 11

                Repeater {
                    id: sectionRepeater
                    model: pickerWindow.categories

                    Column {
                        required property var modelData

                        property string sectionId: modelData.id
                        property var sectionItems:
                            pickerWindow.categoryItems(sectionId)

                        width: sectionsColumn.width
                        spacing: 6

                        Text {
                            width: parent.width

                            text: parent.modelData.label
                            color: Qt.alpha(Theme.white, 0.93)
                            font.family: Theme.fontMain
                            font.pixelSize: 13
                            font.bold: true
                        }

                        GridView {
                            id: sectionGrid

                            width: parent.width
                            height: sectionItems.length > 0
                                ? Math.ceil(
                                    sectionItems.length
                                        / pickerWindow.gridColumns
                                  ) * 48
                                : 0

                            interactive: false
                            clip: false

                            cellWidth: width / pickerWindow.gridColumns
                            cellHeight: 48
                            model: sectionItems

                            delegate: Item {
                                required property var modelData

                                width: sectionGrid.cellWidth
                                height: sectionGrid.cellHeight

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 43
                                    height: 43
                                    radius: 10

                                    color: emojiMouse.containsMouse
                                        ? Qt.alpha(Theme.white, 0.07)
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

                                        onClicked:
                                            pickerWindow.chooseEmoji(
                                                modelData.emoji
                                            )
                                    }
                                }
                            }
                        }

                        Text {
                            visible:
                                parent.sectionId === "recent"
                                && parent.sectionItems.length === 0

                            width: parent.width
                            height: visible ? 38 : 0

                            text: "No recent emojis yet"
                            color: Qt.alpha(Theme.fg, 0.60)
                            font.family: Theme.fontMain
                            font.pixelSize: 12
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }

        // --------------------------------------------------------
        // Search results
        // --------------------------------------------------------

        Text {
            id: searchResultsTitle

            visible: pickerWindow.query.length > 0

            anchors {
                left: parent.left
                top: searchBox.bottom
                leftMargin: 18
                topMargin: 12
            }

            text: "Search results"
            color: Qt.alpha(Theme.white, 0.93)
            font.family: Theme.fontMain
            font.pixelSize: 13
            font.bold: true
        }

        GridView {
            id: searchGrid

            visible: pickerWindow.query.length > 0

            anchors {
                left: parent.left
                right: parent.right
                top: searchResultsTitle.bottom
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

                width: searchGrid.cellWidth
                height: searchGrid.cellHeight

                Rectangle {
                    anchors.centerIn: parent
                    width: 43
                    height: 43
                    radius: 10

                    property bool selected: searchGrid.currentIndex === index

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

                        onEntered: searchGrid.currentIndex = index
                        onClicked:
                            pickerWindow.chooseEmoji(modelData.emoji)
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
                    if (searchGrid.currentIndex
                            < pickerWindow.gridColumns) {
                        searchInput.forceActiveFocus()
                    } else {
                        pickerWindow.moveGridSelection(
                            -pickerWindow.gridColumns
                        )
                    }

                    event.accepted = true
                } else if (event.key === Qt.Key_Down) {
                    pickerWindow.moveGridSelection(
                        pickerWindow.gridColumns
                    )
                    event.accepted = true
                } else if (event.key === Qt.Key_Return
                        || event.key === Qt.Key_Enter) {
                    if (searchGrid.currentIndex >= 0
                            && searchGrid.currentIndex
                                < pickerWindow.filteredEmojis.length) {
                        pickerWindow.chooseEmoji(
                            pickerWindow.filteredEmojis[
                                searchGrid.currentIndex
                            ].emoji
                        )
                    }

                    event.accepted = true
                }
            }
        }

        // Search empty state.
        Column {
            anchors.centerIn: searchGrid
            spacing: 6

            visible:
                pickerWindow.query.length > 0
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
        // Minimal scrollbar for whichever view is active
        // --------------------------------------------------------

        Rectangle {
            id: scrollThumb

            readonly property var activeView:
                pickerWindow.query.length > 0
                    ? searchGrid
                    : emojiScroll

            visible:
                activeView.visible
                && activeView.contentHeight > activeView.height + 1

            anchors.right: parent.right
            anchors.rightMargin: 5

            width: 3
            radius: 1.5
            color: Qt.alpha(Theme.white, 0.48)

            readonly property real viewportRatio:
                Math.min(
                    1,
                    activeView.height
                        / Math.max(1, activeView.contentHeight)
                )

            readonly property real trackHeight: activeView.height
            readonly property real maxTravel:
                Math.max(0, trackHeight - height)

            readonly property real scrollRatio:
                activeView.contentHeight <= activeView.height
                    ? 0
                    : activeView.contentY
                        / (activeView.contentHeight - activeView.height)

            height: Math.max(30, trackHeight * viewportRatio)

            y: activeView.y
                + Math.max(
                    0,
                    Math.min(maxTravel, maxTravel * scrollRatio)
                )
        }
    }
}
