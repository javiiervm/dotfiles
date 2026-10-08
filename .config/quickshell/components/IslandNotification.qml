import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import ".."

// Transient desktop notifications presented in the same top-centre slot as
// the Dynamic Island. The window stays mapped all the time, but has an empty
// input region while inactive. This avoids remapping glitches when the island
// hands control back to the normal clock.
PanelWindow {
    id: notificationIsland

    property int topMargin: -38

    readonly property bool notificationActive: presentationActive
    readonly property int notificationCount: notifications.length

    property bool presentationActive: false
    property bool cardOpen: false
    property var notifications: []
    property int currentIndex: 0

    property int currentId: -1
    property string appName: ""
    property string titleText: ""
    property string bodyText: ""
    property string iconName: "dialog-information"
    property int urgency: 1

    // Animation state used when cycling between notifications.
    property real contentOffsetX: 0
    property real contentOpacity: 0

    // Smooth touchpads often send several tiny wheel deltas instead of one
    // classic +/-120 mouse-wheel step. Accumulate them so both mouse wheels
    // and touchpads can rotate the notification carousel reliably.
    property real wheelAccumulator: 0

    // During the collapse animation the real Dynamic Island stays hidden.
    // We briefly draw the clock inside this same surface, then atomically hand
    // the slot back to DynamicIsland when the animation has fully finished.
    property bool showClosingClock: false
    property string closingClockText: ""

    readonly property int collapsedWidth: 120
    readonly property int collapsedHeight: 32
    readonly property int notificationWidth: 400
    readonly property int notificationHeight: 88

    signal removeManyRequested(var notificationIds)

    anchors {
        top: true
    }

    margins {
        top: notificationIsland.topMargin
    }

    WlrLayershell.layer: WlrLayershell.Overlay
    exclusiveZone: 0
    color: "transparent"

    // Keep this PanelWindow mapped. Only the inner GlassSurface is shown while
    // a transient notification is active.
    implicitWidth: 480
    implicitHeight: 132
    visible: true

    BackgroundEffect.blurRegion: Glass.blurEnabled && notificationIsland.presentationActive
                                 ? notificationBlurRegion
                                 : null

    Region {
        id: notificationBlurRegion
        item: visualBg
        radius: visualBg.glassRadius
    }

    Region {
        id: notificationInputRegion
        item: visualBg
        radius: visualBg.glassRadius
    }

    Region {
        id: emptyInputRegion
    }

    mask: notificationIsland.presentationActive
          ? notificationInputRegion
          : emptyInputRegion

    function cleanString(value) {
        if (value === undefined || value === null)
            return ""
        return String(value)
    }

    function normalizeNotification(notification) {
        var parsedId = Number(notification && notification.id)
        if (isNaN(parsedId))
            parsedId = -1

        var parsedUrgency = Number(notification && notification.urgency)
        if (isNaN(parsedUrgency))
            parsedUrgency = 1

        var parsedIcon = cleanString(notification && notification.icon)
        if (parsedIcon === "")
            parsedIcon = "dialog-information"

        return {
            "id": parsedId,
            "app": cleanString(notification && notification.app),
            "title": cleanString(notification && notification.title),
            "body": cleanString(notification && notification.body),
            "icon": parsedIcon,
            "urgency": parsedUrgency
        }
    }

    function applyCurrent() {
        if (notifications.length === 0) {
            currentId = -1
            appName = ""
            titleText = ""
            bodyText = ""
            iconName = "dialog-information"
            urgency = 1
            currentIndex = 0
            return
        }

        currentIndex = Math.max(0, Math.min(currentIndex, notifications.length - 1))
        var item = notifications[currentIndex]

        currentId = item.id
        appName = item.app !== "" ? item.app : "Notification"
        titleText = item.title
        bodyText = item.body
        iconName = item.icon
        urgency = item.urgency
    }

    function revealContent(direction) {
        contentRevealTimer.stop()
        contentOffsetX = direction >= 0 ? 18 : -18
        contentOpacity = 0
        contentRevealTimer.restart()
    }

    function resetWheelGesture() {
        wheelAccumulator = 0
    }

    function handleWheel(wheel) {
        if (!presentationActive || !cardOpen || notificationCount <= 1)
            return

        // Prefer angleDelta when available (classic wheel and many touchpads),
        // otherwise fall back to pixelDelta used by high-resolution touchpads.
        var dx = Number(wheel.angleDelta.x)
        var dy = Number(wheel.angleDelta.y)

        if (dx === 0 && dy === 0) {
            dx = Number(wheel.pixelDelta.x)
            dy = Number(wheel.pixelDelta.y)
        }

        var delta = Math.abs(dy) >= Math.abs(dx) ? dy : dx
        if (!delta)
            return

        wheel.accepted = true

        // Do not let the tail of the same physical gesture skip through two
        // notifications. Once a page changes, wait a short moment before the
        // next change is allowed.
        if (wheelCooldown.running)
            return

        // If the user reverses direction, discard the accumulated movement so
        // the carousel follows the new gesture immediately.
        if (wheelAccumulator !== 0 && wheelAccumulator * delta < 0)
            wheelAccumulator = 0

        wheelAccumulator += delta
        wheelGestureReset.restart()

        // 40 works for both a single 120-unit mouse notch and several small
        // smooth touchpad events.
        if (wheelAccumulator <= -40) {
            wheelAccumulator = 0
            cycle(1)
            wheelCooldown.restart()
        } else if (wheelAccumulator >= 40) {
            wheelAccumulator = 0
            cycle(-1)
            wheelCooldown.restart()
        }
    }

    function enqueue(notification) {
        var item = normalizeNotification(notification)
        var updated = notifications.slice(0)

        // Replacements should update instead of creating a duplicate entry.
        for (var i = updated.length - 1; i >= 0; --i) {
            if (updated[i].id === item.id)
                updated.splice(i, 1)
        }

        // Newest notification lives at index 0, matching the old popup stack
        // where the most recent card appeared first.
        updated.unshift(item)
        notifications = updated
        currentIndex = 0
        applyCurrent()

        hideTimer.stop()
        closeTimer.stop()
        closeClockTimer.stop()
        showClosingClock = false
        wheelAccumulator = 0

        if (!presentationActive) {
            presentationActive = true
            cardOpen = false
            contentOpacity = 0
            openTimer.restart()
        } else {
            cardOpen = true
            revealContent(-1)
            hideTimer.restart()
        }
    }

    function cycle(step) {
        if (!presentationActive || notifications.length <= 1)
            return

        var next = (currentIndex + step + notifications.length) % notifications.length
        if (next === currentIndex)
            return

        currentIndex = next
        applyCurrent()
        revealContent(step)
        hideTimer.restart()
    }

    // Clicking the card only closes the transient presentation. The actual
    // notification history remains available in Notification Center.
    function dismissPresentation() {
        if (!presentationActive)
            return

        hideTimer.stop()
        openTimer.stop()
        contentRevealTimer.stop()
        wheelGestureReset.stop()
        wheelCooldown.stop()
        wheelAccumulator = 0

        closingClockText = new Date().toLocaleTimeString(Qt.locale("en_US"), "hh:mm A")
        showClosingClock = false
        closeClockTimer.restart()

        contentOpacity = 0
        cardOpen = false
        closeTimer.restart()
    }

    // Used when Notification Center opens. This does not clear history.
    function dismissAll() {
        dismissPresentation()
    }

    // The popup is transient UI, not the notification history. Its X only
    // closes this presentation: pending notifications remain in the shared
    // model and in the Dynamic Island's notifications tab.
    function clearAll() {
        dismissPresentation()
    }

    function finishPresentation() {
        closeClockTimer.stop()
        wheelGestureReset.stop()
        wheelCooldown.stop()
        showClosingClock = false
        wheelAccumulator = 0

        presentationActive = false
        cardOpen = false
        notifications = []
        currentIndex = 0
        contentOffsetX = 0
        contentOpacity = 0
        applyCurrent()
    }

    Timer {
        id: openTimer
        interval: 24
        repeat: false
        onTriggered: {
            if (!notificationIsland.presentationActive)
                return

            notificationIsland.cardOpen = true
            contentRevealTimer.restart()
            hideTimer.restart()
        }
    }

    Timer {
        id: contentRevealTimer
        interval: 105
        repeat: false
        onTriggered: {
            notificationIsland.contentOffsetX = 0
            notificationIsland.contentOpacity = 1
        }
    }

    Timer {
        id: hideTimer
        interval: 5000
        repeat: false
        onTriggered: notificationIsland.dismissPresentation()
    }

    Timer {
        id: wheelGestureReset
        interval: 180
        repeat: false
        onTriggered: notificationIsland.resetWheelGesture()
    }

    Timer {
        id: wheelCooldown
        interval: 240
        repeat: false
    }

    Timer {
        id: closeClockTimer
        interval: 155
        repeat: false
        onTriggered: {
            if (notificationIsland.presentationActive && !notificationIsland.cardOpen)
                notificationIsland.showClosingClock = true
        }
    }

    Timer {
        id: closeTimer
        interval: 320
        repeat: false
        onTriggered: notificationIsland.finishPresentation()
    }

    GlassSurface {
        id: visualBg

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter

        width: notificationIsland.cardOpen
               ? notificationIsland.notificationWidth
               : notificationIsland.collapsedWidth
        height: notificationIsland.cardOpen
                ? notificationIsland.notificationHeight
                : notificationIsland.collapsedHeight

        // Do not fade this surface after the collapse has finished: the real
        // Dynamic Island returns in the exact same frame. A post-collapse fade
        // would overlap both pills and make the clock look duplicated.
        opacity: notificationIsland.presentationActive ? 1 : 0
        visible: notificationIsland.presentationActive

        glassRadius: notificationIsland.cardOpen ? 18 : height / 2
        clip: true
        showHighlight: false

        glassTint: notificationIsland.urgency === 2 ? Theme.red : Glass.tint
        glassOpacity: notificationIsland.urgency === 2 ? 0.14 : Glass.opacity
        border.color: notificationIsland.urgency === 2
                      ? Qt.alpha(Theme.red, 0.75)
                      : Glass.borderColor
        border.width: notificationIsland.urgency === 2 ? 1.5 : Glass.borderWidth

        Behavior on width {
            NumberAnimation { duration: 300; easing.type: Easing.OutQuint }
        }
        Behavior on height {
            NumberAnimation { duration: 300; easing.type: Easing.OutQuint }
        }
        Behavior on glassRadius {
            NumberAnimation { duration: 300; easing.type: Easing.OutQuint }
        }

        MouseArea {
            id: cardMouse
            anchors.fill: parent
            enabled: notificationIsland.cardOpen
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton

            onEntered: hideTimer.stop()
            onExited: {
                if (notificationIsland.presentationActive)
                    hideTimer.restart()
            }

            onClicked: notificationIsland.dismissPresentation()

            onWheel: function(wheel) {
                notificationIsland.handleWheel(wheel)
            }
        }

        Item {
            id: notificationContent
            anchors.fill: parent
            anchors.leftMargin: 11
            anchors.rightMargin: 9
            anchors.topMargin: 9
            anchors.bottomMargin: 9

            visible: notificationIsland.presentationActive
                     && notificationIsland.cardOpen
            opacity: notificationIsland.contentOpacity
            x: notificationIsland.contentOffsetX

            Behavior on opacity {
                NumberAnimation { duration: 145; easing.type: Easing.OutCubic }
            }
            Behavior on x {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            RowLayout {
                anchors.fill: parent
                spacing: 10

                Item {
                    Layout.preferredWidth: 38
                    Layout.preferredHeight: 38
                    Layout.alignment: Qt.AlignVCenter

                    Image {
                        id: rawNotificationIcon
                        anchors.fill: parent
                        source: notificationIsland.iconName.startsWith("/")
                                ? "file://" + notificationIsland.iconName
                                : "image://icon/" + notificationIsland.iconName
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        mipmap: true
                        visible: false
                    }

                    Rectangle {
                        id: notificationIconMask
                        anchors.fill: parent
                        radius: 9
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
                        radius: 9
                        visible: rawNotificationIcon.status !== Image.Ready
                        color: Qt.alpha(Theme.white, 0.10)
                        border.color: Qt.alpha(Theme.white, 0.12)
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "󰂚"
                            color: notificationIsland.urgency === 2 ? Theme.red : Theme.white
                            font.family: Theme.fontIcons
                            font.pixelSize: 17
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 17
                        spacing: 7

                        Text {
                            text: notificationIsland.appName
                            color: notificationIsland.urgency === 2
                                   ? Theme.red
                                   : Qt.alpha(Theme.white, 0.68)
                            font.family: Theme.fontMain
                            font.pixelSize: 10
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            visible: notificationIsland.notificationCount > 1
                            Layout.preferredWidth: countText.implicitWidth + 12
                            Layout.preferredHeight: 16
                            radius: height / 2
                            color: Qt.alpha(Theme.white, 0.08)
                            border.color: Qt.alpha(Theme.white, 0.10)
                            border.width: 1

                            Text {
                                id: countText
                                anchors.centerIn: parent
                                text: (notificationIsland.currentIndex + 1)
                                      + "/"
                                      + notificationIsland.notificationCount
                                color: Qt.alpha(Theme.white, 0.62)
                                font.family: Theme.fontMain
                                font.pixelSize: 9
                                font.bold: true
                            }
                        }

                        Text {
                            text: "now"
                            color: Qt.alpha(Theme.white, 0.48)
                            font.family: Theme.fontMain
                            font.pixelSize: 10
                        }
                    }

                    Text {
                        text: notificationIsland.titleText
                        visible: text !== ""
                        color: Theme.white
                        font.family: Theme.fontMain
                        font.pixelSize: 12
                        font.bold: true
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        Layout.fillWidth: true
                        Layout.preferredHeight: 18
                        verticalAlignment: Text.AlignVCenter
                    }

                    Text {
                        text: notificationIsland.bodyText
                        visible: text !== ""
                        color: Qt.alpha(Theme.white, 0.72)
                        font.family: Theme.fontMain
                        font.pixelSize: 10
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        verticalAlignment: Text.AlignTop
                    }
                }

                Item {
                    Layout.preferredWidth: 21
                    Layout.preferredHeight: 21
                    Layout.alignment: Qt.AlignTop
                    z: 10

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: closeMouse.containsMouse
                               ? Qt.alpha(Theme.white, 0.13)
                               : "transparent"
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "󰅖"
                        color: closeMouse.containsMouse
                               ? Theme.white
                               : Qt.alpha(Theme.white, 0.55)
                        font.family: Theme.fontIcons
                        font.pixelSize: 12
                    }

                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: function(mouse) {
                            mouse.accepted = true
                            notificationIsland.dismissPresentation()
                        }
                    }
                }
            }
        }

        // During the second half of the close animation, morph the transient
        // surface into the same clock shown by the collapsed Dynamic Island.
        // The real island is still off-screen at this point, so only one clock
        // can ever be visible.
        Text {
            anchors.centerIn: parent
            visible: notificationIsland.presentationActive
                     && !notificationIsland.cardOpen
                     && notificationIsland.showClosingClock
            opacity: visible ? 1 : 0
            text: notificationIsland.closingClockText
            color: Theme.white
            font.family: Theme.fontMain
            font.pixelSize: 16
            font.bold: true
            z: 80

            Behavior on opacity {
                NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
            }
        }

        // Dedicated wheel layer above the visual content. It accepts no mouse
        // buttons, so close/click interactions below keep working, but wheel
        // and touchpad events cannot be swallowed by child items.
        MouseArea {
            anchors.fill: parent
            z: 90
            enabled: notificationIsland.cardOpen
            acceptedButtons: Qt.NoButton
            onWheel: function(wheel) {
                notificationIsland.handleWheel(wheel)
            }
        }
    }
}
