import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: altTabWindow
    screen: Quickshell.screens[0]

    // La ventana ocupa exactamente la tarjeta.
    implicitWidth: containerCard.width
    implicitHeight: containerCard.height

    exclusiveZone: 0
    color: "transparent"

    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.namespace: "quickshell:alttab"

    visible: rootRef ? rootRef.isAltTabVisible : false

    property var rootRef: null
    property var windowList: rootRef ? rootRef.altTabList : []
    property int selectedIndex: rootRef ? rootRef.altTabCurrentIndex : 0

    // -----------------------------------------------------------------
    // Geometry
    // -----------------------------------------------------------------
    readonly property real itemSize: 72
    readonly property real itemSpacing: 14
    readonly property real horizontalPadding: 28
    readonly property real topPadding: 22
    readonly property real bottomPadding: 18

    readonly property real rowNaturalWidth: {
        const count = Math.max(0, windowList.length)
        if (count === 0)
            return 0
        return count * itemSize + Math.max(0, count - 1) * itemSpacing
    }

    // El título NO participa en el cálculo del ancho.
    // Así un título largo jamás deforma la tarjeta.
    readonly property real desiredCardWidth:
        Math.max(330, rowNaturalWidth + horizontalPadding * 2)

    readonly property real maxCardWidth:
        Math.max(330, Math.min(760, (screen ? screen.width : 1920) - 80))

    readonly property real cardWidth:
        Math.min(desiredCardWidth, maxCardWidth)

    readonly property real cardHeight: 148

    // -----------------------------------------------------------------
    // Liquid Glass blur
    // -----------------------------------------------------------------
    BackgroundEffect.blurRegion: Glass.blurEnabled ? altTabBlurRegion : null

    Region {
        id: altTabBlurRegion
        x: 0
        y: 0
        width: Math.round(containerCard.width)
        height: Math.round(containerCard.height)
        radius: Math.round(containerCard.radius)
    }

    // -----------------------------------------------------------------
    // Main card
    // -----------------------------------------------------------------
    GlassSurface {
        id: containerCard

        width: altTabWindow.cardWidth
        height: altTabWindow.cardHeight

        glassRadius: 26
        showBorder: true
        showHighlight: true
        clip: true

        // -------------------------------------------------------------
        // Icon strip
        // -------------------------------------------------------------
        Item {
            id: stripViewport

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                leftMargin: altTabWindow.horizontalPadding
                rightMargin: altTabWindow.horizontalPadding
                topMargin: altTabWindow.topPadding
            }

            height: 78
            clip: true

            Row {
                id: itemsRow

                anchors {
                    horizontalCenter: parent.horizontalCenter
                    verticalCenter: parent.verticalCenter
                }

                spacing: altTabWindow.itemSpacing

                Repeater {
                    model: altTabWindow.windowList

                    Rectangle {
                        width: altTabWindow.itemSize
                        height: altTabWindow.itemSize
                        radius: 18

                        property bool isSelected:
                            index === altTabWindow.selectedIndex

                        color: isSelected
                            ? Qt.alpha(Theme.white, 0.16)
                            : Qt.alpha(Theme.white, 0.045)

                        border.color: isSelected
                            ? Qt.alpha(Theme.white, 0.92)
                            : Qt.alpha(Theme.white, Glass.borderOpacity * 0.55)

                        border.width: isSelected ? 2 : Glass.borderWidth

                        scale: isSelected ? 1.07 : 1.0

                        Behavior on scale {
                            NumberAnimation {
                                duration: 110
                                easing.type: Easing.OutCubic
                            }
                        }

                        Behavior on color {
                            ColorAnimation {
                                duration: 100
                            }
                        }

                        Behavior on border.color {
                            ColorAnimation {
                                duration: 100
                            }
                        }

                        // Suave brillo interior del item seleccionado.
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: Math.max(0, parent.radius - 2)
                            visible: parent.isSelected
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.alpha(Theme.white, 0.18)
                        }

                        Item {
                            anchors.centerIn: parent
                            width: 44
                            height: 44

                            Image {
                                id: appIcon

                                anchors.fill: parent

                                source: modelData.icon
                                    ? (modelData.icon.startsWith("/")
                                        ? "file://" + modelData.icon
                                        : "image://icon/" + modelData.icon)
                                    : ""

                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                mipmap: true
                                visible: status === Image.Ready
                            }

                            Text {
                                anchors.centerIn: parent

                                visible: appIcon.status !== Image.Ready

                                text: modelData.class
                                    ? modelData.class.substring(0, 1).toUpperCase()
                                    : "🗔"

                                font.family: Theme.fontIcons
                                font.pixelSize: 26
                                color: Theme.white
                            }
                        }

                        // Indicador de ventana minimizada.
                        Rectangle {
                            visible: modelData.minimized === true

                            anchors {
                                horizontalCenter: parent.horizontalCenter
                                bottom: parent.bottom
                                bottomMargin: 5
                            }

                            width: 5
                            height: 5
                            radius: 2.5

                            color: Theme.blue
                        }
                    }
                }
            }
        }

        // -------------------------------------------------------------
        // Current window title
        // -------------------------------------------------------------
        Text {
            id: selectedTitle

            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom

                leftMargin: 24
                rightMargin: 24
                bottomMargin: altTabWindow.bottomPadding
            }

            height: 22

            text: {
                if (altTabWindow.windowList.length > 0
                        && altTabWindow.selectedIndex >= 0
                        && altTabWindow.selectedIndex < altTabWindow.windowList.length) {
                    const item =
                        altTabWindow.windowList[altTabWindow.selectedIndex]
                    return item.title || item.class || "Aplicación"
                }

                return ""
            }

            color: Theme.white

            font.family: Theme.fontMain
            font.bold: true
            font.pixelSize: 13

            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter

            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }
}
