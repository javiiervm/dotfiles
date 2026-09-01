import QtQuick
import QtMultimedia
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: overlay

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

    readonly property real bubbleSize: 184
    readonly property real edgeMargin: 24
    readonly property real topSafeMargin: 52

    /*
     * IMPORTANT
     *
     * La PanelWindow no se mueve nunca.
     * Ocupa toda la pantalla y únicamente cameraFrame cambia de posición.
     *
     * La región de input se limita al círculo de la cámara para que todo
     * lo demás siga siendo completamente click-through.
     */
    mask: Region {
        item: cameraFrame
        radius: cameraFrame.width / 2
    }

    // ============================================================
    // CAMERA
    // ============================================================

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

    // ============================================================
    // CAMERA BUBBLE
    // ============================================================

    Item {
        id: cameraFrame

        width: overlay.bubbleSize
        height: overlay.bubbleSize

        /*
         * Posición inicial.
         *
         * No usamos anchors porque queremos modificar x/y libremente.
         */
        x: Math.max(
               overlay.edgeMargin,
               overlay.width - width - 36
           )

        y: Math.max(
               overlay.topSafeMargin,
               overlay.height - height - 52
           )

        readonly property real borderSize: 3

        /*
         * Clamp manual.
         *
         * Esto evita que la cámara pueda acabar parcialmente fuera
         * de la pantalla.
         */
        function clampPosition() {
            var maxX = Math.max(
                overlay.edgeMargin,
                overlay.width - width - overlay.edgeMargin
            )

            var maxY = Math.max(
                overlay.topSafeMargin,
                overlay.height - height - overlay.edgeMargin
            )

            x = Math.max(
                overlay.edgeMargin,
                Math.min(x, maxX)
            )

            y = Math.max(
                overlay.topSafeMargin,
                Math.min(y, maxY)
            )
        }

        /*
         * Si cambia la geometría del monitor, por ejemplo al conectar
         * o desconectar una pantalla, recolocamos la burbuja.
         */
        Connections {
            target: overlay

            function onWidthChanged() {
                if (!dragArea.pressed)
                    cameraFrame.clampPosition()
            }

            function onHeightChanged() {
                if (!dragArea.pressed)
                    cameraFrame.clampPosition()
            }
        }

        // ========================================================
        // OUTER FRAME
        // ========================================================

        Rectangle {
            anchors.fill: parent

            radius: width / 2

            color: Qt.rgba(
                       0.04,
                       0.04,
                       0.05,
                       0.96
                   )

            border.width: cameraFrame.borderSize
            border.color: Qt.rgba(
                              1,
                              1,
                              1,
                              0.82
                          )
        }

        // ========================================================
        // VIDEO
        // ========================================================

        Item {
            id: videoArea

            anchors.fill: parent
            anchors.margins: cameraFrame.borderSize

            /*
             * Recorte circular real del VideoOutput.
             */
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

                /*
                 * Mirror horizontal para que se comporte como una
                 * preview de webcam normal.
                 */
                transform: Scale {
                    origin.x: rawVideo.width / 2
                    origin.y: rawVideo.height / 2

                    xScale: -1
                    yScale: 1
                }
            }

            /*
             * Fallback si no existe ninguna cámara.
             */
            Rectangle {
                anchors.fill: parent

                radius: width / 2

                color: Qt.rgba(
                           0.04,
                           0.04,
                           0.05,
                           0.94
                       )

                visible: mediaDevices.videoInputs.length === 0

                Text {
                    anchors.centerIn: parent

                    width: parent.width - 24

                    text: "Camera unavailable"

                    color: Qt.rgba(
                               1,
                               1,
                               1,
                               0.72
                           )

                    font.pixelSize: 11

                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }
        }

        /*
         * Aro interior muy suave.
         */
        Rectangle {
            anchors.fill: parent
            anchors.margins: cameraFrame.borderSize

            radius: width / 2

            color: "transparent"

            border.width: 1
            border.color: Qt.rgba(
                              1,
                              1,
                              1,
                              0.20
                          )
        }

        // ========================================================
        // MANUAL DRAGGING
        // ========================================================

        MouseArea {
            id: dragArea

            anchors.fill: parent

            acceptedButtons: Qt.LeftButton

            hoverEnabled: true

            cursorShape:
                pressed
                    ? Qt.ClosedHandCursor
                    : Qt.OpenHandCursor

            /*
             * NO usamos:
             *
             *     drag.target: cameraFrame
             *
             * porque con una Region dinámica en layer-shell puede
             * perder el pointer grab.
             *
             * En su lugar almacenamos:
             *
             * - dónde estaba el cursor al pulsar
             * - dónde estaba la cámara al pulsar
             *
             * y calculamos el desplazamiento manualmente.
             */

            property real pressGlobalX: 0
            property real pressGlobalY: 0

            property real startFrameX: 0
            property real startFrameY: 0

            onPressed: function(mouse) {
                /*
                 * mapToItem(null, ...) nos proporciona la posición
                 * respecto al root de la ventana, cuyo sistema de
                 * coordenadas permanece fijo durante todo el drag.
                 */
                var globalPoint = dragArea.mapToItem(
                    overlay.contentItem,
                    mouse.x,
                    mouse.y
                )

                pressGlobalX = globalPoint.x
                pressGlobalY = globalPoint.y

                startFrameX = cameraFrame.x
                startFrameY = cameraFrame.y

                mouse.accepted = true
            }

            onPositionChanged: function(mouse) {
                if (!pressed)
                    return

                /*
                 * Como cameraFrame se mueve, mouse.x/mouse.y cambian
                 * respecto al propio MouseArea.
                 *
                 * Por eso convertimos SIEMPRE la posición actual al
                 * sistema fijo de overlay.contentItem.
                 */
                var globalPoint = dragArea.mapToItem(
                    overlay.contentItem,
                    mouse.x,
                    mouse.y
                )

                var deltaX =
                    globalPoint.x - pressGlobalX

                var deltaY =
                    globalPoint.y - pressGlobalY

                var targetX =
                    startFrameX + deltaX

                var targetY =
                    startFrameY + deltaY

                var maxX = Math.max(
                    overlay.edgeMargin,
                    overlay.width
                        - cameraFrame.width
                        - overlay.edgeMargin
                )

                var maxY = Math.max(
                    overlay.topSafeMargin,
                    overlay.height
                        - cameraFrame.height
                        - overlay.edgeMargin
                )

                cameraFrame.x = Math.max(
                    overlay.edgeMargin,
                    Math.min(
                        targetX,
                        maxX
                    )
                )

                cameraFrame.y = Math.max(
                    overlay.topSafeMargin,
                    Math.min(
                        targetY,
                        maxY
                    )
                )
            }

            onReleased: {
                cameraFrame.clampPosition()
            }

            onCanceled: {
                cameraFrame.clampPosition()
            }
        }
    }
}