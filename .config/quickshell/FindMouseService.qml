import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

pragma Singleton

Singleton {
    id: service

    // ---------------------------------------------------------------------
    // Behaviour / appearance
    // ---------------------------------------------------------------------
    // Maximum delay between both Ctrl releases for them to count as a
    // double tap. PowerToys-like values around 350-450 ms feel natural.
    readonly property int doubleTapInterval: 420

    // Cursor tracking only runs while the spotlight is visible. Keeping this
    // reasonably low avoids hammering hyprctl while still making the halo
    // follow the pointer smoothly.
    readonly property int cursorTrackingInterval: 70

    // Spotlight geometry is expressed in logical pixels, so it behaves well
    // on mixed-DPI / scaled monitor setups.
    readonly property real spotlightInnerRadius: 82
    readonly property real spotlightOuterRadius: 155
    readonly property real ringDiameter: 154
    readonly property real dimOpacity: 0.76

    property bool active: false
    property bool pendingStart: false
    property bool cursorValid: false

    property real cursorX: 0
    property real cursorY: 0
    property real effectOpacity: 0
    property real ringScale: 1

    property double lastCtrlTapMs: 0

    // Called once for every modifier-only Hyprland global shortcut event.
    function registerCtrlTap(): void {
        const now = Date.now()
        const elapsed = now - lastCtrlTapMs

        if (lastCtrlTapMs > 0 && elapsed > 35 && elapsed <= doubleTapInterval) {
            lastCtrlTapMs = 0
            pendingStart = true
            requestCursorPosition()
            return
        }

        lastCtrlTapMs = now
    }

    function requestCursorPosition(): void {
        if (!cursorProcess.running)
            cursorProcess.running = true
    }

    function parseCursorPosition(output): bool {
        const text = String(output ?? "").trim()
        if (text.length === 0)
            return false

        // Current Hyprland JSON output: { "x": ..., "y": ... }
        try {
            const parsed = JSON.parse(text)
            const x = Number(parsed.x)
            const y = Number(parsed.y)

            if (Number.isFinite(x) && Number.isFinite(y)) {
                cursorX = x
                cursorY = y
                cursorValid = true
                return true
            }
        } catch (error) {
            // Fall through to the plain-text parser below. This keeps the
            // feature tolerant of older/different hyprctl output formats.
        }

        const match = text.match(/(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)/)
        if (!match)
            return false

        const x = Number(match[1])
        const y = Number(match[2])
        if (!Number.isFinite(x) || !Number.isFinite(y))
            return false

        cursorX = x
        cursorY = y
        cursorValid = true
        return true
    }

    function handleCursorOutput(output): void {
        const parsed = parseCursorPosition(output)

        if (!parsed) {
            if (pendingStart) {
                pendingStart = false
                console.warn("FindMouseService: could not read Hyprland cursor position")
            }
            return
        }

        if (pendingStart) {
            pendingStart = false
            startEffect()
        }
    }

    function startEffect(): void {
        if (!cursorValid)
            return

        effectAnimation.stop()
        cursorTrackingTimer.stop()

        // The initial cursor query happens while active == false, so each
        // monitor's smoothed local coordinates jump to the correct position
        // before the overlay is made visible. Subsequent cursor updates are
        // animated while the effect is active.
        effectOpacity = 0
        ringScale = 1.28
        active = true

        cursorTrackingTimer.start()
        effectAnimation.start()
    }

    function stopEffect(): void {
        effectAnimation.stop()
        cursorTrackingTimer.stop()
        effectOpacity = 0
        ringScale = 1
        active = false
        pendingStart = false
    }

    // Native Hyprland global shortcut. Hyprland binds both left and right Ctrl
    // releases to this shortcut; the double-tap recognition itself lives here
    // so there is no process spawn for each Ctrl press.
    GlobalShortcut {
        name: "find_mouse"
        description: "Find mouse spotlight (double Ctrl)"

        onPressed: service.registerCtrlTap()
    }

    // hyprctl exposes the cursor in global layout coordinates. We only poll it
    // while the effect is visible, never continuously in the background.
    Process {
        id: cursorProcess
        command: ["hyprctl", "-j", "cursorpos"]

        stdout: StdioCollector {
            onStreamFinished: service.handleCursorOutput(this.text)
        }
    }

    Timer {
        id: cursorTrackingTimer
        interval: service.cursorTrackingInterval
        repeat: true
        running: false
        onTriggered: service.requestCursorPosition()
    }

    // Quick PowerToys-like entrance, short hold, then a softer fade-out.
    SequentialAnimation {
        id: effectAnimation

        ParallelAnimation {
            NumberAnimation {
                target: service
                property: "effectOpacity"
                from: 0
                to: 1
                duration: 105
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                target: service
                property: "ringScale"
                from: 1.28
                to: 1
                duration: 230
                easing.type: Easing.OutCubic
            }
        }

        PauseAnimation {
            duration: 690
        }

        NumberAnimation {
            target: service
            property: "effectOpacity"
            from: 1
            to: 0
            duration: 390
            easing.type: Easing.InOutQuad
        }

        ScriptAction {
            script: {
                cursorTrackingTimer.stop()
                service.effectOpacity = 0
                service.ringScale = 1
                service.active = false
            }
        }
    }

    // One transparent, click-through overlay per connected monitor.
    // Quickshell automatically creates/removes these as outputs are hotplugged.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: overlay
            required property var modelData

            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(overlay.screen)

            readonly property real rawCursorX: service.cursorX - (monitor ? monitor.x : 0)
            readonly property real rawCursorY: service.cursorY - (monitor ? monitor.y : 0)

            // While inactive these jump immediately to the latest cursor
            // position. While visible they interpolate the 70 ms samples so the
            // spotlight looks continuous without high-frequency hyprctl spam.
            property real displayCursorX: rawCursorX
            property real displayCursorY: rawCursorY

            readonly property bool haloNearScreen:
                displayCursorX >= -service.spotlightOuterRadius &&
                displayCursorX <= width + service.spotlightOuterRadius &&
                displayCursorY >= -service.spotlightOuterRadius &&
                displayCursorY <= height + service.spotlightOuterRadius

            screen: modelData
            visible: service.active
            color: "transparent"
            focusable: false
            exclusionMode: ExclusionMode.Ignore

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            implicitWidth: screen.width
            implicitHeight: screen.height

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:find-mouse"

            // An empty input region means the overlay never steals clicks,
            // scrolling, or pointer movement from the application underneath.
            mask: Region { }

            Behavior on displayCursorX {
                enabled: service.active
                NumberAnimation {
                    duration: service.cursorTrackingInterval
                    easing.type: Easing.OutQuad
                }
            }

            Behavior on displayCursorY {
                enabled: service.active
                NumberAnimation {
                    duration: service.cursorTrackingInterval
                    easing.type: Easing.OutQuad
                }
            }

            onDisplayCursorXChanged: dimmer.requestPaint()
            onDisplayCursorYChanged: dimmer.requestPaint()
            onWidthChanged: dimmer.requestPaint()
            onHeightChanged: dimmer.requestPaint()
            onVisibleChanged: {
                if (visible)
                    dimmer.requestPaint()
            }

            // Darkens the complete output, then punches a feathered circular
            // hole through the alpha channel around the global cursor position.
            Canvas {
                id: dimmer
                anchors.fill: parent
                opacity: service.effectOpacity

                onPaint: {
                    const ctx = getContext("2d")
                    if (!ctx)
                        return

                    ctx.save()
                    ctx.globalCompositeOperation = "source-over"
                    ctx.clearRect(0, 0, width, height)

                    ctx.fillStyle = `rgba(0, 0, 0, ${service.dimOpacity})`
                    ctx.fillRect(0, 0, width, height)

                    const cx = overlay.displayCursorX
                    const cy = overlay.displayCursorY
                    const inner = service.spotlightInnerRadius
                    const outer = service.spotlightOuterRadius

                    // destination-out uses the source alpha as an eraser. The
                    // inner area is fully transparent and the outer edge fades
                    // smoothly back into the dimmed desktop.
                    ctx.globalCompositeOperation = "destination-out"
                    const gradient = ctx.createRadialGradient(cx, cy, 0, cx, cy, outer)
                    gradient.addColorStop(0, "rgba(0, 0, 0, 1)")
                    gradient.addColorStop(inner / outer, "rgba(0, 0, 0, 1)")
                    gradient.addColorStop(1, "rgba(0, 0, 0, 0)")

                    ctx.fillStyle = gradient
                    ctx.beginPath()
                    ctx.arc(cx, cy, outer, 0, Math.PI * 2, false)
                    ctx.fill()

                    ctx.restore()
                }
            }

            // Wide, low-opacity blue rim: gives the circle definition on both
            // dark and bright backgrounds without looking pasted on top.
            Rectangle {
                width: service.ringDiameter + 14
                height: width
                x: overlay.displayCursorX - width / 2
                y: overlay.displayCursorY - height / 2
                radius: width / 2
                visible: overlay.haloNearScreen
                color: "transparent"
                border.width: 7
                border.color: Qt.alpha(Theme.blue, 0.20)
                opacity: service.effectOpacity
                scale: service.ringScale
            }

            // Crisp PowerToys-style inner ring.
            Rectangle {
                width: service.ringDiameter
                height: width
                x: overlay.displayCursorX - width / 2
                y: overlay.displayCursorY - height / 2
                radius: width / 2
                visible: overlay.haloNearScreen
                color: "transparent"
                border.width: 3
                border.color: Qt.rgba(1, 1, 1, 0.96)
                opacity: service.effectOpacity
                scale: service.ringScale
            }
        }
    }

    // Manual IPC hooks are handy for testing the visual effect without having
    // to double-tap Ctrl every time while tweaking QML.
    IpcHandler {
        target: "findMouse"

        function trigger(): void {
            service.pendingStart = true
            service.requestCursorPosition()
        }

        function hide(): void {
            service.stopEffect()
        }
    }
}
