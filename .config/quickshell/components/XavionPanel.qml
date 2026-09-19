import QtQuick
import QtQuick.Layouts

import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

import ".."

PanelWindow {
    id: panel

    required property var service

    property bool settingsOpen: false
    property bool expanded: false
    property string reservedMonitor: ""

    readonly property bool onHdmi:
        panel.screen && panel.screen.name === "HDMI-A-1"

    readonly property int normalOuterTop:
        onHdmi ? 10 : 2

    readonly property int normalOuterRight:
        onHdmi ? 10 : 12

    readonly property int normalOuterBottom:
        onHdmi ? 10 : 12

    readonly property int normalOuterLeft:
        onHdmi ? 10 : 12

    readonly property int normalInnerGap:
        onHdmi ? 4 : 5

    // Expanded background glows follow the currently selected message theme.
    readonly property color expandedGlowStart:
        Qt.alpha(service.gradientStart, 0.050)

    readonly property color expandedGlowMid:
        Qt.alpha(service.gradientMid, 0.055)

    readonly property color expandedGlowEnd:
        Qt.alpha(service.gradientEnd, 0.040)

    readonly property color expandedGlowStartSoft:
        Qt.alpha(service.gradientStart, 0.030)

    readonly property color expandedGlowMidSoft:
        Qt.alpha(service.gradientMid, 0.028)

    readonly property color expandedGlowEndSoft:
        Qt.alpha(service.gradientEnd, 0.020)


    readonly property var focusedWorkspaceRef:
        Hyprland.focusedWorkspace

    function applyWorkspaceReservation(expand, monitorName): void {
        var targetMonitor =
            monitorName && monitorName.length > 0
            ? monitorName
            : (
                panel.screen
                ? panel.screen.name
                : ""
            )

        if (targetMonitor.length === 0)
            return

        var helperPath =
            Quickshell.env("HOME")
            + "/.config/hypr/xavion_sidebar.lua"

        var lua =
            'local x = dofile("'
            + helperPath
            + '"); x.set("'
            + targetMonitor
            + '", '
            + (expand ? "true" : "false")
            + ', '
            + panel.implicitWidth
            + ', '
            + (
                targetMonitor === "HDMI-A-1"
                ? 10
                : 12
            )
            + ')'

        Quickshell.execDetached([
            "hyprctl",
            "eval",
            lua
        ])
    }

    function closePanel(): void {
        settingsOpen = false

        if (expanded) {
            applyWorkspaceReservation(false, reservedMonitor)
            expanded = false
            reservedMonitor = ""
        }

        service.closePanel()
    }

    function enterExpandedMode(): void {
        if (expanded)
            return

        reservedMonitor =
            panel.screen
            ? panel.screen.name
            : ""

        expanded = true
        applyWorkspaceReservation(true, reservedMonitor)

        Qt.callLater(function() {
            input.forceActiveFocus()
        })
    }

    function leaveExpandedMode(): void {
        if (!expanded)
            return

        applyWorkspaceReservation(false, reservedMonitor)

        expanded = false
        reservedMonitor = ""

        Qt.callLater(function() {
            input.forceActiveFocus()
        })
    }

    function toggleExpandedMode(): void {
        if (expanded)
            leaveExpandedMode()
        else
            enterExpandedMode()
    }

    onFocusedWorkspaceRefChanged: {
        if (expanded)
            applyWorkspaceReservation(true, reservedMonitor)
    }

    implicitWidth: 450
    implicitHeight: 550

    anchors {
        top: true
        bottom: expanded
        left: true
    }

    margins {
        top: expanded ? normalOuterTop : 0
        bottom: expanded ? normalOuterBottom : 0
        left: normalOuterLeft
    }

    // Never reserve layer-shell space: other Quickshell surfaces keep the
    // full monitor. Only Hyprland workspaces are shifted by xavion_sidebar.lua.
    exclusiveZone: 0

    color: "transparent"

    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: WlrLayershell.OnDemand

    function submitMessage(): void {
        var message = input.text.trim()

        if (message.length === 0)
            return

        if (service.sendMessage(message))
            input.text = ""
    }

    Component.onCompleted: {
        service.ensureBackend()

        Qt.callLater(function() {
            input.forceActiveFocus()
        })
    }

    Component.onDestruction: {
        if (expanded && reservedMonitor.length > 0)
            applyWorkspaceReservation(false, reservedMonitor)
    }

    HyprlandFocusGrab {
        id: focusGrab

        // Outside-click closing is only wanted in compact mode.
        active: !panel.expanded
        windows: [ panel ]

        onCleared: {
            if (service.panelOpen && !panel.expanded)
                panel.closePanel()
        }
    }

    BackgroundEffect.blurRegion:
        Glass.blurEnabled && !panel.expanded
        ? panelBlurRegion
        : null

    Region {
        id: panelBlurRegion
        item: panelGlass
        radius: panelGlass.radius
    }

    GlassSurface {
        id: panelGlass

        anchors.fill: parent

        // Compact mode keeps the normal dotfiles glass material.
        // Expanded mode becomes Xavion's own opaque surface.
        glassTint: panel.expanded ? "#050506" : Glass.tint
        glassOpacity: panel.expanded ? 1.0 : Glass.opacity
        glassRadius: 18
        showBorder: !panel.expanded
        showHighlight: !panel.expanded
        clip: true

        // ============================================================
        // EXPANDED-ONLY XAVION BACKGROUND
        // ============================================================
        //
        // Compact mode keeps the normal glass material.
        // Expanded mode gets an almost-black background with a couple of very
        // soft circular ambient glows in Xavion's palette. The glows are made
        // only from a few translucent circles and slow position/scale
        // animations, which is much lighter than running a continuously
        // blurred shader-based effect.
        Item {
            id: expandedBackground

            anchors.fill: parent
            visible: panel.expanded

            Rectangle {
                anchors.fill: parent
                radius: panelGlass.radius
                color: "#050506"
            }

            Item {
                id: glowCanvas

                anchors.fill: parent
                visible: panel.expanded

                // Warm orange/red glow near the upper-left area.
                Item {
                    id: warmGlow

                    width: 460
                    height: 460

                    x: -150
                    y: -80

                    Rectangle {
                        anchors.centerIn: parent
                        width: 460
                        height: 460
                        radius: width / 2
                        color: panel.expandedGlowStart
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 340
                        height: 340
                        radius: width / 2
                        color: panel.expandedGlowMid
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 220
                        height: 220
                        radius: width / 2
                        color: panel.expandedGlowEnd
                    }

                    SequentialAnimation on x {
                        running: panel.expanded && panel.visible
                        loops: Animation.Infinite

                        NumberAnimation {
                            from: -150
                            to: -90
                            duration: 24000
                            easing.type: Easing.InOutSine
                        }

                        NumberAnimation {
                            from: -90
                            to: -150
                            duration: 24000
                            easing.type: Easing.InOutSine
                        }
                    }

                    SequentialAnimation on y {
                        running: panel.expanded && panel.visible
                        loops: Animation.Infinite

                        NumberAnimation {
                            from: -80
                            to: -20
                            duration: 32000
                            easing.type: Easing.InOutSine
                        }

                        NumberAnimation {
                            from: -20
                            to: -80
                            duration: 32000
                            easing.type: Easing.InOutSine
                        }
                    }

                    SequentialAnimation on scale {
                        running: panel.expanded && panel.visible
                        loops: Animation.Infinite

                        NumberAnimation {
                            from: 0.98
                            to: 1.04
                            duration: 28000
                            easing.type: Easing.InOutSine
                        }

                        NumberAnimation {
                            from: 1.04
                            to: 0.98
                            duration: 28000
                            easing.type: Easing.InOutSine
                        }
                    }
                }

                // Secondary magenta glow lower on the right side.
                Item {
                    id: roseGlow

                    width: 340
                    height: 340

                    x: panelGlass.width - 240
                    y: panelGlass.height - 430

                    Rectangle {
                        anchors.centerIn: parent
                        width: 340
                        height: 340
                        radius: width / 2
                        color: panel.expandedGlowStartSoft
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 220
                        height: 220
                        radius: width / 2
                        color: panel.expandedGlowMidSoft
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 120
                        height: 120
                        radius: width / 2
                        color: panel.expandedGlowEndSoft
                    }

                    SequentialAnimation on x {
                        running: panel.expanded && panel.visible
                        loops: Animation.Infinite

                        NumberAnimation {
                            from: panelGlass.width - 240
                            to: panelGlass.width - 285
                            duration: 30000
                            easing.type: Easing.InOutSine
                        }

                        NumberAnimation {
                            from: panelGlass.width - 285
                            to: panelGlass.width - 240
                            duration: 30000
                            easing.type: Easing.InOutSine
                        }
                    }

                    SequentialAnimation on y {
                        running: panel.expanded && panel.visible
                        loops: Animation.Infinite

                        NumberAnimation {
                            from: panelGlass.height - 430
                            to: panelGlass.height - 360
                            duration: 36000
                            easing.type: Easing.InOutSine
                        }

                        NumberAnimation {
                            from: panelGlass.height - 360
                            to: panelGlass.height - 430
                            duration: 36000
                            easing.type: Easing.InOutSine
                        }
                    }

                    SequentialAnimation on scale {
                        running: panel.expanded && panel.visible
                        loops: Animation.Infinite

                        NumberAnimation {
                            from: 0.96
                            to: 1.02
                            duration: 34000
                            easing.type: Easing.InOutSine
                        }

                        NumberAnimation {
                            from: 1.02
                            to: 0.96
                            duration: 34000
                            easing.type: Easing.InOutSine
                        }
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: panelGlass.radius
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1.0, 1.0, 1.0, 0.070)
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            // ============================================================
            // HEADER
            // ============================================================

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                spacing: 8

                // New chat / Back.
                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32

                    radius: width / 2

                    color:
                        newChatMouse.containsMouse
                        ? Qt.alpha(Theme.white, 0.10)
                        : "transparent"

                    border.width: 1
                    border.color: Qt.alpha(Theme.white, 0.10)

                    Text {
                        anchors.centerIn: parent

                        // Pencil in chat view, back arrow in settings view.
                        text: panel.settingsOpen ? "󰁍" : "󰏫"

                        color:
                            newChatMouse.containsMouse
                            ? Theme.white
                            : Theme.grey1

                        font.family: Theme.fontIcons
                        font.pixelSize: panel.settingsOpen ? 15 : 14
                    }

                    MouseArea {
                        id: newChatMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        onClicked: {
                            if (panel.settingsOpen) {
                                panel.settingsOpen = false
                            } else {
                                service.newConversation()
                            }
                        }
                    }
                }

                // Settings.
                Rectangle {
                    visible: !panel.settingsOpen

                    Layout.preferredWidth: visible ? 32 : 0
                    Layout.preferredHeight: 32

                    radius: width / 2

                    color:
                        settingsMouse.containsMouse
                        ? Qt.alpha(Theme.white, 0.10)
                        : "transparent"

                    border.width: 1
                    border.color: Qt.alpha(Theme.white, 0.10)

                    Text {
                        anchors.centerIn: parent

                        text: "󰒓"

                        color:
                            settingsMouse.containsMouse
                            ? Theme.white
                            : Theme.grey1

                        font.family: Theme.fontIcons
                        font.pixelSize: 15
                    }

                    MouseArea {
                        id: settingsMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        onClicked: {
                            panel.settingsOpen = true

                            if (service.backendReady)
                                service.refreshModels()
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                // Expand to sidebar / restore compact panel.
                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32

                    radius: width / 2

                    color:
                        zoomMouse.containsMouse
                        ? Qt.alpha(Theme.white, 0.10)
                        : "transparent"

                    border.width: 1
                    border.color: Qt.alpha(Theme.white, 0.10)

                    Item {
                        anchors.centerIn: parent
                        width: 16
                        height: 16

                        // Compact mode: one square -> enter normal-window mode.
                        Rectangle {
                            visible: !panel.expanded

                            anchors.centerIn: parent
                            width: 11
                            height: 11
                            radius: 2

                            color: "transparent"
                            border.width: 1
                            border.color:
                                zoomMouse.containsMouse
                                ? Theme.white
                                : Theme.grey1
                        }

                        // Window mode: overlapping squares -> restore compact mode.
                        Rectangle {
                            visible: panel.expanded

                            x: 2
                            y: 2
                            width: 9
                            height: 9
                            radius: 1.5

                            color: "transparent"
                            border.width: 1
                            border.color:
                                zoomMouse.containsMouse
                                ? Theme.white
                                : Theme.grey1
                        }

                        Rectangle {
                            visible: panel.expanded

                            x: 5
                            y: 5
                            width: 9
                            height: 9
                            radius: 1.5

                            color: Qt.alpha(Theme.bg1, 0.92)
                            border.width: 1
                            border.color:
                                zoomMouse.containsMouse
                                ? Theme.white
                                : Theme.grey1
                        }
                    }

                    MouseArea {
                        id: zoomMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        onClicked:
                            panel.toggleExpandedMode()
                    }
                }
            }

            // ============================================================
            // CHAT
            // ============================================================

            Item {
                visible: !panel.settingsOpen

                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: messageList

                    anchors.fill: parent
                    anchors.rightMargin: 6

                    clip: true
                    spacing: 6

                    model: service.messages
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Item {
                        id: messageDelegate

                        required property string role
                        required property string text
                        required property bool streaming

                        readonly property bool fromUser:
                            role === "user"

                        width: messageList.width

                        height:
                            fromUser
                            ? userBubble.height + 8
                            : assistantText.implicitHeight + 12

                        // ====================================================
                        // USER MESSAGE
                        // ====================================================

                        Rectangle {
                            id: userBubble

                            visible: messageDelegate.fromUser

                            anchors.right: parent.right

                            width: Math.min(
                                messageList.width * 0.78,
                                userText.implicitWidth + 24
                            )

                            height: userText.implicitHeight + 18

                            radius: 16

                            // Message-sent entrance animation:
                            // the bubble grows out from the right side of the chat,
                            // similar to modern messaging apps.
                            opacity: messageDelegate.fromUser ? 0 : 1
                            scale: messageDelegate.fromUser ? 0.72 : 1
                            transformOrigin: Item.BottomRight

                            property real entranceOffset: 18

                            transform: Translate {
                                x: userBubble.entranceOffset
                            }

                            gradient: Gradient {
                                orientation: Gradient.Horizontal

                                GradientStop {
                                    position: 0.0
                                    color: service.gradientStart
                                }

                                GradientStop {
                                    position: 0.52
                                    color: service.gradientMid
                                }

                                GradientStop {
                                    position: 1.0
                                    color: service.gradientEnd
                                }
                            }

                            Text {
                                id: userText

                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top

                                    leftMargin: 12
                                    rightMargin: 12
                                    topMargin: 9
                                }

                                text: messageDelegate.text

                                color: Theme.white

                                font.family: Theme.fontMain
                                font.pixelSize: 12

                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                            }
                        }

                        ParallelAnimation {
                            id: userBubbleAppear

                            NumberAnimation {
                                target: userBubble
                                property: "opacity"

                                from: 0
                                to: 1

                                duration: 170
                                easing.type: Easing.OutCubic
                            }

                            NumberAnimation {
                                target: userBubble
                                property: "scale"

                                from: 0.72
                                to: 1

                                duration: 220
                                easing.type: Easing.OutBack
                            }

                            NumberAnimation {
                                target: userBubble
                                property: "entranceOffset"

                                from: 18
                                to: 0

                                duration: 210
                                easing.type: Easing.OutCubic
                            }
                        }

                        Component.onCompleted: {
                            if (messageDelegate.fromUser) {
                                Qt.callLater(function() {
                                    userBubbleAppear.start()
                                })
                            }
                        }

                        // ====================================================
                        // XAVION MESSAGE
                        // ====================================================

                        Text {
                            id: assistantText

                            visible: !messageDelegate.fromUser

                            anchors {
                                left: parent.left
                                right: parent.right

                                leftMargin: 10
                                rightMargin: 20
                            }

                            text:
                                messageDelegate.text
                                + (
                                    messageDelegate.streaming
                                    ? " ▌"
                                    : ""
                                )

                            color: Theme.white

                            font.family: Theme.fontMain
                            font.pixelSize: 12

                            wrapMode: Text.Wrap
                            textFormat: Text.MarkdownText
                            linkColor: Theme.blue
                        }
                    }

                    footer: Item {
                        width: messageList.width
                        height: service.awaitingFirstChunk ? 34 : 0
                        visible: service.awaitingFirstChunk

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 5

                            Repeater {
                                model: 3

                                Rectangle {
                                    required property int index

                                    width: 6
                                    height: 6
                                    radius: 3

                                    color: Theme.grey1
                                    opacity: 0.35

                                    SequentialAnimation on opacity {
                                        running: service.awaitingFirstChunk
                                        loops: Animation.Infinite

                                        PauseAnimation {
                                            duration: index * 140
                                        }

                                        NumberAnimation {
                                            from: 0.35
                                            to: 1.0
                                            duration: 220
                                            easing.type: Easing.InOutQuad
                                        }

                                        NumberAnimation {
                                            from: 1.0
                                            to: 0.35
                                            duration: 220
                                            easing.type: Easing.InOutQuad
                                        }

                                        PauseAnimation {
                                            duration: (2 - index) * 140
                                        }
                                    }

                                    SequentialAnimation on y {
                                        running: service.awaitingFirstChunk
                                        loops: Animation.Infinite

                                        PauseAnimation {
                                            duration: index * 140
                                        }

                                        NumberAnimation {
                                            from: 0
                                            to: -3
                                            duration: 180
                                            easing.type: Easing.OutQuad
                                        }

                                        NumberAnimation {
                                            from: -3
                                            to: 0
                                            duration: 180
                                            easing.type: Easing.InQuad
                                        }

                                        PauseAnimation {
                                            duration: (2 - index) * 140
                                        }
                                    }
                                }
                            }
                        }
                    }

                    onCountChanged: {
                        Qt.callLater(function() {
                            messageList.positionViewAtEnd()
                        })
                    }
                }

                // ============================================================
                // EMPTY STATE
                // ============================================================

                Column {
                    anchors.centerIn: parent
                    spacing: 6

                    visible: service.messages.count === 0

                    Image {
                        anchors.horizontalCenter:
                            parent.horizontalCenter

                        width: 54
                        height: 54

                        source: "../assets/xavion/chat.png"

                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                    }

                    Text {
                        anchors.horizontalCenter:
                            parent.horizontalCenter

                        text: "Ask Xavion anything"

                        color: Theme.grey1
                        font.family: Theme.fontMain
                        font.pixelSize: 12
                    }

                    Text {
                        anchors.horizontalCenter:
                            parent.horizontalCenter

                        text: service.statusText

                        color:
                            service.busy
                            ? Theme.orange
                            : service.backendReady
                                ? Theme.green
                                : Theme.grey1

                        font.family: Theme.fontMain
                        font.pixelSize: 10
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter

                        visible: service.lastError.length > 0

                        width: 320
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap

                        text: service.lastError

                        color: Theme.red
                        font.family: Theme.fontMain
                        font.pixelSize: 10
                    }
                }
            }

            // ============================================================
            // SETTINGS
            // ============================================================

            Item {
                visible: panel.settingsOpen

                Layout.fillWidth: true
                Layout.fillHeight: true

                Flickable {
                    id: settingsFlick

                    anchors.fill: parent

                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    contentWidth: width
                    contentHeight: settingsColumn.implicitHeight + 20

                    Column {
                        id: settingsColumn

                        x: 8
                        y: 10

                        width: settingsFlick.width - 16
                        spacing: 18

                        Text {
                            text: "Settings"

                            color: Theme.white
                            font.family: Theme.fontMain
                            font.pixelSize: 16
                            font.bold: true
                        }

                        // ====================================================
                        // MESSAGE THEME
                        // ====================================================

                        Column {
                            width: parent.width
                            spacing: 10

                            Text {
                                text: "Message theme"

                                color: Theme.white
                                font.family: Theme.fontMain
                                font.pixelSize: 12
                                font.bold: true
                            }

                            Text {
                                width: parent.width

                                text: "Choose the gradient used for your messages, send button and expanded background."

                                color: Theme.grey1
                                font.family: Theme.fontMain
                                font.pixelSize: 10

                                wrapMode: Text.Wrap
                            }

                            Row {
                                anchors.horizontalCenter:
                                    parent.horizontalCenter

                                spacing: 12

                                Repeater {
                                    model: service.gradientPresets.length

                                    Item {
                                        required property int index

                                        width: 44
                                        height: 44

                                        Rectangle {
                                            anchors.centerIn: parent

                                            width: 40
                                            height: 40
                                            radius: width / 2

                                            gradient: Gradient {
                                                orientation:
                                                    Gradient.Horizontal

                                                GradientStop {
                                                    position: 0.0
                                                    color:
                                                        service.gradientPresets[
                                                            index
                                                        ].start
                                                }

                                                GradientStop {
                                                    position: 0.52
                                                    color:
                                                        service.gradientPresets[
                                                            index
                                                        ].mid
                                                }

                                                GradientStop {
                                                    position: 1.0
                                                    color:
                                                        service.gradientPresets[
                                                            index
                                                        ].end
                                                }
                                            }

                                            border.width:
                                                service.gradientIndex === index
                                                ? 2
                                                : 1

                                            border.color:
                                                service.gradientIndex === index
                                                ? Theme.white
                                                : Qt.alpha(
                                                    Theme.white,
                                                    0.18
                                                )
                                        }

                                        Rectangle {
                                            anchors.centerIn: parent

                                            width: 44
                                            height: 44
                                            radius: width / 2

                                            color: "transparent"

                                            border.width:
                                                service.gradientIndex === index
                                                ? 1
                                                : 0

                                            border.color:
                                                Qt.alpha(
                                                    Theme.white,
                                                    0.30
                                                )
                                        }

                                        MouseArea {
                                            anchors.fill: parent

                                            hoverEnabled: true
                                            cursorShape:
                                                Qt.PointingHandCursor

                                            onClicked:
                                                service.setGradient(index)
                                        }
                                    }
                                }
                            }

                            Text {
                                anchors.horizontalCenter:
                                    parent.horizontalCenter

                                text:
                                    service.gradientPresets[
                                        service.gradientIndex
                                    ].name

                                color: Theme.grey1
                                font.family: Theme.fontMain
                                font.pixelSize: 10
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 1

                            color:
                                Qt.alpha(
                                    Theme.white,
                                    0.08
                                )
                        }

                        // ====================================================
                        // TONE
                        // ====================================================

                        Column {
                            width: parent.width
                            spacing: 10

                            Text {
                                text: "Tone"

                                color: Theme.white
                                font.family: Theme.fontMain
                                font.pixelSize: 12
                                font.bold: true
                            }

                            Text {
                                width: parent.width

                                text: "Choose how Xavion should phrase its replies."

                                color: Theme.grey1
                                font.family: Theme.fontMain
                                font.pixelSize: 10

                                wrapMode: Text.Wrap
                            }

                            Flow {
                                width: parent.width
                                spacing: 8

                                Repeater {
                                    model: service.toneOptions.length

                                    Rectangle {
                                        id: toneOption

                                        required property int index

                                        readonly property var option:
                                            service.toneOptions[index]

                                        readonly property bool selected:
                                            service.toneMode
                                            === option.value

                                        width:
                                            toneLabel.implicitWidth + 24

                                        height: 32
                                        radius: height / 2

                                        color:
                                            selected
                                            ? Qt.alpha(
                                                service.gradientMid,
                                                0.20
                                            )
                                            : (
                                                toneMouse.containsMouse
                                                ? Qt.alpha(
                                                    Theme.white,
                                                    0.09
                                                )
                                                : Qt.alpha(
                                                    Theme.white,
                                                    0.045
                                                )
                                            )

                                        border.width: 1

                                        border.color:
                                            selected
                                            ? Qt.alpha(
                                                service.gradientMid,
                                                0.72
                                            )
                                            : Qt.alpha(
                                                Theme.white,
                                                0.10
                                            )

                                        Text {
                                            id: toneLabel

                                            anchors.centerIn: parent

                                            text: toneOption.option.label

                                            color:
                                                toneOption.selected
                                                ? Theme.white
                                                : Theme.grey1

                                            font.family: Theme.fontMain
                                            font.pixelSize: 10
                                            font.bold:
                                                toneOption.selected
                                        }

                                        MouseArea {
                                            id: toneMouse

                                            anchors.fill: parent

                                            hoverEnabled: true
                                            cursorShape:
                                                Qt.PointingHandCursor

                                            onClicked:
                                                service.setTone(
                                                    toneOption.option.value
                                                )
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 1

                            color:
                                Qt.alpha(
                                    Theme.white,
                                    0.08
                                )
                        }

                        // ====================================================
                        // MODEL
                        // ====================================================

                        Column {
                            width: parent.width
                            spacing: 10

                            Row {
                                width: parent.width
                                height: 24
                                spacing: 8

                                Text {
                                    anchors.verticalCenter:
                                        parent.verticalCenter

                                    text: "Model"

                                    color: Theme.white
                                    font.family: Theme.fontMain
                                    font.pixelSize: 12
                                    font.bold: true
                                }

                                Item {
                                    width:
                                        parent.width
                                        - refreshModelsButton.width
                                        - 50
                                    height: 1
                                }

                                Rectangle {
                                    id: refreshModelsButton

                                    width: 26
                                    height: 26
                                    radius: width / 2

                                    anchors.verticalCenter:
                                        parent.verticalCenter

                                    color:
                                        refreshModelsMouse.containsMouse
                                        ? Qt.alpha(
                                            Theme.white,
                                            0.10
                                        )
                                        : "transparent"

                                    border.width: 1
                                    border.color:
                                        Qt.alpha(
                                            Theme.white,
                                            0.10
                                        )

                                    Text {
                                        anchors.centerIn: parent

                                        text: "󰑐"

                                        color:
                                            service.backendReady
                                            ? (
                                                refreshModelsMouse.containsMouse
                                                ? Theme.white
                                                : Theme.grey1
                                            )
                                            : Qt.alpha(
                                                Theme.grey1,
                                                0.45
                                            )

                                        font.family: Theme.fontIcons
                                        font.pixelSize: 13
                                    }

                                    MouseArea {
                                        id: refreshModelsMouse

                                        anchors.fill: parent

                                        enabled:
                                            service.backendReady
                                            && !service.busy

                                        hoverEnabled: true

                                        cursorShape:
                                            enabled
                                            ? Qt.PointingHandCursor
                                            : Qt.ArrowCursor

                                        onClicked:
                                            service.refreshModels()
                                    }
                                }
                            }

                            Text {
                                width: parent.width

                                text:
                                    service.backendReady
                                    ? "Choose the local model used by Xavion."
                                    : "Models will be available when Xavion finishes starting."

                                color: Theme.grey1
                                font.family: Theme.fontMain
                                font.pixelSize: 10

                                wrapMode: Text.Wrap
                            }

                            Text {
                                visible:
                                    service.availableModels.length === 0

                                width: parent.width

                                text:
                                    service.backendReady
                                    ? "No local models found."
                                    : "Starting Xavion…"

                                color: Theme.grey1
                                font.family: Theme.fontMain
                                font.pixelSize: 10
                            }

                            Column {
                                width: parent.width
                                spacing: 7

                                Repeater {
                                    model:
                                        service.availableModels.length

                                    Rectangle {
                                        id: modelOption

                                        required property int index

                                        readonly property string modelName:
                                            String(
                                                service.availableModels[
                                                    index
                                                ]
                                            )

                                        readonly property bool active:
                                            modelName
                                            === service.activeModel

                                        readonly property bool selected:
                                            modelName
                                            === (
                                                service.selectedModel.length > 0
                                                ? service.selectedModel
                                                : service.activeModel
                                            )

                                        width: parent.width
                                        height: 40
                                        radius: 11

                                        color:
                                            selected
                                            ? Qt.alpha(
                                                service.gradientMid,
                                                0.16
                                            )
                                            : (
                                                modelMouse.containsMouse
                                                ? Qt.alpha(
                                                    Theme.white,
                                                    0.075
                                                )
                                                : Qt.alpha(
                                                    Theme.white,
                                                    0.035
                                                )
                                            )

                                        border.width: 1

                                        border.color:
                                            selected
                                            ? Qt.alpha(
                                                service.gradientMid,
                                                0.58
                                            )
                                            : Qt.alpha(
                                                Theme.white,
                                                0.09
                                            )

                                        Text {
                                            anchors {
                                                left: parent.left
                                                verticalCenter:
                                                    parent.verticalCenter
                                                leftMargin: 12
                                            }

                                            width:
                                                parent.width - 86

                                            text:
                                                modelOption.modelName

                                            color:
                                                modelOption.selected
                                                ? Theme.white
                                                : Theme.grey1

                                            font.family: Theme.fontMain
                                            font.pixelSize: 10
                                            font.bold:
                                                modelOption.selected

                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            anchors {
                                                right: parent.right
                                                verticalCenter:
                                                    parent.verticalCenter
                                                rightMargin: 12
                                            }

                                            text:
                                                modelOption.active
                                                ? "Active"
                                                : (
                                                    modelOption.selected
                                                    ? "Selected"
                                                    : ""
                                                )

                                            color:
                                                modelOption.active
                                                ? Theme.green
                                                : service.gradientMid

                                            font.family: Theme.fontMain
                                            font.pixelSize: 9
                                        }

                                        MouseArea {
                                            id: modelMouse

                                            anchors.fill: parent

                                            enabled:
                                                service.backendReady
                                                && !service.busy

                                            hoverEnabled: true

                                            cursorShape:
                                                enabled
                                                ? Qt.PointingHandCursor
                                                : Qt.ArrowCursor

                                            onClicked: {
                                                if (
                                                    !modelOption.active
                                                    || !modelOption.selected
                                                ) {
                                                    service.setModel(
                                                        modelOption.modelName
                                                    )
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Small scrollbar only when the settings page is taller
                    // than the available panel height.
                    Rectangle {
                        anchors {
                            right: parent.right
                            rightMargin: 1
                        }

                        width: 3

                        height:
                            Math.max(
                                24,
                                settingsFlick.height
                                * settingsFlick.visibleArea.heightRatio
                            )

                        y:
                            settingsFlick.visibleArea.yPosition
                            * (settingsFlick.height - height)

                        radius: width / 2

                        visible:
                            settingsFlick.contentHeight
                            > settingsFlick.height

                        color:
                            Qt.alpha(
                                Theme.white,
                                0.20
                            )
                    }
                }
            }

            // ============================================================
            // INPUT
            // ============================================================

            Rectangle {
                visible: !panel.settingsOpen
                Layout.fillWidth: true
                Layout.preferredHeight: 36

                radius: height / 2

                color: Qt.alpha(
                    Theme.bg1,
                    0.72
                )

                border.width: 1

                border.color:
                    input.activeFocus
                    ? Qt.alpha(Theme.white, 0.18)
                    : Qt.alpha(Theme.white, 0.10)

                Text {
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                        leftMargin: 14
                    }

                    visible: input.text.length === 0

                    text:
                        service.backendReady
                        ? (
                            service.busy
                            ? "Xavion is thinking…"
                            : "Ask Xavion..."
                        )
                        : "Starting Xavion…"

                    color: Theme.grey1

                    font.family: Theme.fontMain
                    font.pixelSize: 12
                }

                TextInput {
                    id: input

                    anchors {
                        left: parent.left
                        right: sendButton.left

                        top: parent.top
                        bottom: parent.bottom

                        leftMargin: 14
                        rightMargin: 8
                    }

                    enabled:
                        service.backendReady
                        && !service.busy

                    color: Theme.white

                    selectionColor:
                        Qt.alpha(
                            Theme.blue,
                            0.45
                        )

                    selectedTextColor:
                        Theme.white

                    font.family: Theme.fontMain
                    font.pixelSize: 12

                    verticalAlignment:
                        TextInput.AlignVCenter

                    clip: true

                    onAccepted:
                        panel.submitMessage()

                    Keys.onEscapePressed: function(event) {
                        panel.closePanel()
                        event.accepted = true
                    }
                }

                Item {
                    id: sendButton

                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        rightMargin: 4
                    }

                    width: 28
                    height: 28

                    Rectangle {
                        anchors.fill: parent

                        radius: width / 2

                        opacity:
                            service.backendReady
                            && !service.busy
                            && input.text.trim().length > 0
                            ? 1.0
                            : 0.34

                        gradient: Gradient {
                            orientation: Gradient.Horizontal

                            GradientStop {
                                position: 0.0
                                color: service.gradientStart
                            }

                            GradientStop {
                                position: 0.52
                                color: service.gradientMid
                            }

                            GradientStop {
                                position: 1.0
                                color: service.gradientEnd
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: 1

                        text: "󰁝"

                        color: Theme.white

                        font.family: Theme.fontIcons
                        font.pixelSize: 15
                    }

                    MouseArea {
                        id: sendMouse

                        anchors.fill: parent
                        hoverEnabled: true

                        cursorShape:
                            service.backendReady
                            && !service.busy
                            && input.text.trim().length > 0
                            ? Qt.PointingHandCursor
                            : Qt.ArrowCursor

                        onClicked:
                            panel.submitMessage()
                    }
                }
            }
        }
    }

    Connections {
        target: service

        function onStreamUpdated() {
            Qt.callLater(function() {
                messageList.positionViewAtEnd()
            })
        }

        function onBackendReadyChanged() {
            if (service.backendReady) {
                Qt.callLater(function() {
                    input.forceActiveFocus()
                })
            }
        }

        function onAwaitingFirstChunkChanged() {
            if (service.awaitingFirstChunk) {
                Qt.callLater(function() {
                    messageList.positionViewAtEnd()
                })
            }
        }
    }
}
