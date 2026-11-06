
import QtQuick
import QtQuick.Layouts
import ".."

// Xavion is an actual Launcher view, not a separate window or glass card.
// Launcher.qml already owns the GlassSurface, blur, rounded edges and animations.
Item {
    id: root

    required property var service
    signal requestBack()

    focus: visible
    property bool settingsOpen: false
    property bool historyOpen: false
    property bool historySelectionMode: false
    property var selectedSessionIds: []
    property bool deleteConfirmationOpen: false
    property var pendingDeletionIds: []
    property var queuedMessages: []
    // A draft belongs to this view. Only paths are sent to the backend.
    property var pendingImages: []
    readonly property int maxImages: 4

    function addImageFile(fileUrl) {
        if (!service.visionSupported || pendingImages.length >= maxImages)
            return
        const url = String(fileUrl)
        if (!url.startsWith("file:///"))
            return
        let path
        try {
            path = decodeURIComponent(url.substring("file://".length))
        } catch (error) {
            console.warn("Xavion: invalid image file URL", error)
            return
        }
        if (!/\.(png|jpe?g|webp)$/i.test(path))
            return
        for (let i = 0; i < pendingImages.length; ++i) {
            if (pendingImages[i].path === path)
                return
        }
        const updated = pendingImages.slice()
        updated.push({path: path, url: url})
        pendingImages = updated
    }

    function removePendingImage(index) {
        const updated = pendingImages.slice()
        if (index >= 0 && index < updated.length) {
            updated.splice(index, 1)
            pendingImages = updated
        }
    }

    function exitHistorySelection() {
        historySelectionMode = false
        selectedSessionIds = []
    }

    function toggleSelectedSession(sessionId) {
        const id = String(sessionId)
        const updated = selectedSessionIds.slice()
        const index = updated.indexOf(id)
        if (index < 0)
            updated.push(id)
        else
            updated.splice(index, 1)
        selectedSessionIds = updated
    }

    function selectAllSessions() {
        if (selectedSessionIds.length === service.savedSessions.length) {
            selectedSessionIds = []
            return
        }
        const allIds = []
        for (let i = 0; i < service.savedSessions.length; i++)
            allIds.push(String(service.savedSessions[i].id))
        selectedSessionIds = allIds
    }

    // Called for both a row's trash icon and the bulk-delete action.
    // Both paths use the same single confirmation dialog.
    function requestDeletion(ids) {
        if (!service.backendReady || service.busy || service.deletionPending)
            return
        if (!ids || ids.length === 0)
            return
        pendingDeletionIds = ids.slice()
        deleteConfirmationOpen = true
    }

    function cancelDeletion() {
        deleteConfirmationOpen = false
        pendingDeletionIds = []
    }

    readonly property color accent: service.gradientMid
    readonly property color accentSoft: Qt.alpha(service.gradientMid, 0.38)
    readonly property color controlBackground: Qt.alpha(Theme.white, 0.075)
    readonly property color controlBorder: Qt.alpha(Theme.white, 0.13)
    readonly property color controlBackgroundStrong: Qt.alpha(Theme.white, 0.10)
    readonly property string currentModelLabel: {
        if (service.activeModel && service.activeModel.length > 0)
            return service.activeModel
        if (service.selectedModel && service.selectedModel.length > 0)
            return service.selectedModel
        return service.backendReady ? "Ready" : "Starting Xavion..."
    }

    Keys.onEscapePressed: function(event) {
        back()
        event.accepted = true
    }

    function back() {
        if (imagePicker.visible) {
            imagePicker.cancel()
        } else if (deleteConfirmationOpen) {
            cancelDeletion()
        } else if (historyOpen && historySelectionMode) {
            exitHistorySelection()
        } else if (historyOpen) {
            historyOpen = false
            Qt.callLater(focusInput)
        } else if (settingsOpen) {
            settingsOpen = false
            Qt.callLater(focusInput)
        } else {
            requestBack()
        }
    }

    function focusInput() {
        if (visible && !settingsOpen && !historyOpen && !imagePicker.visible
            && service.backendReady && !service.busy)
            composerInput.forceActiveFocus()
    }

    function sendMessage() {
        const content = composerInput.text.trim()
        if ((!content.length && pendingImages.length === 0)
            || !service.backendReady || service.busy)
            return
        const attachments = pendingImages.slice()
        if (service.sendMessage(content, attachments)) {
            composerInput.text = ""
            pendingImages = []
            messageList.jumpToLatest()
        }
    }

    // Enter from the Launcher's search field lands here, including while
    // Xavion's Python bridge is still starting. Keep prompts in order.
    function sendFromLauncher(message) {
        const content = String(message === undefined || message === null ? "" : message).trim()
        if (!content.length) return
        const pending = queuedMessages.slice()
        pending.push(content)
        queuedMessages = pending
        service.ensureBackend()
        flushQueuedMessage()
    }

    function flushQueuedMessage() {
        if (!queuedMessages.length || !service.backendReady || service.busy)
            return
        if (service.sendMessage(queuedMessages[0])) {
            queuedMessages = queuedMessages.slice(1)
            messageList.jumpToLatest()
        }
    }

    onVisibleChanged: {
        if (visible) {
            service.ensureBackend()
            Qt.callLater(focusInput)
        } else {
            settingsOpen = false
            historyOpen = false
            exitHistorySelection()
            cancelDeletion()
            imagePicker.cancel()
        }
    }

    // A modal picker rendered inside the same Launcher item. There is no
    // platform FileDialog, so focus never leaves the Xavion chat surface.
    XavionImagePicker {
        id: imagePicker
        anchors.fill: parent
        z: 35
        maxImages: root.maxImages
        accentColor: root.accent
        onAccepted: function(images) {
            root.pendingImages = images
            Qt.callLater(root.focusInput)
        }
        onCanceled: Qt.callLater(root.focusInput)
    }

    // The parent Launcher supplies the ONLY background. No opaque red panel,
    // independent corner radius, extra borders or duplicated glow effects.
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Launcher-style header: title and current model at left, actions at right.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: 20
                color: backArea.containsMouse ? Qt.alpha(Theme.white, 0.15) : root.controlBackground
                border.width: 1
                border.color: root.controlBorder

                Text {
                    anchors.centerIn: parent
                    text: ""
                    font.family: Theme.fontIcons
                    font.pixelSize: 16
                    color: Theme.white
                }
                MouseArea {
                    id: backArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.back()
                }
            }

            ColumnLayout {
                spacing: 1
                Text {
                    text: "Xavion"
                    color: Theme.white
                    font.family: Theme.fontMain
                    font.pixelSize: 16
                    font.bold: true
                }
                Text {
                    text: root.currentModelLabel
                    color: Theme.grey1
                    font.family: Theme.fontMain
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                visible: !root.settingsOpen
                Layout.preferredWidth: visible ? Math.max(105, newChatLabel.implicitWidth + 30) : 0
                Layout.preferredHeight: 40
                radius: 13
                color: newChatArea.containsMouse ? Qt.alpha(Theme.white, 0.15) : root.controlBackground
                border.width: 1
                border.color: root.controlBorder

                Text {
                    id: newChatLabel
                    anchors.centerIn: parent
                    text: "New chat"
                    color: Theme.white
                    font.family: Theme.fontMain
                    font.pixelSize: 12
                    font.bold: true
                }
                MouseArea {
                    id: newChatArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.historyOpen = false
                        root.exitHistorySelection()
                        root.service.newConversation()
                    }
                }
            }

            // Local conversation history, between New chat and Settings.
            Rectangle {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: 13
                color: historyArea.containsMouse || root.historyOpen
                       ? Qt.alpha(Theme.white, 0.16) : root.controlBackground
                border.width: 1
                border.color: root.historyOpen ? Qt.alpha(Theme.white, 0.20) : root.controlBorder
                Text {
                    anchors.centerIn: parent
                    text: "󰋚"
                    font.family: Theme.fontIcons
                    font.pixelSize: 18
                    color: Theme.white
                }
                MouseArea {
                    id: historyArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.settingsOpen = false
                        root.historyOpen = !root.historyOpen
                        root.exitHistorySelection()
                        if (root.historyOpen)
                            root.service.listSessions()
                        else
                            Qt.callLater(root.focusInput)
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: 13
                color: settingsArea.containsMouse || root.settingsOpen
                       ? Qt.alpha(Theme.white, 0.16) : root.controlBackground
                border.width: 1
                border.color: root.settingsOpen ? Qt.alpha(Theme.white, 0.20) : root.controlBorder
                Text {
                    anchors.centerIn: parent
                    text: "󰒓"
                    font.family: Theme.fontIcons
                    font.pixelSize: 17
                    color: Theme.white
                }
                MouseArea {
                    id: settingsArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.historyOpen = false
                        root.exitHistorySelection()
                        root.settingsOpen = !root.settingsOpen
                        if (root.settingsOpen && root.service.backendReady)
                            root.service.refreshModels()
                        else
                            Qt.callLater(root.focusInput)
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 12
            Layout.bottomMargin: 8
            Layout.preferredHeight: 1
            color: Qt.alpha(Theme.white, 0.10)
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // History is kept by Xavion in local data/chat_*.json files.
            Column {
                anchors.fill: parent
                visible: root.historyOpen
                spacing: 10

                RowLayout {
                    width: parent.width
                    height: 34
                    spacing: 10

                    Text {
                        text: "Recent conversations"
                        color: Theme.white
                        font.family: Theme.fontMain
                        font.pixelSize: 15
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredWidth: selectionToggleLabel.implicitWidth + 24
                        Layout.preferredHeight: 32
                        radius: 10
                        color: selectionToggleArea.containsMouse
                               ? Qt.alpha(Theme.white, 0.15)
                               : root.controlBackground
                        border.width: 1
                        border.color: root.controlBorder

                        Text {
                            id: selectionToggleLabel
                            anchors.centerIn: parent
                            text: root.historySelectionMode ? "Cancel" : "Select"
                            color: Theme.white
                            font.family: Theme.fontMain
                            font.pixelSize: 12
                            font.bold: true
                        }
                        MouseArea {
                            id: selectionToggleArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !root.service.deletionPending
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.historySelectionMode) {
                                    root.exitHistorySelection()
                                } else {
                                    root.historySelectionMode = true
                                    root.selectedSessionIds = []
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    width: parent.width
                    height: visible ? 34 : 0
                    visible: root.historySelectionMode
                    spacing: 8

                    Text {
                        text: root.selectedSessionIds.length + " selected"
                        color: Theme.grey1
                        font.family: Theme.fontMain
                        font.pixelSize: 11
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredWidth: selectAllLabel.implicitWidth + 22
                        Layout.preferredHeight: 32
                        radius: 10
                        color: selectAllArea.containsMouse
                               ? Qt.alpha(Theme.white, 0.15)
                               : root.controlBackground
                        border.width: 1
                        border.color: root.controlBorder

                        Text {
                            id: selectAllLabel
                            anchors.centerIn: parent
                            text: root.selectedSessionIds.length > 0
                                  && root.selectedSessionIds.length === root.service.savedSessions.length
                                  ? "Deselect all" : "Select all"
                            color: Theme.white
                            font.family: Theme.fontMain
                            font.pixelSize: 11
                        }
                        MouseArea {
                            id: selectAllArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !root.service.deletionPending
                                     && root.service.savedSessions.length > 0
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectAllSessions()
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: deleteSelectedLabel.implicitWidth + 24
                        Layout.preferredHeight: 32
                        radius: 10
                        color: deleteSelectedArea.containsMouse
                               ? Qt.alpha(Theme.red, 0.23)
                               : Qt.alpha(Theme.red, 0.13)
                        opacity: root.selectedSessionIds.length > 0 ? 1 : 0.45
                        border.width: 1
                        border.color: Qt.alpha(Theme.red, 0.40)

                        Text {
                            id: deleteSelectedLabel
                            anchors.centerIn: parent
                            text: "Delete (" + root.selectedSessionIds.length + ")"
                            color: Theme.red
                            font.family: Theme.fontMain
                            font.pixelSize: 11
                            font.bold: true
                        }
                        MouseArea {
                            id: deleteSelectedArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: root.selectedSessionIds.length > 0
                                     && !root.service.deletionPending
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.requestDeletion(root.selectedSessionIds)
                        }
                    }
                }

                Text {
                    visible: root.service.lastError.length > 0
                    width: parent.width
                    text: root.service.lastError
                    color: Theme.red
                    font.family: Theme.fontMain
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                }

                ListView {
                    id: historyList
                    width: parent.width
                    height: Math.max(0, parent.height - (root.historySelectionMode ? 88 : 44)
                                     - (root.service.lastError.length > 0 ? 24 : 0))
                    clip: true
                    spacing: 7
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.service.savedSessions

                    delegate: Rectangle {
                        id: sessionRow
                        required property var modelData
                        readonly property string sessionId: String(modelData.id)
                        readonly property bool selected: root.selectedSessionIds.indexOf(sessionId) !== -1
                        width: historyList.width
                        height: 62
                        radius: 12
                        color: selected
                               ? Qt.alpha(root.accent, 0.19)
                               : historyRow.containsMouse
                                 ? Qt.alpha(Theme.white, 0.14)
                                 : root.controlBackground
                        border.width: 1
                        border.color: selected ? root.accentSoft : root.controlBorder

                        MouseArea {
                            id: historyRow
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !root.service.busy && !root.service.deletionPending
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.historySelectionMode)
                                    root.toggleSelectedSession(sessionRow.sessionId)
                                else
                                    root.service.loadSession(sessionRow.sessionId)
                            }
                        }

                        Rectangle {
                            visible: root.historySelectionMode
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            width: 22
                            height: 22
                            radius: 7
                            color: sessionRow.selected
                                   ? Qt.alpha(root.accent, 0.50)
                                   : Qt.alpha(Theme.white, 0.06)
                            border.width: 1
                            border.color: sessionRow.selected
                                          ? root.accent : root.controlBorder
                            Text {
                                anchors.centerIn: parent
                                text: "✓"
                                visible: sessionRow.selected
                                font.family: Theme.fontMain
                                font.pixelSize: 14
                                font.bold: true
                                color: Theme.white
                            }
                        }

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: root.historySelectionMode ? 48 : 14
                            anchors.right: parent.right
                            anchors.rightMargin: root.historySelectionMode ? 14 : 55
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Text {
                                width: parent.width
                                text: String(modelData.title || "Untitled chat")
                                color: Theme.white
                                font.family: Theme.fontMain
                                font.pixelSize: 12
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: modelData.last_updated
                                      ? Qt.formatDateTime(new Date(Number(modelData.last_updated) * 1000), "dd MMM yyyy · hh:mm")
                                      : "Saved locally"
                                color: Theme.grey1
                                font.family: Theme.fontMain
                                font.pixelSize: 10
                            }
                        }

                        // A single click on a row's trash icon asks for one
                        // confirmation, just like the bulk-delete action.
                        Rectangle {
                            visible: !root.historySelectionMode
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 34
                            height: 34
                            radius: 10
                            color: historyDeleteArea.containsMouse
                                   ? Qt.alpha(Theme.red, 0.20)
                                   : Qt.alpha(Theme.white, 0.04)
                            Text {
                                anchors.centerIn: parent
                                text: "󰆴"
                                color: historyDeleteArea.containsMouse
                                       ? Theme.red : Qt.alpha(Theme.white, 0.65)
                                font.family: Theme.fontIcons
                                font.pixelSize: 16
                            }
                            MouseArea {
                                id: historyDeleteArea
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !root.service.busy && !root.service.deletionPending
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.requestDeletion([sessionRow.sessionId])
                            }
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: root.historyOpen && root.service.savedSessions.length === 0
                text: "No saved conversations yet"
                color: Theme.grey1
                font.family: Theme.fontMain
                font.pixelSize: 12
            }

            // Chat view: messages float directly on the Launcher's glass.
            ListView {
                id: messageList
                anchors.fill: parent
                anchors.topMargin: 9
                anchors.bottomMargin: 7
                visible: !root.settingsOpen && !root.historyOpen
                clip: true
                spacing: 11
                model: root.service.messages
                boundsBehavior: Flickable.StopAtBounds

                // Follow tokens only while the reader is at the bottom.
                // A user scrolling upward immediately takes control back.
                property bool followOutput: true
                function jumpToLatest() {
                    followOutput = true
                    Qt.callLater(function() { messageList.positionViewAtEnd() })
                }
                onMovementStarted: followOutput = false
                onMovementEnded: {
                    if (atYEnd)
                        followOutput = true
                }
                onContentYChanged: {
                    if (!moving && atYEnd && !followOutput)
                        followOutput = true
                }
                onContentHeightChanged: {
                    if (followOutput && !moving)
                        Qt.callLater(function() {
                            if (messageList.followOutput && !messageList.moving)
                                messageList.positionViewAtEnd()
                        })
                }
                onCountChanged: {
                    if (followOutput)
                        Qt.callLater(function() { messageList.positionViewAtEnd() })
                }

                delegate: Item {
                    id: messageDelegate
                    required property string role
                    required property string text
                    required property bool streaming
                    required property string imagesJson
                    readonly property bool fromUser: role === "user"

                    width: messageList.width
                    height: fromUser ? userContent.implicitHeight + 10
                                     : assistantRow.height + 10

                    // Measure the text without constraining it to the bubble width.
                    // TextEdit.implicitWidth is unsuitable here because the edit's
                    // explicit width depends on the bubble itself.
                    Text {
                        id: userWidthProbe
                        visible: false
                        text: messageDelegate.fromUser ? messageDelegate.text : ""
                        font.family: Theme.fontMain
                        font.pixelSize: 13
                        textFormat: Text.PlainText
                    }

                    // Like ChatGPT: attached images sit above the user's bubble,
                    // not inside the text's gradient background.
                    Column {
                        id: userContent
                        visible: messageDelegate.fromUser
                        anchors.right: parent.right
                        spacing: 7
                        width: Math.min(messageList.width * 0.78,
                                        Math.max(userWidthProbe.implicitWidth + 30,
                                                 imageRow.implicitWidth, 50))

                        Row {
                            id: imageRow
                            anchors.right: parent.right
                            spacing: 6
                            readonly property var sources:
                                JSON.parse(messageDelegate.imagesJson || "[]")
                            readonly property real imageSize:
                                Math.min(88, Math.max(48,
                                    (messageList.width * 0.78 - 18) / 4))
                            visible: sources.length > 0

                            Repeater {
                                model: imageRow.sources
                                Rectangle {
                                    required property string modelData
                                    width: imageRow.imageSize
                                    height: imageRow.imageSize
                                    radius: 12
                                    clip: true
                                    color: root.controlBackgroundStrong
                                    border.width: 1
                                    border.color: root.controlBorder
                                    Image {
                                        anchors.fill: parent
                                        source: modelData
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: true
                                        smooth: true
                                        mipmap: true
                                    }
                                }
                            }
                        }

                        Rectangle {
                            id: userBubble
                            visible: messageDelegate.text.length > 0
                            anchors.right: parent.right
                            width: Math.min(messageList.width * 0.78,
                                            Math.max(50, userWidthProbe.implicitWidth + 30))
                            height: userText.implicitHeight + 24
                            radius: 18
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: root.service.gradientStart }
                                GradientStop { position: 0.52; color: root.service.gradientMid }
                                GradientStop { position: 1; color: root.service.gradientEnd }
                            }
                            TextEdit {
                                id: userText
                                x: 15
                                y: 11
                                width: parent.width - 30
                                text: messageDelegate.fromUser ? messageDelegate.text : ""
                                color: Theme.white
                                font.family: Theme.fontMain
                                font.pixelSize: 13
                                wrapMode: TextEdit.Wrap
                                textFormat: TextEdit.PlainText
                                readOnly: true
                                selectByMouse: true
                                selectionColor: Qt.alpha(Theme.white, 0.25)
                            }
                        }
                    }

                    Row {
                        id: assistantRow
                        visible: !messageDelegate.fromUser
                        spacing: 11
                        // Match the max width of user messages for readable lines.
                        width: Math.min(parent.width * 0.78, 740)
                        height: Math.max(30, assistantMarkdown.implicitHeight + 6)

                        Image {
                            width: 29
                            height: 29
                            source: "../assets/xavion/chat.png"
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                        }

                        XavionMarkdown {
                            id: assistantMarkdown
                            width: Math.max(0, assistantRow.width - 40)
                            markdown: messageDelegate.fromUser ? "" : messageDelegate.text
                            streaming: messageDelegate.streaming
                            textColor: Qt.alpha(Theme.white, 0.94)
                            mutedColor: Theme.grey1
                            accentStart: root.service.gradientStart
                            accentMid: root.service.gradientMid
                            accentEnd: root.service.gradientEnd
                            bodyFont: Theme.fontMain
                            bodySize: 13
                        }
                    }
                }

                footer: Item {
                    width: messageList.width
                    height: root.service.awaitingFirstChunk ? 48 : 0
                    visible: root.service.awaitingFirstChunk
                    RowLayout {
                        anchors.left: parent.left
                        anchors.leftMargin: 42
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10

                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width: 4
                            height: 24
                            radius: 2
                            gradient: Gradient {
                                GradientStop { position: 0; color: root.service.gradientStart }
                                GradientStop { position: 0.5; color: root.service.gradientMid }
                                GradientStop { position: 1; color: root.service.gradientEnd }
                            }
                            SequentialAnimation on opacity {
                                running: root.service.awaitingFirstChunk
                                loops: Animation.Infinite
                                NumberAnimation { from: 0.38; to: 1; duration: 700 }
                                NumberAnimation { from: 1; to: 0.38; duration: 700 }
                            }
                        }
                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: root.service.pendingStatus
                            color: root.accent
                            font.family: Theme.fontMain
                            font.pixelSize: 13
                            font.bold: true
                        }
                        Repeater {
                            model: 3
                            Rectangle {
                                required property int index
                                Layout.alignment: Qt.AlignVCenter
                                width: 5
                                height: 5
                                radius: 3
                                color: index === 0 ? root.service.gradientStart
                                      : index === 1 ? root.service.gradientMid
                                      : root.service.gradientEnd
                                SequentialAnimation on opacity {
                                    running: root.service.awaitingFirstChunk
                                    loops: Animation.Infinite
                                    PauseAnimation { duration: index * 135 }
                                    NumberAnimation { from: 0.28; to: 1; duration: 270 }
                                    NumberAnimation { from: 1; to: 0.28; duration: 270 }
                                }
                            }
                        }
                    }
                }
            }

            // Visible only after the reader has scrolled away from new tokens.
            Rectangle {
                z: 3
                visible: !root.settingsOpen && !root.historyOpen
                         && root.service.messages.count > 0 && !messageList.followOutput
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 15
                width: 138
                height: 32
                radius: 16
                color: Qt.alpha(Theme.bg1, 0.96)
                border.width: 1
                border.color: Qt.alpha(root.accent, 0.50)
                Text {
                    anchors.centerIn: parent
                    text: "↓  Latest message"
                    color: Theme.white
                    font.family: Theme.fontMain
                    font.pixelSize: 11
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: messageList.jumpToLatest()
                }
            }

            // Clean Launcher-style empty state: the avatar is the only artwork.
            Column {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -10
                visible: !root.settingsOpen && !root.historyOpen && root.service.messages.count === 0
                spacing: 12

                Image {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 78
                    height: 78
                    source: "../assets/xavion/chat.png"
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Ask Xavion anything"
                    color: Theme.white
                    font.family: Theme.fontMain
                    font.pixelSize: 19
                    font.bold: true
                }
                Text {
                    visible: root.service.lastError.length > 0
                    width: Math.min(360, root.width - 44)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: root.service.lastError
                    color: Theme.red
                    font.family: Theme.fontMain
                    font.pixelSize: 11
                }
            }

            Flickable {
                visible: root.settingsOpen
                anchors.fill: parent
                clip: true
                contentWidth: width
                contentHeight: settingsContent.implicitHeight + 22
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: settingsContent
                    width: parent.width
                    y: 7
                    spacing: 15

                    Text {
                        text: "Appearance"
                        color: Theme.white
                        font.family: Theme.fontMain
                        font.pixelSize: 15
                        font.bold: true
                    }
                    Text {
                        text: "Choose your message gradient — or create your own"
                        color: Theme.grey1
                        font.family: Theme.fontMain
                        font.pixelSize: 12
                    }

                    // Flow, not Row: palettes wrap gracefully on narrow Launchers.
                    Flow {
                        width: parent.width
                        spacing: 10
                        Repeater {
                            model: root.service.gradientPresets.length
                            Item {
                                required property int index
                                readonly property var preset: root.service.gradientPresets[index]
                                width: 56
                                height: 67

                                Rectangle {
                                    id: paletteTile
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 48
                                    height: 48
                                    radius: 14
                                    color: root.controlBackground
                                    border.width: root.service.gradientIndex === index ? 2 : 1
                                    border.color: root.service.gradientIndex === index
                                                  ? root.accent : root.controlBorder
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 30
                                        height: 30
                                        radius: 10
                                        gradient: Gradient {
                                            GradientStop { position: 0; color: preset.start }
                                            GradientStop { position: 0.5; color: preset.mid }
                                            GradientStop { position: 1; color: preset.end }
                                        }
                                        Text {
                                            visible: preset.name === "Custom"
                                            anchors.centerIn: parent
                                            text: "+"
                                            color: Theme.white
                                            font.family: Theme.fontMain
                                            font.pixelSize: 19
                                            font.bold: true
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.service.setGradient(index)
                                    }
                                }
                                Text {
                                    anchors.top: paletteTile.bottom
                                    anchors.topMargin: 5
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 60
                                    horizontalAlignment: Text.AlignHCenter
                                    text: preset.name
                                    elide: Text.ElideRight
                                    color: root.service.gradientIndex === index
                                           ? Theme.white : Theme.grey1
                                    font.family: Theme.fontMain
                                    font.pixelSize: 9
                                }
                            }
                        }
                    }

                    // Make the custom palette useful without opening an external
                    // color picker (which would dismiss the Launcher on Hyprland).
                    Rectangle {
                        visible: root.service.gradientIndex === root.service.customGradientIndex
                        width: parent.width
                        height: visible ? customEditor.implicitHeight + 24 : 0
                        radius: 14
                        color: root.controlBackground
                        border.width: 1
                        border.color: root.controlBorder

                        Column {
                            id: customEditor
                            x: 12
                            y: 12
                            width: parent.width - 24
                            spacing: 10

                            Text {
                                text: "Custom gradient"
                                color: Theme.white
                                font.family: Theme.fontMain
                                font.pixelSize: 13
                                font.bold: true
                            }
                            Text {
                                text: "Enter HEX colors and press Enter to apply each stop"
                                color: Theme.grey1
                                font.family: Theme.fontMain
                                font.pixelSize: 11
                            }
                            Rectangle {
                                width: parent.width
                                height: 24
                                radius: 12
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: root.service.customGradientStart }
                                    GradientStop { position: 0.5; color: root.service.customGradientMid }
                                    GradientStop { position: 1; color: root.service.customGradientEnd }
                                }
                            }
                            Flow {
                                width: parent.width
                                spacing: 10
                                Repeater {
                                    model: ["Start", "Middle", "End"]
                                    Column {
                                        id: stopEditor
                                        required property int index
                                        required property string modelData
                                        readonly property string currentValue:
                                            index === 0 ? root.service.customGradientStart
                                            : index === 1 ? root.service.customGradientMid
                                            : root.service.customGradientEnd
                                        spacing: 5
                                        Text {
                                            text: stopEditor.modelData
                                            color: Theme.grey1
                                            font.family: Theme.fontMain
                                            font.pixelSize: 10
                                        }
                                        Rectangle {
                                            width: 125
                                            height: 32
                                            radius: 9
                                            color: Qt.alpha(Theme.bg0, 0.32)
                                            border.width: 1
                                            border.color: hexInput.activeFocus
                                                          ? root.accentSoft : root.controlBorder
                                            Rectangle {
                                                anchors.left: parent.left
                                                anchors.leftMargin: 8
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 15
                                                height: 15
                                                radius: 5
                                                color: stopEditor.currentValue
                                            }
                                            TextInput {
                                                id: hexInput
                                                anchors.left: parent.left
                                                anchors.leftMargin: 29
                                                anchors.right: parent.right
                                                anchors.rightMargin: 5
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: stopEditor.currentValue
                                                maximumLength: 7
                                                font.family: Theme.fontMain
                                                font.pixelSize: 11
                                                color: Theme.white
                                                selectByMouse: true
                                                selectionColor: root.accentSoft
                                                onEditingFinished: {
                                                    if (!root.service.setCustomGradientStop(
                                                            stopEditor.index, text))
                                                        text = stopEditor.currentValue
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Qt.alpha(Theme.white, 0.10) }
                    Text {
                        text: "Response tone"
                        color: Theme.white
                        font.family: Theme.fontMain
                        font.pixelSize: 15
                        font.bold: true
                    }
                    Flow {
                        width: parent.width
                        spacing: 9
                        Repeater {
                            model: root.service.toneOptions
                            Rectangle {
                                required property var modelData
                                width: toneLabel.implicitWidth + 29
                                height: 38
                                radius: 12
                                color: root.service.toneMode === modelData.value
                                       ? Qt.alpha(Theme.white, 0.16) : root.controlBackground
                                border.width: 1
                                border.color: root.service.toneMode === modelData.value
                                              ? root.accentSoft : root.controlBorder
                                Text {
                                    id: toneLabel
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: root.service.toneMode === modelData.value
                                           ? Theme.white : Qt.alpha(Theme.white, 0.75)
                                    font.family: Theme.fontMain
                                    font.pixelSize: 12
                                    font.bold: root.service.toneMode === modelData.value
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.service.setTone(modelData.value)
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: root.service.reasoningSupported
                        width: parent.width; height: 1
                        color: Qt.alpha(Theme.white, 0.10)
                    }
                    Text {
                        visible: root.service.reasoningSupported
                        text: "Reasoning"
                        color: Theme.white
                        font.family: Theme.fontMain
                        font.pixelSize: 15
                        font.bold: true
                    }
                    Flow {
                        visible: root.service.reasoningSupported
                        width: parent.width
                        spacing: 9
                        Repeater {
                            model: root.service.reasoningOptions
                            Rectangle {
                                required property var modelData
                                width: reasoningLabel.implicitWidth + 29
                                height: 38
                                radius: 12
                                opacity: modelData.enabled ? 1 : 0.4
                                color: root.service.reasoningMode === modelData.value
                                       ? Qt.alpha(Theme.white, 0.16) : root.controlBackground
                                border.width: 1
                                border.color: root.service.reasoningMode === modelData.value
                                              ? root.accentSoft : root.controlBorder
                                Text {
                                    id: reasoningLabel
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: Theme.white
                                    font.family: Theme.fontMain
                                    font.pixelSize: 12
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: modelData.enabled
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.service.setReasoning(modelData.value)
                                }
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Qt.alpha(Theme.white, 0.10) }
                    Row {
                        width: parent.width
                        height: 26
                        spacing: 12
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Local model"
                            color: Theme.white
                            font.family: Theme.fontMain
                            font.pixelSize: 15
                            font.bold: true
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰑐"
                            color: Theme.grey1
                            font.family: Theme.fontIcons
                            font.pixelSize: 17
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.service.refreshModels()
                            }
                        }
                    }
                    Text {
                        visible: root.service.availableModels.length === 0
                        text: root.service.backendReady ? "No local models found" : "Starting Xavion..."
                        color: Theme.grey1
                        font.family: Theme.fontMain
                        font.pixelSize: 12
                    }
                    Repeater {
                        model: root.service.availableModels
                        Rectangle {
                            required property string modelData
                            readonly property bool selected: modelData === root.service.selectedModel
                                || (root.service.selectedModel.length === 0
                                    && modelData === root.service.activeModel)
                            width: settingsContent.width
                            height: 43
                            radius: 13
                            color: selected ? Qt.alpha(Theme.white, 0.16) : root.controlBackground
                            border.width: 1
                            border.color: selected ? root.accentSoft : root.controlBorder
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData
                                color: Theme.white
                                font.family: Theme.fontMain
                                font.pixelSize: 12
                            }
                            Text {
                                visible: parent.selected
                                anchors.right: parent.right
                                anchors.rightMargin: 15
                                anchors.verticalCenter: parent.verticalCenter
                                text: ""
                                color: root.accent
                                font.family: Theme.fontIcons
                                font.pixelSize: 14
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.service.setModel(modelData)
                            }
                        }
                    }
                }
            }
        }

        // The composer grows vertically only while attachments are pending.
        // Attached thumbnails and text entry share one glass surface.
        Item {
            visible: !root.settingsOpen && !root.historyOpen
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? (74 + (root.pendingImages.length ? 70 : 0)) : 0

            Rectangle {
                id: composerBar
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 7
                width: Math.min(parent.width, 540)
                height: 44 + (root.pendingImages.length ? 70 : 0)
                radius: root.pendingImages.length ? 19 : height / 2
                color: root.controlBackgroundStrong
                border.width: 1
                border.color: composerInput.activeFocus
                              ? Qt.alpha(Theme.white, 0.22) : root.controlBorder
                Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Behavior on radius { NumberAnimation { duration: 160 } }

                Row {
                    id: pendingStrip
                    visible: root.pendingImages.length > 0
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.leftMargin: 11
                    anchors.topMargin: 8
                    spacing: 8

                    Repeater {
                        model: root.pendingImages
                        Rectangle {
                            id: previewTile
                            required property int index
                            required property var modelData
                            width: 54
                            height: 54
                            radius: 10
                            clip: true
                            color: root.controlBackground
                            border.width: 1
                            border.color: root.controlBorder

                            Image {
                                anchors.fill: parent
                                source: previewTile.modelData.url
                                fillMode: Image.PreserveAspectCrop
                                smooth: true
                                asynchronous: true
                                mipmap: true
                            }
                            Rectangle {
                                width: 17
                                height: 17
                                radius: 9
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 3
                                color: Qt.alpha(Theme.bg0, 0.86)
                                border.width: 1
                                border.color: Qt.alpha(Theme.white, 0.3)
                                Text {
                                    anchors.centerIn: parent
                                    text: "×"
                                    color: Theme.white
                                    font.pixelSize: 13
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.removePendingImage(previewTile.index)
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: attachButton
                    visible: root.service.visionSupported
                    anchors.left: parent.left
                    anchors.leftMargin: 7
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 6
                    width: 32
                    height: 32
                    radius: 16
                    color: attachArea.containsMouse
                           ? Qt.alpha(Theme.white, 0.13) : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "󰏢" // nf-md-paperclip
                        color: Theme.white
                        font.family: Theme.fontIcons
                        font.pixelSize: 18
                    }
                    MouseArea {
                        id: attachArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: root.service.backendReady && !root.service.busy
                                 && root.pendingImages.length < root.maxImages
                        cursorShape: Qt.PointingHandCursor
                        onClicked: imagePicker.openWith(root.pendingImages)
                    }
                }

                TextInput {
                    id: composerInput
                    anchors.left: attachButton.visible ? attachButton.right : parent.left
                    anchors.leftMargin: attachButton.visible ? 9 : 18
                    anchors.right: sendButton.left
                    anchors.rightMargin: 11
                    anchors.bottom: parent.bottom
                    height: 44
                    verticalAlignment: TextInput.AlignVCenter
                    enabled: root.service.backendReady && !root.service.busy
                    clip: true
                    color: Theme.white
                    selectionColor: Qt.alpha(Theme.blue, 0.45)
                    selectedTextColor: Theme.white
                    font.family: Theme.fontMain
                    font.pixelSize: 14
                    onAccepted: root.sendMessage()
                    Keys.onEscapePressed: function(event) {
                        root.back()
                        event.accepted = true
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: composerInput.text.length === 0
                        text: root.service.busy ? "Xavion is responding..."
                              : root.service.backendReady ? "Ask anything..." : "Starting Xavion..."
                        color: Theme.grey1
                        opacity: 0.85
                        font.family: Theme.fontMain
                        font.pixelSize: 14
                    }
                }

                Rectangle {
                    id: sendButton
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 6
                    width: 32
                    height: 32
                    radius: 16
                    readonly property bool canSend: root.service.backendReady
                                                    && !root.service.busy
                                                    && (composerInput.text.trim().length > 0
                                                        || root.pendingImages.length > 0)
                    color: canSend ? Qt.alpha(Theme.white, 0.14) : Qt.alpha(Theme.white, 0.06)
                    border.width: 1
                    border.color: canSend ? Qt.alpha(Theme.white, 0.18) : root.controlBorder
                    Text {
                        anchors.centerIn: parent
                        text: "󰁝"
                        color: sendButton.canSend ? Theme.white : Theme.grey1
                        font.family: Theme.fontIcons
                        font.pixelSize: 16
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: sendButton.canSend
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.sendMessage()
                    }
                }
            }

            Text {
                anchors.top: composerBar.bottom
                anchors.topMargin: 7
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.service.lastError.length > 0
                    ? root.service.lastError
                    : "Enter to send  ·  Esc to return"
                color: root.service.lastError.length > 0
                       ? Theme.red : Qt.alpha(Theme.white, 0.36)
                font.family: Theme.fontMain
                font.pixelSize: 10
                width: Math.min(parent.width - 20, 540)
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
    }

    // One confirmation dialog for individual and multi-conversation deletion.
    Item {
        anchors.fill: parent
        z: 30
        visible: root.deleteConfirmationOpen

        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Theme.bg0, 0.68)
            MouseArea {
                anchors.fill: parent
                onClicked: {} // Keep the dialog modal; use Cancel to dismiss.
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 420)
            height: 218
            radius: 19
            color: Qt.alpha(Theme.bg1, 0.98)
            border.width: 1
            border.color: Qt.alpha(Theme.white, 0.18)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 23
                spacing: 12

                Text {
                    text: root.pendingDeletionIds.length === 1
                          ? "Delete conversation?"
                          : "Delete " + root.pendingDeletionIds.length + " conversations?"
                    color: Theme.white
                    font.family: Theme.fontMain
                    font.pixelSize: 17
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    text: root.pendingDeletionIds.length === 1
                          ? "This conversation will be permanently removed from local history. This cannot be undone."
                          : "The selected conversations will be permanently removed from local history. This cannot be undone."
                    color: Theme.grey1
                    font.family: Theme.fontMain
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredWidth: 93
                        Layout.preferredHeight: 38
                        radius: 11
                        color: cancelDeleteArea.containsMouse
                               ? Qt.alpha(Theme.white, 0.16)
                               : root.controlBackgroundStrong
                        border.width: 1
                        border.color: root.controlBorder
                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: Theme.white
                            font.family: Theme.fontMain
                            font.pixelSize: 12
                        }
                        MouseArea {
                            id: cancelDeleteArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.cancelDeletion()
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 93
                        Layout.preferredHeight: 38
                        radius: 11
                        color: confirmDeleteArea.containsMouse
                               ? Qt.alpha(Theme.red, 0.32)
                               : Qt.alpha(Theme.red, 0.19)
                        border.width: 1
                        border.color: Qt.alpha(Theme.red, 0.58)
                        Text {
                            anchors.centerIn: parent
                            text: "Delete"
                            color: Theme.red
                            font.family: Theme.fontMain
                            font.pixelSize: 12
                            font.bold: true
                        }
                        MouseArea {
                            id: confirmDeleteArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !root.service.deletionPending
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.service.deleteSessions(root.pendingDeletionIds))
                                    root.cancelDeletion()
                            }
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: root.service
        function onSessionLoaded() {
            root.historyOpen = false
            root.exitHistorySelection()
            Qt.callLater(root.focusInput)
            messageList.jumpToLatest()
        }
        function onSessionsDeleted(deleted, failed) {
            // The service has already refreshed the list. The history panel
            // stays open and a failed deletion is visible as an error there.
            root.exitHistorySelection()
        }
    }

    Connections {
        target: root.service
        // Output growth is handled by ListView.followOutput. Never force the
        // view to the bottom while the user is inspecting an earlier message.
        function onBackendReadyChanged() {
            root.flushQueuedMessage()
            Qt.callLater(root.focusInput)
        }
        function onVisionSupportedChanged() {
            if (!root.service.visionSupported) {
                root.pendingImages = []
                imagePicker.cancel()
            }
        }
        function onBusyChanged() {
            if (!root.service.busy) {
                root.flushQueuedMessage()
                Qt.callLater(root.focusInput)
            }
        }
    }
}
