import QtQuick
import QtMultimedia
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: overlay

    property string monitorName: String(Quickshell.env("QS_SCREENREC_CAMERA_OUTPUT") || "")
    readonly property var targetScreen: {
        var screens = Quickshell.screens
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === monitorName)
                return screens[i]
        }
        return screens.length > 0 ? screens[0] : null
    }
    screen: targetScreen

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    exclusiveZone: -1
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: WlrLayershell.None

    readonly property real edgeMargin: 24
    readonly property real topSafeMargin: 52
    readonly property real minBubbleSize: 112
    readonly property real maxBubbleSize: 320
    property real preferredSize: 184
    readonly property real bubbleSize: Math.max(1, Math.min(
        preferredSize, Math.max(1, width - 2 * edgeMargin),
        Math.max(1, height - topSafeMargin - edgeMargin)))

    // Desired coordinates are local to the active monitor. NaN means the
    // default bottom-right position. The actual geometry is always clamped.
    property real desiredX: NaN
    property real desiredY: NaN
    property real releaseOffsetX: 0
    property real releaseOffsetY: 0

    function clamp(value, minimum, maximum) {
        return Math.max(minimum, Math.min(value, Math.max(minimum, maximum)))
    }

    function originFor(s) {
        var monitor = Hyprland.monitorFor(s)
        return monitor ? Qt.point(monitor.x, monitor.y) : Qt.point(s.x, s.y)
    }

    function moveToCursor(globalX, globalY) {
        var screens = Quickshell.screens
        for (var i = 0; i < screens.length; ++i) {
            var s = screens[i]
            var origin = originFor(s)
            if (globalX >= origin.x && globalX < origin.x + s.width
                    && globalY >= origin.y && globalY < origin.y + s.height) {
                var x = globalX - origin.x - releaseOffsetX
                var y = globalY - origin.y - releaseOffsetY
                monitorName = s.name
                desiredX = x
                desiredY = y
                return
            }
        }
    }

    // Right-click is a direct alternative to dragging across displays.
    function nextMonitor() {
        var screens = Quickshell.screens
        if (screens.length < 2)
            return
        var index = -1
        for (var i = 0; i < screens.length; ++i) {
            if (targetScreen && screens[i].name === targetScreen.name) {
                index = i
                break
            }
        }
        monitorName = screens[(index + 1) % screens.length].name
        desiredX = NaN
        desiredY = NaN
    }

    function resizeBubble(steps) {
        if (!steps)
            return
        var centerX = cameraFrame.x + cameraFrame.width / 2
        var centerY = cameraFrame.y + cameraFrame.height / 2
        preferredSize = clamp(preferredSize + steps * 16, minBubbleSize, maxBubbleSize)
        desiredX = centerX - bubbleSize / 2
        desiredY = centerY - bubbleSize / 2
    }

    // One cursor query on mouse release, no periodic polling. Hyprland reports
    // global coordinates even when the pointer has left this layer surface.
    Process {
        id: releaseCursor
        command: ["hyprctl", "cursorpos", "-j"]
        property string output: ""
        stdout: SplitParser {
            onRead: function(line) { releaseCursor.output += line }
        }
        onExited: function(exitCode) {
            if (exitCode !== 0)
                return
            try {
                var p = JSON.parse(output)
                if (typeof p.x === "number" && typeof p.y === "number")
                    overlay.moveToCursor(p.x, p.y)
            } catch (e) {
                console.warn("CameraOverlay: cursor position:", e)
            }
        }
    }

    // Only the circle accepts input. Everything outside remains click-through.
    mask: Region {
        item: cameraFrame
        radius: cameraFrame.width / 2
    }

    MediaDevices { id: mediaDevices }
    Camera {
        id: camera
        cameraDevice: mediaDevices.defaultVideoInput
        active: mediaDevices.videoInputs.length > 0
    }
    CaptureSession {
        camera: camera
        videoOutput: rawVideo
    }

    Item {
        id: cameraFrame
        width: overlay.bubbleSize
        height: width
        readonly property real borderSize: 3

        x: overlay.clamp(isNaN(overlay.desiredX) ? overlay.width - width - 36 : overlay.desiredX,
                         overlay.edgeMargin, overlay.width - width - overlay.edgeMargin)
        y: overlay.clamp(isNaN(overlay.desiredY) ? overlay.height - height - 52 : overlay.desiredY,
                         overlay.topSafeMargin, overlay.height - height - overlay.edgeMargin)

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Qt.rgba(0.04, 0.04, 0.05, 0.96)
            border.width: cameraFrame.borderSize
            border.color: Qt.rgba(1, 1, 1, 0.82)
        }

        Item {
            id: videoArea
            anchors.fill: parent
            anchors.margins: cameraFrame.borderSize
            layer.enabled: true
            layer.smooth: true
            layer.effect: OpacityMask {
                cached: false
                maskSource: Rectangle {
                    width: videoArea.width
                    height: videoArea.height
                    radius: width / 2
                    color: "white"
                }
            }
            VideoOutput {
                id: rawVideo
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectCrop
                transform: Scale {
                    origin.x: rawVideo.width / 2
                    origin.y: rawVideo.height / 2
                    xScale: -1
                    yScale: 1
                }
            }
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Qt.rgba(0.04, 0.04, 0.05, 0.94)
                visible: mediaDevices.videoInputs.length === 0
                Text {
                    anchors.centerIn: parent
                    width: parent.width - 24
                    text: "Camera unavailable"
                    color: Qt.rgba(1, 1, 1, 0.72)
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: cameraFrame.borderSize
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.20)
        }

        MouseArea {
            id: dragArea
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            cursorShape: pressedButtons & Qt.LeftButton ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            preventStealing: true

            property real offsetX: 0
            property real offsetY: 0
            property real pressX: 0
            property real pressY: 0
            property bool moved: false

            onPressed: function(mouse) {
                if (mouse.button !== Qt.LeftButton)
                    return
                offsetX = mouse.x
                offsetY = mouse.y
                var p = dragArea.mapToItem(overlay.contentItem, mouse.x, mouse.y)
                pressX = p.x
                pressY = p.y
                moved = false
                mouse.accepted = true
            }
            onPositionChanged: function(mouse) {
                if (!(pressedButtons & Qt.LeftButton))
                    return
                var p = dragArea.mapToItem(overlay.contentItem, mouse.x, mouse.y)
                if (Math.abs(p.x - pressX) > 3 || Math.abs(p.y - pressY) > 3)
                    moved = true
                if (moved) {
                    overlay.desiredX = p.x - offsetX
                    overlay.desiredY = p.y - offsetY
                }
            }
            onReleased: function(mouse) {
                if (mouse.button !== Qt.LeftButton || !moved)
                    return
                // Wait until release before switching the layer-shell window;
                // changing outputs mid-drag could break Wayland's pointer grab.
                overlay.releaseOffsetX = offsetX
                overlay.releaseOffsetY = offsetY
                if (!releaseCursor.running) {
                    releaseCursor.output = ""
                    releaseCursor.running = true
                }
            }
            onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton)
                    overlay.nextMonitor()
            }
            onWheel: function(wheel) {
                if (pressedButtons & Qt.LeftButton) {
                    wheel.accepted = true
                    return
                }
                var delta = wheel.angleDelta.y
                if (delta === 0 && wheel.pixelDelta.y !== 0)
                    delta = wheel.pixelDelta.y > 0 ? 120 : -120
                if (delta !== 0) {
                    var steps = delta > 0 ? Math.max(1, Math.round(delta / 120)) : Math.min(-1, Math.round(delta / 120))
                    overlay.resizeBubble(steps)
                }
                wheel.accepted = true
            }
        }
    }
}
