import QtQuick
import Quickshell.Io
import ".."

// Embedded in components/Launcher.qml: this is NOT another PanelWindow.
// The Python helper runs only when Settings is opened or Apply is clicked.
FocusScope {
    id: settings
    height: 578
    focus: visible
    signal requestBack()

    property int selectedTab: 0
    // Focus stays in this FocusScope except while an input is being edited.
    // 0/1 = tabs, 2.. = settings, next two = Discard / Apply.
    property int keyboardIndex: 0
    property int pickerIndex: 0  // 0..2 RGB, 3..18 presets, 19 Done
    property var editOriginal: null
    property string editingKey: ""
    readonly property int fieldCount: selectedTab === 0 ? hyprFields.length : quickFields.length
    readonly property var currentFields: selectedTab === 0 ? hyprFields : quickFields
    readonly property var presetColors: [
        "#61afef", "#c678dd", "#e08c75", "#98c379",
        "#e5c07b", "#ff6b9d", "#55c8c6", "#ffffff",
        "#101013", "#282c34", "#3e4451", "#4066ad",
        "#a855f7", "#ed4245", "#f59e0b", "#000000"
    ]
    property var values: ({})
    property var savedValues: ({})
    property var savedRevisions: ({})
    property bool loaded: false
    property bool busy: false
    property bool dirty: false
    property bool hasError: false
    property string statusText: "Open Settings to load values."

    // Inline color chooser. No separate window, external tool or background process.
    property bool colorPickerOpen: false
    property string pickerKey: ""
    property string pickerTitle: ""
    property int pickerRed: 0
    property int pickerGreen: 0
    property int pickerBlue: 0
    readonly property string backend: "/home/javier/.config/quickshell/settings/settings_backend.py"

    readonly property var hyprFields: [
        { key: "hypr_blur_enabled", label: "Window blur", detail: "Blur behind transparent windows.", kind: "toggle" },
        { key: "hypr_blur_size", label: "Blur size", detail: "Blur kernel size (1–12).", kind: "number" },
        { key: "hypr_blur_passes", label: "Blur passes", detail: "Blur quality / GPU work (1–5).", kind: "number" },
        { key: "hypr_active_opacity", label: "Focused opacity", detail: "Opacity of the active window (0.35–1).", kind: "number" },
        { key: "hypr_inactive_opacity", label: "Unfocused opacity", detail: "Opacity of inactive windows (0.35–1).", kind: "number" },
        { key: "hypr_rounding", label: "Corner radius", detail: "Hyprland window rounding (0–30).", kind: "number" },
        { key: "hypr_gaps_in", label: "Inner gaps", detail: "Space between tiled windows (0–30).", kind: "number" },
        { key: "hypr_border_size", label: "Border width", detail: "Window border width (0–8).", kind: "number" },
        { key: "hypr_animations", label: "Window animations", detail: "Enable Hyprland animations.", kind: "toggle" }
    ]
    readonly property var quickFields: [
        { key: "glass_tint", label: "Glass tint", detail: "Tint color (#RRGGBB).", kind: "color" },
        { key: "glass_opacity", label: "Glass opacity", detail: "Opacity of glass surfaces (0.05–1).", kind: "number" },
        { key: "glass_blur", label: "Shell blur", detail: "Blur behind supported Quickshell surfaces.", kind: "toggle" },
        { key: "glass_border", label: "Border opacity", detail: "Opacity of glass borders (0–1).", kind: "number" },
        { key: "glass_radius", label: "Glass radius", detail: "Default rounding of glass surfaces (0–32).", kind: "number" },
        { key: "theme_accent", label: "Accent color", detail: "Theme.blue (#RRGGBB).", kind: "color" },
        { key: "theme_background", label: "Background color", detail: "Theme.bg0 (#RRGGBB).", kind: "color" }
    ]

    function valueString(key) {
        var value = values[key]
        return value === undefined || value === null ? "" : String(value)
    }

    function setValue(key, value) {
        if (!loaded || busy || values[key] === value)
            return
        var next = Object.assign({}, values)
        next[key] = value
        values = next
        dirty = JSON.stringify(values) !== JSON.stringify(savedValues)
        hasError = false
        statusText = dirty ? "Unsaved changes" : "No unsaved changes"
    }

    function validHex(value) {
        return /^#[0-9a-fA-F]{6}$/.test(String(value || ""))
    }

    function safeColor(key) {
        var current = valueString(key)
        if (validHex(current)) return current
        var previous = savedValues[key]
        return validHex(previous) ? previous : "#808080"
    }

    function hexByte(value) {
        var digits = Math.max(0, Math.min(255, Math.round(value))).toString(16)
        return digits.length < 2 ? "0" + digits : digits
    }

    function rgbHex(red, green, blue) {
        return "#" + hexByte(red) + hexByte(green) + hexByte(blue)
    }

    function pickerChannel(index) {
        return index === 0 ? pickerRed : (index === 1 ? pickerGreen : pickerBlue)
    }

    function setPickerChannel(index, number) {
        if (!colorPickerOpen || !loaded || busy) return
        var v = Math.max(0, Math.min(255, Math.round(number)))
        if (index === 0) pickerRed = v
        else if (index === 1) pickerGreen = v
        else pickerBlue = v
        setValue(pickerKey, rgbHex(pickerRed, pickerGreen, pickerBlue))
    }

    function choosePreset(hex) {
        if (!colorPickerOpen || !validHex(hex)) return
        pickerRed = parseInt(hex.substring(1, 3), 16)
        pickerGreen = parseInt(hex.substring(3, 5), 16)
        pickerBlue = parseInt(hex.substring(5, 7), 16)
        setValue(pickerKey, hex.toLowerCase())
    }

    function openColorPicker(key, label) {
        if (!loaded || busy) return
        var hex = safeColor(key)
        pickerKey = key
        pickerTitle = label
        pickerRed = parseInt(hex.substring(1, 3), 16)
        pickerGreen = parseInt(hex.substring(3, 5), 16)
        pickerBlue = parseInt(hex.substring(5, 7), 16)
        pickerIndex = 0
        colorPickerOpen = true
        settings.forceActiveFocus()
    }

    function closeColorPicker() {
        colorPickerOpen = false
        pickerKey = ""
        settings.forceActiveFocus()
    }

    function openPanel() {
        colorPickerOpen = false
        selectedTab = 0
        keyboardIndex = 0
        pickerIndex = 0
        editingKey = ""
        loaded = false
        savedRevisions = ({})
        dirty = false
        hasError = false
        statusText = "Reading configuration..."
        if (!readProc.running && !saveProc.running) {
            busy = true
            readProc.running = true
        }
        Qt.callLater(function() { settings.forceActiveFocus() })
    }

    function discardChanges() {
        if (!loaded || busy) return
        closeColorPicker()
        values = Object.assign({}, savedValues)
        dirty = false
        hasError = false
        statusText = "Changes discarded"
    }

    function applyChanges() {
        if (!loaded || busy || !dirty) return
        // Validate ALL controls first. The helper only writes on success.
        busy = true
        hasError = false
        statusText = "Applying settings..."
        saveProc.command = ["python3", backend, "apply",
                            JSON.stringify({values: values, revisions: savedRevisions})]
        saveProc.running = true
    }

    // Keyboard navigation is event-driven; no timers, polling or extra processes.
    function selectKeyboard(index, wrap) {
        var count = 4 + fieldCount
        keyboardIndex = wrap ? (index % count + count) % count
                             : Math.max(0, Math.min(count - 1, index))
        if (keyboardIndex >= 2 && keyboardIndex < 2 + fieldCount) {
            // 69px row + 8px gap, with enough margin to show focus clearly.
            var y = (keyboardIndex - 2) * 77
            if (y < rowsScroll.contentY)
                rowsScroll.contentY = y
            else if (y + 69 > rowsScroll.contentY + rowsScroll.height)
                rowsScroll.contentY = Math.min(Math.max(0, rowsScroll.contentHeight - rowsScroll.height),
                                               y + 69 - rowsScroll.height)
        }
    }

    function switchTab(tab) {
        selectedTab = Math.max(0, Math.min(1, tab))
        keyboardIndex = selectedTab
        rowsScroll.contentY = 0
        forceActiveFocus()
    }

    function activateSelection() {
        if (busy) return
        if (keyboardIndex <= 1) {
            switchTab(keyboardIndex)
        } else if (keyboardIndex < 2 + fieldCount) {
            if (!loaded) return
            var field = currentFields[keyboardIndex - 2]
            if (field.kind === "toggle") {
                setValue(field.key, !values[field.key])
            } else if (field.kind === "color") {
                openColorPicker(field.key, field.label)
            } else {
                focusSelectedEntry()
            }
        } else if (keyboardIndex === 2 + fieldCount) {
            discardChanges()
        } else {
            applyChanges()
        }
    }

    function focusSelectedEntry() {
        // The Repeater delegate may have been recreated after changing tabs.
        var item = rowsRepeater.itemAt(keyboardIndex - 2)
        if (!item || !item.valueEditor) return
        item.valueEditor.forceActiveFocus()
        item.valueEditor.selectAll()
    }

    function beginTextEdit(key) {
        editingKey = key
        editOriginal = values[key]
    }

    function endTextEdit(key, text, cancel, step) {
        var result = cancel ? editOriginal : text.trim()
        // Preserve the numeric type of the original JSON values. Otherwise
        // pressing Enter on an unchanged "8" would mark the setting as dirty.
        if (!cancel && result !== "") {
            for (var i = 0; i < currentFields.length; ++i) {
                var field = currentFields[i]
                if (field.key === key && field.kind === "number" && isFinite(Number(result))) {
                    result = Number(result)
                    break
                }
            }
        }
        setValue(key, result)
        editingKey = ""
        forceActiveFocus()
        if (step !== 0) selectKeyboard(keyboardIndex + step, false)
    }

    function handlePickerKey(event) {
        var k = event.key
        if (k === Qt.Key_Escape || k === Qt.Key_Backspace) {
            closeColorPicker()
            return true
        }
        if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
            var delta = k === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1
            pickerIndex = (pickerIndex + delta + 20) % 20
            return true
        }
        if (k === Qt.Key_Left || k === Qt.Key_Right) {
            var dir = k === Qt.Key_Right ? 1 : -1
            if (pickerIndex <= 2) {
                setPickerChannel(pickerIndex, pickerChannel(pickerIndex) + dir *
                                 ((event.modifiers & Qt.ShiftModifier) ? 1 : 5))
            } else if (pickerIndex <= 18) {
                pickerIndex = Math.max(3, Math.min(18, pickerIndex + dir))
            }
            return true
        }
        if (k === Qt.Key_Up || k === Qt.Key_Down) {
            if (k === Qt.Key_Up) {
                if (pickerIndex === 19) pickerIndex = 11
                else if (pickerIndex >= 11) pickerIndex -= 8
                else if (pickerIndex >= 3) pickerIndex = 2
                else pickerIndex = Math.max(0, pickerIndex - 1)
            } else {
                if (pickerIndex < 2) pickerIndex++
                else if (pickerIndex === 2) pickerIndex = 3
                else if (pickerIndex <= 10) pickerIndex += 8
                else pickerIndex = 19
            }
            return true
        }
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
            if (pickerIndex === 19) closeColorPicker()
            else if (pickerIndex >= 3) choosePreset(presetColors[pickerIndex - 3])
            return true
        }
        return false
    }

    Keys.onPressed: (event) => {
        if (colorPickerOpen) {
            event.accepted = handlePickerKey(event)
            return
        }
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) {
            requestBack()
            event.accepted = true
        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            selectKeyboard(keyboardIndex +
                           ((event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier)) ? -1 : 1), true)
            event.accepted = true
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
            selectKeyboard(keyboardIndex + (event.key === Qt.Key_Down ? 1 : -1), false)
            event.accepted = true
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
            if (keyboardIndex <= 1) {
                switchTab(event.key === Qt.Key_Left ? 0 : 1)
                event.accepted = true
            }
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            activateSelection()
            event.accepted = true
        } else if (event.key === Qt.Key_F2 && keyboardIndex >= 2 && keyboardIndex < 2 + fieldCount) {
            var field = currentFields[keyboardIndex - 2]
            if (field.kind !== "toggle") focusSelectedEntry()
            event.accepted = true
        }
    }

    Process {
        id: readProc
        command: ["python3", settings.backend, "read"]
        stdout: SplitParser {
            onRead: (line) => {
                try {
                    var result = JSON.parse(line)
                    if (!result.ok) throw new Error(result.error || "Unable to read configuration")
                    settings.values = Object.assign({}, result.values)
                    if (!result.revisions) throw new Error("Missing configuration revisions")
                    settings.savedValues = Object.assign({}, result.values)
                    settings.savedRevisions = Object.assign({}, result.revisions)
                    settings.loaded = true
                    settings.dirty = false
                    settings.hasError = false
                    settings.statusText = "Ready. Save changes with Apply."
                } catch (error) {
                    settings.hasError = true
                    settings.statusText = String(error)
                }
            }
        }
        onExited: (code) => {
            settings.busy = false
            if (code !== 0 && !settings.loaded && !settings.hasError) {
                settings.hasError = true
                settings.statusText = "Unable to read settings; check settings_backend.py."
            }
        }
    }

    Process {
        id: saveProc
        stdout: SplitParser {
            onRead: (line) => {
                try {
                    var result = JSON.parse(line)
                    if (!result.ok) throw new Error(result.error || "Unable to save settings")
                    if (!result.revisions || !result.values)
                        throw new Error("Settings saved, but verification data is missing. Reopen Settings.")
                    // Trust only the canonical values and file hashes returned after verification.
                    settings.values = Object.assign({}, result.values)
                    settings.savedValues = Object.assign({}, result.values)
                    settings.savedRevisions = Object.assign({}, result.revisions)
                    settings.dirty = false
                    settings.hasError = false
                    settings.statusText = result.warning || "Saved and verified. Backup created."
                } catch (error) {
                    settings.hasError = true
                    settings.statusText = String(error)
                }
            }
        }
        onExited: (code) => {
            settings.busy = false
            if (code !== 0 && !settings.hasError) {
                settings.hasError = true
                settings.statusText = "Failed to apply changes"
            }
        }
    }

    Column {
        anchors.fill: parent
        spacing: 12

        Row {
            width: parent.width
            height: 39
            spacing: 10
            Repeater {
                model: ["Hyprland", "Quickshell"]
                delegate: Rectangle {
                    required property int index
                    required property string modelData
                    width: (settings.width - 10) / 2
                    height: 39
                    radius: 12
                    color: settings.selectedTab === index
                        ? Qt.alpha(Theme.white, 0.18)
                        : Qt.alpha(Theme.white, tabMouse.containsMouse ? 0.12 : 0.06)
                    border.width: settings.keyboardIndex === index && !settings.colorPickerOpen ? 2 : 1
                    border.color: settings.keyboardIndex === index && !settings.colorPickerOpen
                        ? Theme.blue
                        : (settings.selectedTab === index ? Qt.alpha(Theme.white, 0.28)
                                                          : Qt.alpha(Theme.white, 0.10))
                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        color: settings.selectedTab === index ? Theme.white : Qt.alpha(Theme.white, 0.62)
                        font.family: Theme.fontMain
                        font.pixelSize: 13
                        font.bold: settings.selectedTab === index
                    }
                    MouseArea {
                        id: tabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            settings.switchTab(index)
                        }
                    }
                }
            }
        }

        Flickable {
            id: rowsScroll
            width: parent.width
            height: 380
            contentWidth: width
            contentHeight: rowsColumn.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick

            Column {
                id: rowsColumn
                width: rowsScroll.width - 8
                spacing: 8
                Repeater {
                    id: rowsRepeater
                    model: settings.currentFields
                    delegate: Rectangle {
                        id: settingRow
                        required property int index
                        required property var modelData
                        property alias valueEditor: entry
                        width: rowsColumn.width
                        height: 69
                        radius: 13
                        color: Qt.alpha(Theme.white, 0.065)
                        border.color: settings.keyboardIndex === 2 + index && !settings.colorPickerOpen
                            ? Theme.blue : Qt.alpha(Theme.white, 0.09)
                        border.width: settings.keyboardIndex === 2 + index && !settings.colorPickerOpen ? 2 : 1

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 15
                            anchors.right: valueBox.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            Text {
                                width: parent.width
                                text: settingRow.modelData.label
                                font.family: Theme.fontMain
                                font.pixelSize: 13
                                font.bold: true
                                color: Theme.white
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: settingRow.modelData.detail
                                font.family: Theme.fontMain
                                font.pixelSize: 10
                                color: Qt.alpha(Theme.white, 0.55)
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            id: valueBox
                            width: settingRow.modelData.kind === "toggle" ? 50
                                   : (settingRow.modelData.kind === "color" ? 198 : 155)
                            height: 35
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            radius: settingRow.modelData.kind === "toggle" ? 18 : 10
                            color: settingRow.modelData.kind === "toggle"
                                ? (settings.values[settingRow.modelData.key] ? Theme.blue : Qt.alpha(Theme.white, 0.15))
                                : Qt.alpha(Theme.white, 0.08)
                            border.color: Qt.alpha(Theme.white, 0.12)
                            border.width: 1

                            Rectangle {
                                visible: settingRow.modelData.kind === "toggle"
                                width: 23
                                height: 23
                                radius: 12
                                anchors.verticalCenter: parent.verticalCenter
                                x: settings.values[settingRow.modelData.key] ? parent.width - width - 6 : 6
                                color: Theme.white
                                Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                visible: settingRow.modelData.kind === "toggle"
                                enabled: settings.loaded && !settings.busy
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    settings.keyboardIndex = 2 + settingRow.index
                                    settings.setValue(settingRow.modelData.key,
                                                      !settings.values[settingRow.modelData.key])
                                    settings.forceActiveFocus()
                                }
                            }
                            // Live preview for every color field. Clicking it opens the
                            // RGB/preset selector inside this very same Launcher card.
                            Rectangle {
                                id: colorSwatch
                                visible: settingRow.modelData.kind === "color"
                                width: 31
                                height: 27
                                radius: 7
                                anchors.left: parent.left
                                anchors.leftMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                color: settings.safeColor(settingRow.modelData.key)
                                border.width: 1
                                border.color: Qt.alpha(Theme.white, 0.44)

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: colorSwatch.visible && settings.loaded && !settings.busy
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        settings.keyboardIndex = 2 + settingRow.index
                                        settings.openColorPicker(settingRow.modelData.key,
                                                                 settingRow.modelData.label)
                                    }
                                }
                            }

                            TextInput {
                                id: entry
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.left: settingRow.modelData.kind === "color" ? colorSwatch.right : parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: settingRow.modelData.kind === "color" ? 7 : 9
                                anchors.rightMargin: 9
                                visible: settingRow.modelData.kind !== "toggle"
                                enabled: settings.loaded && !settings.busy
                                text: settings.valueString(settingRow.modelData.key)
                                color: Theme.white
                                font.family: Theme.fontMain
                                font.pixelSize: 13
                                selectByMouse: true
                                horizontalAlignment: TextInput.AlignHCenter
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true
                                onActiveFocusChanged: {
                                    if (activeFocus) {
                                        settings.keyboardIndex = 2 + settingRow.index
                                        settings.beginTextEdit(settingRow.modelData.key)
                                    }
                                }
                                onTextEdited: settings.setValue(settingRow.modelData.key, text.trim())
                                Keys.onPressed: (event) => {
                                    if (event.key === Qt.Key_Escape) {
                                        settings.endTextEdit(settingRow.modelData.key, text, true, 0)
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                        settings.endTextEdit(settingRow.modelData.key, text, false, 1)
                                        event.accepted = true
                                    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab ||
                                               event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
                                        var step = (event.key === Qt.Key_Backtab || event.key === Qt.Key_Up ||
                                                    (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) ? -1 : 1
                                        settings.endTextEdit(settingRow.modelData.key, text, false, 0)
                                        settings.selectKeyboard(settings.keyboardIndex + step, true)
                                        event.accepted = true
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Qt.alpha(Theme.white, 0.10)
        }

        Row {
            width: parent.width
            height: 39
            spacing: 12
            Rectangle {
                width: 140
                height: parent.height
                radius: 11
                color: Qt.alpha(Theme.white, discardHover.containsMouse ? 0.17 : 0.08)
                border.color: settings.keyboardIndex === 2 + settings.fieldCount && !settings.colorPickerOpen
                    ? Theme.blue : Qt.alpha(Theme.white, 0.12)
                border.width: settings.keyboardIndex === 2 + settings.fieldCount && !settings.colorPickerOpen ? 2 : 1
                Text { anchors.centerIn: parent; text: "Discard edits"; color: Theme.white; font.family: Theme.fontMain; font.pixelSize: 12 }
                MouseArea {
                    id: discardHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: settings.dirty && !settings.busy
                    onClicked: {
                        settings.keyboardIndex = 2 + settings.fieldCount
                        settings.discardChanges()
                        settings.forceActiveFocus()
                    }
                }
            }
            Item { width: parent.width - 316; height: 1 }
            Rectangle {
                width: 152
                height: parent.height
                radius: 11
                color: settings.dirty && !settings.busy ? Theme.blue : Qt.alpha(Theme.white, 0.12)
                border.width: settings.keyboardIndex === 3 + settings.fieldCount && !settings.colorPickerOpen ? 2 : 0
                border.color: Theme.white
                Text {
                    anchors.centerIn: parent
                    text: settings.busy ? "Please wait..." : "Apply changes"
                    color: settings.dirty && !settings.busy ? Theme.bg0 : Qt.alpha(Theme.white, 0.65)
                    font.family: Theme.fontMain
                    font.pixelSize: 12
                    font.bold: true
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: settings.loaded && !settings.busy && settings.dirty
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        settings.keyboardIndex = 3 + settings.fieldCount
                        settings.applyChanges()
                        settings.forceActiveFocus()
                    }
                }
            }
        }
        Text {
            width: parent.width
            height: 32
            text: settings.statusText
            color: settings.hasError ? Theme.red : Qt.alpha(Theme.white, 0.56)
            font.family: Theme.fontMain
            font.pixelSize: 10
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            height: 16
            text: "↑↓ / Tab: navigate  •  ←→: tabs  •  Enter: select  •  F2: edit  •  Esc: back"
            font.family: Theme.fontMain
            font.pixelSize: 10
            color: Qt.alpha(Theme.white, 0.43)
            elide: Text.ElideRight
        }
    }

    // Color editor floats over the embedded Settings contents, never outside
    // the Launcher. The same Apply button below still controls persistence.
    Rectangle {
        id: pickerOverlay
        anchors.fill: parent
        z: 30
        visible: settings.colorPickerOpen
        color: Qt.alpha(Theme.bg0, 0.76)

        MouseArea {
            anchors.fill: parent
            onClicked: settings.closeColorPicker()
        }

        Rectangle {
            id: pickerCard
            anchors.centerIn: parent
            width: Math.min(parent.width - 22, 445)
            height: 465
            radius: Glass.radiusLarge
            color: Qt.alpha(Glass.tint, 0.97)
            border.color: Glass.borderColor
            border.width: Math.max(1, Glass.borderWidth)

            MouseArea { anchors.fill: parent } // Don't dismiss when interacting with sliders.

            Column {
                anchors.fill: parent
                anchors.margins: 19
                spacing: 12

                Item {
                    width: parent.width
                    height: 31
                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: settings.pickerTitle
                        font.family: Theme.fontMain
                        font.pixelSize: 17
                        font.bold: true
                        color: Theme.white
                    }
                    Rectangle {
                        width: 30
                        height: 30
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 9
                        color: Qt.alpha(Theme.white, pickerCloseArea.containsMouse ? 0.18 : 0.09)
                        Text {
                            anchors.centerIn: parent
                            text: "󰅖"
                            font.family: Theme.fontIcons
                            font.pixelSize: 15
                            color: Theme.white
                        }
                        MouseArea {
                            id: pickerCloseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: settings.closeColorPicker()
                        }
                    }
                }

                Row {
                    width: parent.width
                    height: 64
                    spacing: 15
                    Rectangle {
                        width: 92
                        height: 64
                        radius: 13
                        color: settings.rgbHex(settings.pickerRed, settings.pickerGreen, settings.pickerBlue)
                        border.width: 1
                        border.color: Qt.alpha(Theme.white, 0.42)
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Text {
                            text: settings.rgbHex(settings.pickerRed, settings.pickerGreen, settings.pickerBlue).toUpperCase()
                            color: Theme.white
                            font.family: Theme.fontMain
                            font.pixelSize: 18
                            font.bold: true
                        }
                        Text {
                            text: "Preview · changes not saved yet"
                            color: Qt.alpha(Theme.white, 0.59)
                            font.family: Theme.fontMain
                            font.pixelSize: 11
                        }
                    }
                }

                Text {
                    text: "RGB: ←→ adjust (Shift: fine), ↑↓ move"
                    font.family: Theme.fontMain
                    font.pixelSize: 12
                    color: Qt.alpha(Theme.white, 0.65)
                }

                Column {
                    width: parent.width
                    spacing: 5
                    Repeater {
                        model: ["R", "G", "B"]
                        delegate: Row {
                            required property int index
                            required property string modelData
                            width: parent.width
                            height: 32
                            spacing: 11
                            Text {
                                width: 18
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData
                                color: Theme.white
                                font.family: Theme.fontMain
                                font.pixelSize: 12
                                font.bold: true
                            }

                            Item {
                                id: channelTrack
                                width: parent.width - 18 - 39 - 22
                                height: 32
                                Rectangle {
                                    anchors.fill: parent
                                    color: "transparent"
                                    radius: 8
                                    border.width: settings.colorPickerOpen && settings.pickerIndex === index ? 2 : 0
                                    border.color: Theme.blue
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    height: 9
                                    radius: 4
                                    color: Qt.alpha(Theme.white, 0.16)
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(0, parent.width * settings.pickerChannel(index) / 255)
                                    height: 9
                                    radius: 4
                                    color: index === 0 ? "#f47b80"
                                         : (index === 1 ? "#86d6a1" : "#77adff")
                                }
                                Rectangle {
                                    width: 16
                                    height: 16
                                    radius: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: (parent.width - width) * settings.pickerChannel(index) / 255
                                    color: Theme.white
                                    border.color: Qt.alpha(Theme.bg0, 0.65)
                                    border.width: 1
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onPressed: (mouse) => {
                                        settings.pickerIndex = index
                                        settings.setPickerChannel(index, mouse.x / width * 255)
                                        settings.forceActiveFocus()
                                    }
                                    onPositionChanged: (mouse) => {
                                        if (pressed) settings.setPickerChannel(index, mouse.x / width * 255)
                                    }
                                }
                            }

                            Text {
                                width: 39
                                anchors.verticalCenter: parent.verticalCenter
                                text: String(settings.pickerChannel(index))
                                horizontalAlignment: Text.AlignRight
                                color: Theme.white
                                font.family: Theme.fontMain
                                font.pixelSize: 12
                                font.bold: true
                            }
                        }
                    }
                }

                Text {
                    text: "Quick colors · Enter to choose"
                    font.family: Theme.fontMain
                    font.pixelSize: 12
                    color: Qt.alpha(Theme.white, 0.65)
                }

                Grid {
                    columns: 8
                    spacing: 8
                    Repeater {
                        model: settings.presetColors
                        delegate: Rectangle {
                            required property int index
                            required property string modelData
                            width: 36
                            height: 29
                            radius: 8
                            color: modelData
                            border.width: settings.pickerIndex === 3 + index ? 3 :
                                          (settings.rgbHex(settings.pickerRed, settings.pickerGreen,
                                                           settings.pickerBlue).toLowerCase() === modelData ? 2 : 1)
                            border.color: settings.pickerIndex === 3 + index ? Theme.blue :
                                          (settings.rgbHex(settings.pickerRed, settings.pickerGreen,
                                                           settings.pickerBlue).toLowerCase() === modelData
                                           ? Theme.white : Qt.alpha(Theme.white, 0.29))
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    settings.pickerIndex = 3 + index
                                    settings.choosePreset(modelData)
                                    settings.forceActiveFocus()
                                }
                            }
                        }
                    }
                }

                Item { width: 1; height: 1 }

                Rectangle {
                    width: parent.width
                    height: 36
                    radius: 11
                    color: Qt.alpha(Theme.white, doneArea.containsMouse ? 0.22 : 0.13)
                    border.color: settings.pickerIndex === 19 ? Theme.blue : Qt.alpha(Theme.white, 0.19)
                    border.width: settings.pickerIndex === 19 ? 2 : 1
                    Text {
                        anchors.centerIn: parent
                        text: "Done · return to Settings"
                        color: Theme.white
                        font.family: Theme.fontMain
                        font.pixelSize: 12
                        font.bold: true
                    }
                    MouseArea {
                        id: doneArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: settings.closeColorPicker()
                    }
                }
            }
        }
    }
}
