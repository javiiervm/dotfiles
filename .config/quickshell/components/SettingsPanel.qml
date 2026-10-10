import QtQuick
import Quickshell.Io
import ".."

// Embedded in components/Launcher.qml: this is NOT another PanelWindow.
// The Python helper runs only when Settings is opened or Apply is clicked.
FocusScope {
    id: settings
    height: isNetworkTab ? 520 : 578
    focus: visible
    signal requestBack()

    property int selectedTab: 0 // 0 Wi-Fi, 1 Bluetooth, 2 Hyprland, 3 Quickshell
    // Focus stays in this FocusScope except while an input is being edited.
    // 0..3 tabs; then controls/rows; then Discard / Apply on visual tabs.
    property int keyboardIndex: 0
    property int pickerIndex: 0  // 0..2 RGB, 3..18 presets, 19 Done
    property var editOriginal: null
    property string editingKey: ""
    readonly property bool isNetworkTab: selectedTab === 0 || selectedTab === 1
    readonly property int fieldCount: selectedTab === 2 ? hyprFields.length : quickFields.length
    readonly property var currentFields: selectedTab === 2 ? hyprFields : quickFields
    // Network listings are still fetched/structured by Launcher's existing provider.
    property var networkModel: null
    property bool wifiEnabled: false
    property bool btEnabled: false
    property bool wifiLoading: false
    property bool btLoading: false
    signal requestNetworkData(string kind)
    signal requestNetworkRescan(string kind)
    signal requestNetworkPower(string kind, bool enable)
    signal requestNetworkAction(string command, string name)
    signal requestConnectWifi(string ssid, string password)
    property bool wifiPasswordOpen: false
    property string wifiPasswordSsid: ""
    readonly property int networkCount: networkModel ? networkModel.count : 0
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
        wifiPasswordOpen = false
        wifiPasswordSsid = ""
        wifiPasswordInput.text = ""
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
        requestNetworkData("wifi")
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

    // Keyboard geometry: 0..3 = tabs, 4.. = content. The two axes
    // are deliberately independent: Left/Right = tabs, Up/Down = content.
    // No polling: network rows are read only when the user navigates.
    function keyboardSize() {
        return isNetworkTab ? 6 + networkCount : 6 + fieldCount
    }

    function selectableNetworkRow(index) {
        return index < 6 || (networkModel && index - 6 < networkCount
                              && networkModel.get(index - 6).type !== "dummy")
    }

    function selectKeyboard(index, wrap) {
        var count = keyboardSize()
        var wanted = wrap ? (index % count + count) % count
                          : Math.max(4, Math.min(count - 1, index))
        if (isNetworkTab && wanted >= 6) {
            // Ignore group headings (Connected / Saved Networks / etc.).
            var direction = wanted >= keyboardIndex ? 1 : -1
            while (wanted >= 6 && wanted < count && !selectableNetworkRow(wanted))
                wanted += direction
            if (wanted >= count || wanted < 4)
                return // Reached the end: never focus a heading.
        }
        keyboardIndex = wanted
        if (isNetworkTab) {
            if (wanted >= 6 && networkModel)
                networkList.positionViewAtIndex(wanted - 6, ListView.Contain)
        } else if (wanted >= 4 && wanted < 4 + fieldCount) {
            var y = (wanted - 4) * 77
            if (y < rowsScroll.contentY) rowsScroll.contentY = y
            else if (y + 69 > rowsScroll.contentY + rowsScroll.height)
                rowsScroll.contentY = Math.min(Math.max(0, rowsScroll.contentHeight - rowsScroll.height),
                                               y + 69 - rowsScroll.height)
        }
    }

    function moveVertical(direction, wrap) {
        // Down from any tab enters its own contents, not the next tab.
        if (keyboardIndex <= 3) {
            if (direction > 0) selectKeyboard(4, false)
            else if (wrap) selectKeyboard(keyboardSize() - 1, false)
            return
        }
        // Up from the first button/setting focuses the current tab.
        if (direction < 0 && keyboardIndex === 4) {
            keyboardIndex = selectedTab
            return
        }
        // Tab wraps from the last control back to the active tab.
        if (direction > 0 && keyboardIndex === keyboardSize() - 1 && wrap) {
            keyboardIndex = selectedTab
            return
        }
        selectKeyboard(keyboardIndex + direction, false)
    }

    function switchTab(tab) {
        var next = Math.max(0, Math.min(3, tab))
        selectedTab = next
        keyboardIndex = next
        editingKey = "" // Switching away from a TextInput exits edit mode.
        rowsScroll.contentY = 0
        if (next === 0) requestNetworkData("wifi")
        else if (next === 1) requestNetworkData("bt")
        forceActiveFocus()
    }

    function activateNetwork(command, name) {
        if (!command || command.length === 0 || command === "qs_none") return
        if (command.indexOf("qs_wifi_pass:") === 0) {
            wifiPasswordSsid = command.substring("qs_wifi_pass:".length)
            wifiPasswordInput.text = ""
            wifiPasswordOpen = true
            Qt.callLater(function() { wifiPasswordInput.forceActiveFocus() })
        } else {
            requestNetworkAction(command, name)
        }
    }

    function closeWifiPassword() {
        wifiPasswordInput.text = ""
        wifiPasswordSsid = ""
        wifiPasswordOpen = false
        settings.forceActiveFocus()
    }

    function submitWifiPassword() {
        if (wifiPasswordSsid.length === 0 || wifiPasswordInput.text.length === 0) return
        var ssid = wifiPasswordSsid
        var pwd = wifiPasswordInput.text
        closeWifiPassword()
        requestConnectWifi(ssid, pwd)
    }

    function activateSelection() {
        if (busy) return
        if (keyboardIndex <= 3) {
            switchTab(keyboardIndex)
        } else if (isNetworkTab) {
            var kind = selectedTab === 0 ? "wifi" : "bt"
            if (keyboardIndex === 4) requestNetworkRescan(kind)
            else if (keyboardIndex === 5)
                requestNetworkPower(kind, !(kind === "wifi" ? wifiEnabled : btEnabled))
            else if (networkModel && keyboardIndex - 6 < networkCount) {
                var item = networkModel.get(keyboardIndex - 6)
                if (item.type !== "dummy" && item.type !== "wifi_current")
                    activateNetwork(item.exec, item.name)
            }
        } else if (keyboardIndex < 4 + fieldCount) {
            if (!loaded) return
            var field = currentFields[keyboardIndex - 4]
            if (field.kind === "toggle") setValue(field.key, !values[field.key])
            else if (field.kind === "color") openColorPicker(field.key, field.label)
            else focusSelectedEntry()
        } else if (keyboardIndex === 4 + fieldCount) {
            discardChanges()
        } else {
            applyChanges()
        }
    }

    function focusSelectedEntry() {
        var item = rowsRepeater.itemAt(keyboardIndex - 4)
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
        if (wifiPasswordOpen) return
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) {
            requestBack()
            event.accepted = true
        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            var tabDirection = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1
            moveVertical(tabDirection, true)
            event.accepted = true
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
            moveVertical(event.key === Qt.Key_Down ? 1 : -1, false)
            event.accepted = true
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
            // A tab switch works even if an item in the current tab is focused.
            // Editable TextInputs and the color picker have their own handlers.
            if (editingKey === "") {
                switchTab(selectedTab + (event.key === Qt.Key_Left ? -1 : 1))
                event.accepted = true
            }
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            activateSelection()
            event.accepted = true
        } else if (event.key === Qt.Key_F2 && !isNetworkTab && keyboardIndex >= 4 && keyboardIndex < 4 + fieldCount) {
            var field = currentFields[keyboardIndex - 4]
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
                model: ["Wi-Fi", "Bluetooth", "Hyprland", "Quickshell"]
                delegate: Rectangle {
                    required property int index
                    required property string modelData
                    width: (settings.width - 30) / 4
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

        // Wi-Fi and Bluetooth: larger version of the original Launcher lists.
        Column {
            id: networkSection
            visible: settings.isNetworkTab
            width: parent.width
            // Use the available height; the help text is anchored at the bottom.
            height: visible ? Math.max(380, settings.height - 87) : 0
            spacing: 10

            Row {
                width: parent.width
                height: 43
                spacing: 10
                Text {
                    width: parent.width - 108
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: settings.selectedTab === 0 ? "Wi-Fi Networks" : "Bluetooth Devices"
                    color: Theme.white
                    font.family: Theme.fontMain
                    font.pixelSize: 15
                    font.bold: true
                }
                Rectangle {
                    width: 43; height: 43; radius: 14
                    color: Qt.alpha(Theme.white, networkRefreshArea.containsMouse ? 0.17 : 0.08)
                    border.color: settings.keyboardIndex === 4 ? Theme.blue : Qt.alpha(Theme.white, 0.14)
                    border.width: settings.keyboardIndex === 4 ? 2 : 1
                    Text {
                        anchors.centerIn: parent
                        text: "󰑐"
                        font.family: Theme.fontIcons
                        font.pixelSize: 18
                        color: Theme.white
                    }
                    MouseArea {
                        id: networkRefreshArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: {
                            settings.keyboardIndex = 4
                            settings.requestNetworkRescan(settings.selectedTab === 0 ? "wifi" : "bt")
                            settings.forceActiveFocus()
                        }
                    }
                }
                Rectangle {
                    width: 43; height: 43; radius: 14
                    property bool enabledRadio: settings.selectedTab === 0 ? settings.wifiEnabled : settings.btEnabled
                    color: enabledRadio ? Theme.white : Qt.alpha(Theme.white, powerMouse.containsMouse ? 0.17 : 0.08)
                    border.color: settings.keyboardIndex === 5 ? Theme.blue : Qt.alpha(Theme.white, 0.14)
                    border.width: settings.keyboardIndex === 5 ? 2 : 1
                    Text {
                        anchors.centerIn: parent
                        text: settings.selectedTab === 0 ? "" : ""
                        font.family: Theme.fontIcons
                        font.pixelSize: 17
                        color: parent.enabledRadio ? Theme.bg0 : Theme.white
                    }
                    MouseArea {
                        id: powerMouse
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: {
                            settings.keyboardIndex = 5
                            settings.requestNetworkPower(settings.selectedTab === 0 ? "wifi" : "bt", !parent.enabledRadio)
                            settings.forceActiveFocus()
                        }
                    }
                }
            }

            ListView {
                id: networkList
                width: parent.width
                height: networkSection.height - 43 - networkSection.spacing
                model: settings.networkModel
                clip: true
                spacing: 3
                interactive: true
                boundsBehavior: Flickable.StopAtBounds
                delegate: Rectangle {
                    id: networkRow
                    required property int index
                    required property string name
                    required property string comment
                    required property string icon
                    required property string exec
                    required property string type
                    width: networkList.width
                    height: type === "dummy" ? 34 : 59
                    radius: 12
                    color: type === "dummy" ? "transparent"
                           : (settings.keyboardIndex === index + 6
                              ? Qt.alpha(Theme.white, 0.14)
                              : Qt.alpha(Theme.white, networkItemMouse.containsMouse ? 0.10 : 0.055))
                    border.width: (type !== "dummy" && settings.keyboardIndex === index + 6) ? 2 : 0
                    border.color: Theme.blue
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 14
                        Text {
                            width: 26
                            height: parent.height
                            visible: networkRow.type !== "dummy"
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignHCenter
                            text: settings.selectedTab === 0 ? "" : ""
                            font.family: Theme.fontIcons
                            color: networkRow.type === "wifi_current" || networkRow.type === "bt_current"
                                   ? "#30d158" : Theme.white
                            font.pixelSize: 19
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            width: parent.width - 85
                            Text {
                                width: parent.width
                                text: networkRow.name
                                font.family: Theme.fontMain
                                color: networkRow.type === "dummy" ? Qt.alpha(Theme.white, 0.56)
                                    : (networkRow.type === "wifi_current" ? "#30d158" : Theme.white)
                                font.pixelSize: networkRow.type === "dummy" ? 11 : 14
                                font.bold: networkRow.type !== "dummy"
                                elide: Text.ElideRight
                            }
                            Text {
                                visible: networkRow.type !== "dummy" && networkRow.comment !== ""
                                width: parent.width
                                text: networkRow.comment
                                font.family: Theme.fontMain
                                font.pixelSize: 11
                                color: Theme.grey1
                                elide: Text.ElideRight
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰄬"
                            font.family: Theme.fontIcons
                            font.pixelSize: 19
                            color: "#30d158"
                            visible: networkRow.type === "wifi_current" || networkRow.type === "bt_current"
                        }
                    }
                    MouseArea {
                        id: networkItemMouse
                        anchors.fill: parent
                        enabled: networkRow.type !== "dummy" && networkRow.type !== "wifi_current"
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        hoverEnabled: true
                        onClicked: {
                            settings.keyboardIndex = 6 + networkRow.index
                            settings.activateNetwork(networkRow.exec, networkRow.name)
                            settings.forceActiveFocus()
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: networkList.count === 0
                    text: settings.selectedTab === 0
                          ? (settings.wifiEnabled ? "Scanning networks..." : "Wi-Fi is disabled")
                          : (settings.btEnabled ? "Scanning devices..." : "Bluetooth is disabled")
                    color: Theme.grey1
                    font.family: Theme.fontMain
                    font.pixelSize: 13
                }
            }
        }

        Flickable {
            id: rowsScroll
            width: parent.width
            height: settings.isNetworkTab ? 0 : 380
            visible: !settings.isNetworkTab
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
                        border.color: settings.keyboardIndex === 4 + index && !settings.colorPickerOpen
                            ? Theme.blue : Qt.alpha(Theme.white, 0.09)
                        border.width: settings.keyboardIndex === 4 + index && !settings.colorPickerOpen ? 2 : 1

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
                                    settings.keyboardIndex = 4 + settingRow.index
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
                                        settings.keyboardIndex = 4 + settingRow.index
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
                                        settings.keyboardIndex = 4 + settingRow.index
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
                                        settings.moveVertical(step, true)
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
            visible: !settings.isNetworkTab
            width: parent.width
            height: visible ? 1 : 0
            color: Qt.alpha(Theme.white, 0.10)
        }

        Row {
            visible: !settings.isNetworkTab
            width: parent.width
            height: visible ? 39 : 0
            spacing: 12
            Rectangle {
                width: 140
                height: parent.height
                radius: 11
                color: Qt.alpha(Theme.white, discardHover.containsMouse ? 0.17 : 0.08)
                border.color: settings.keyboardIndex === 4 + settings.fieldCount && !settings.colorPickerOpen
                    ? Theme.blue : Qt.alpha(Theme.white, 0.12)
                border.width: settings.keyboardIndex === 4 + settings.fieldCount && !settings.colorPickerOpen ? 2 : 1
                Text { anchors.centerIn: parent; text: "Discard edits"; color: Theme.white; font.family: Theme.fontMain; font.pixelSize: 12 }
                MouseArea {
                    id: discardHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: settings.dirty && !settings.busy
                    onClicked: {
                        settings.keyboardIndex = 4 + settings.fieldCount
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
                border.width: settings.keyboardIndex === 5 + settings.fieldCount && !settings.colorPickerOpen ? 2 : 0
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
                        settings.keyboardIndex = 5 + settings.fieldCount
                        settings.applyChanges()
                        settings.forceActiveFocus()
                    }
                }
            }
        }
        Text {
            visible: !settings.isNetworkTab
            width: parent.width
            height: visible ? 32 : 0
            text: settings.statusText
            color: settings.hasError ? Theme.red : Qt.alpha(Theme.white, 0.56)
            font.family: Theme.fontMain
            font.pixelSize: 10
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
    }

    // Keep navigation help close to the bottom edge, not in the scrolling
    // content's vertical flow. This also frees space for more network rows.
    Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        height: 16
        text: settings.isNetworkTab
            ? "←→: tabs  •  ↑↓ / Tab: content  •  Enter: connect/toggle  •  Esc: back"
            : "←→: tabs  •  ↑↓ / Tab: content  •  Enter: select  •  F2: edit  •  Esc: back"
        font.family: Theme.fontMain
        font.pixelSize: 10
        color: Qt.alpha(Theme.white, 0.43)
        elide: Text.ElideRight
    }

    // Secured Wi-Fi networks require a password, still inside the same Launcher.
    Rectangle {
        anchors.fill: parent
        z: 40
        visible: settings.wifiPasswordOpen
        color: Qt.alpha(Theme.bg0, 0.78)
        MouseArea { anchors.fill: parent; onClicked: settings.closeWifiPassword() }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 36, 420)
            height: 190
            radius: Glass.radiusLarge
            color: Qt.alpha(Glass.tint, 0.98)
            border.color: Glass.borderColor
            border.width: 1
            MouseArea { anchors.fill: parent }
            Column {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 14
                Text {
                    text: "Connect to " + settings.wifiPasswordSsid
                    width: parent.width
                    elide: Text.ElideRight
                    color: Theme.white
                    font.family: Theme.fontMain
                    font.pixelSize: 16
                    font.bold: true
                }
                Rectangle {
                    width: parent.width
                    height: 42
                    radius: 11
                    color: Qt.alpha(Theme.white, 0.09)
                    border.color: wifiPasswordInput.activeFocus ? Theme.blue : Qt.alpha(Theme.white, 0.18)
                    border.width: wifiPasswordInput.activeFocus ? 2 : 1
                    TextInput {
                        id: wifiPasswordInput
                        anchors.fill: parent
                        anchors.margins: 10
                        color: Theme.white
                        font.family: Theme.fontMain
                        font.pixelSize: 14
                        echoMode: TextInput.Password
                        selectByMouse: true
                        verticalAlignment: TextInput.AlignVCenter
                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Escape) {
                                settings.closeWifiPassword()
                                event.accepted = true
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                settings.submitWifiPassword()
                                event.accepted = true
                            }
                        }
                    }
                }
                Row {
                    spacing: 12
                    Rectangle {
                        width: 180; height: 39; radius: 11
                        color: Qt.alpha(Theme.white, 0.10)
                        Text { anchors.centerIn: parent; text: "Cancel"; color: Theme.white; font.family: Theme.fontMain }
                        MouseArea { anchors.fill: parent; onClicked: settings.closeWifiPassword(); cursorShape: Qt.PointingHandCursor }
                    }
                    Rectangle {
                        width: 180; height: 39; radius: 11
                        color: Theme.blue
                        Text { anchors.centerIn: parent; text: "Connect"; color: Theme.bg0; font.family: Theme.fontMain; font.bold: true }
                        MouseArea { anchors.fill: parent; onClicked: settings.submitWifiPassword(); cursorShape: Qt.PointingHandCursor }
                    }
                }
            }
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
