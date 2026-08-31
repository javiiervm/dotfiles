import QtQuick
import QtMultimedia
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: overlay

    implicitWidth: 184
    implicitHeight: 184
    color: "transparent"
    exclusiveZone: 0

    anchors {
        top: true
        left: true
    }

    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: WlrLayershell.None

    property real leftMargin: screen ? Math.max(24, screen.width - implicitWidth - 36) : 40
    property real topMargin: screen ? Math.max(70, screen.height - implicitHeight - 52) : 100
    property real dragStartLeft: 0
    property real dragStartTop: 0

    margins {
        left: Math.round(overlay.leftMargin)
        top: Math.round(overlay.topMargin)
    }

    function clampPosition() {
        if (!screen)
            return

        leftMargin = Math.max(8, Math.min(leftMargin, screen.width - implicitWidth - 8))
        topMargin = Math.max(8, Math.min(topMargin, screen.height - implicitHeight - 8))
    }

    onScreenChanged: clampPosition()

    mask: Region {
        item: cameraFrame
        radius: cameraFrame.radius
    }

    MediaDevices {
        id: mediaDevices
    }

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
        anchors.fill: parent

        readonly property real borderSize: 3
        readonly property real innerMargin: borderSize
        property real radius: width / 2

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
            anchors.margins: cameraFrame.innerMargin
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

                Column {
                    anchors.centerIn: parent
                    spacing: 5

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Camera unavailable"
                        color: Qt.rgba(1, 1, 1, 0.72)
                        font.pixelSize: 11
                    }
                }
            }
        }

        // Tiny inner highlight so the circular edge remains readable over both
        // bright and dark content without putting controls into the recording.
        Rectangle {
            anchors.fill: parent
            anchors.margins: cameraFrame.borderSize
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.20)
        }

        DragHandler {
            id: dragHandler
            target: null

            onActiveChanged: {
                if (active) {
                    overlay.dragStartLeft = overlay.leftMargin
                    overlay.dragStartTop = overlay.topMargin
                } else {
                    overlay.clampPosition()
                }
            }

            onActiveTranslationChanged: {
                if (!active || !overlay.screen)
                    return

                overlay.leftMargin = Math.max(
                    8,
                    Math.min(
                        overlay.dragStartLeft + activeTranslation.x,
                        overlay.screen.width - overlay.implicitWidth - 8
                    )
                )
                overlay.topMargin = Math.max(
                    8,
                    Math.min(
                        overlay.dragStartTop + activeTranslation.y,
                        overlay.screen.height - overlay.implicitHeight - 8
                    )
                )
            }
        }
    }
}
