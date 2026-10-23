import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

Scope {
    id: frame

    property var targetScreen: null
    property bool fullscreen: false

    readonly property int edgeSize: 12
    readonly property int headerSize: targetScreen && targetScreen.name === "HDMI-A-1" ? 38 : 44
    readonly property int cornerRadius: 18
    readonly property color material: Glass.tint
    readonly property color innerBorder: Qt.alpha(Theme.blue, 0.28)

    // These three panels reserve real desktop space. The existing top bar
    // already reserves the top 44/38 pixels, so it must not be reserved twice.
    PanelWindow {
        screen: frame.targetScreen
        visible: !frame.fullscreen
        anchors { top: true; bottom: true; left: true }
        implicitWidth: frame.edgeSize
        exclusiveZone: frame.edgeSize
        color: "transparent"
        WlrLayershell.layer: WlrLayershell.Top
        mask: Region {}
    }

    PanelWindow {
        screen: frame.targetScreen
        visible: !frame.fullscreen
        anchors { top: true; bottom: true; right: true }
        implicitWidth: frame.edgeSize
        exclusiveZone: frame.edgeSize
        color: "transparent"
        WlrLayershell.layer: WlrLayershell.Top
        mask: Region {}
    }

    PanelWindow {
        screen: frame.targetScreen
        visible: !frame.fullscreen
        anchors { bottom: true; left: true; right: true }
        implicitHeight: frame.edgeSize
        exclusiveZone: frame.edgeSize
        color: "transparent"
        WlrLayershell.layer: WlrLayershell.Top
        mask: Region {}
    }

    // Purely visual. Empty input mask allows clicks to pass to applications.
    PanelWindow {
        id: frameSurface
        screen: frame.targetScreen
        visible: !frame.fullscreen
        anchors { top: true; right: true; bottom: true; left: true }
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayershell.Top
        mask: Region {}

        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: frame.headerSize
            color: frame.material
        }

        Rectangle {
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: frame.edgeSize
            color: frame.material
        }

        Rectangle {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: frame.edgeSize
            color: frame.material
        }

        Rectangle {
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: frame.edgeSize
            color: frame.material
        }

        // Fine inner contour, interrupted at the four rounded corners.
        Rectangle {
            x: frame.edgeSize + frame.cornerRadius
            y: frame.headerSize
            width: parent.width - 2 * (frame.edgeSize + frame.cornerRadius)
            height: 1
            color: frame.innerBorder
        }

        Rectangle {
            x: frame.edgeSize + frame.cornerRadius
            y: parent.height - frame.edgeSize - 1
            width: parent.width - 2 * (frame.edgeSize + frame.cornerRadius)
            height: 1
            color: frame.innerBorder
        }

        Rectangle {
            x: frame.edgeSize
            y: frame.headerSize + frame.cornerRadius
            width: 1
            height: parent.height - frame.headerSize - frame.edgeSize - 2 * frame.cornerRadius
            color: frame.innerBorder
        }

        Rectangle {
            x: parent.width - frame.edgeSize - 1
            y: frame.headerSize + frame.cornerRadius
            width: 1
            height: parent.height - frame.headerSize - frame.edgeSize - 2 * frame.cornerRadius
            color: frame.innerBorder
        }

        Repeater {
            model: 4

            Canvas {
                id: corner
                required property int index

                x: index % 2 === 0
                   ? frame.edgeSize
                   : frameSurface.width - frame.edgeSize - frame.cornerRadius
                y: index < 2
                   ? frame.headerSize
                   : frameSurface.height - frame.edgeSize - frame.cornerRadius
                width: frame.cornerRadius
                height: frame.cornerRadius

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.save()
                    if (index % 2 === 1) {
                        ctx.translate(width, 0)
                        ctx.scale(-1, 1)
                    }
                    if (index >= 2) {
                        ctx.translate(0, height)
                        ctx.scale(1, -1)
                    }

                    ctx.fillStyle = frame.material
                    ctx.beginPath()
                    ctx.moveTo(0, 0)
                    ctx.lineTo(width, 0)
                    ctx.quadraticCurveTo(0, 0, 0, height)
                    ctx.closePath()
                    ctx.fill()

                    ctx.strokeStyle = frame.innerBorder
                    ctx.lineWidth = 1
                    ctx.beginPath()
                    ctx.moveTo(width, 0)
                    ctx.quadraticCurveTo(0, 0, 0, height)
                    ctx.stroke()
                    ctx.restore()
                }

                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                Connections {
                    target: frame
                    function onMaterialChanged() { corner.requestPaint() }
                    function onInnerBorderChanged() { corner.requestPaint() }
                }
            }
        }
    }
}
