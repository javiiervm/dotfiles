import QtQuick
import QtQuick.Layouts
import ".."

GlassSurface {
    id: menuRoot

    // Propiedades de estado expuestas
    property string title: ""
    property string info1: ""
    property string info2: ""
    property color accent: Theme.white
    property bool isOpen: false

    width: 200
    height: 90
    glassRadius: 12

    // Cliping para evitar que los hijos se desborden durante las animaciones de escala/tamaño
    clip: true

    // --- ANIMACIONES DE APERTURA / CIERRE ---
    // 1. Opacidad con curva elástica suave
    opacity: isOpen ? 1.0 : 0.0
    Behavior on opacity {
        NumberAnimation {
            duration: 220
            easing.type: Easing.OutCubic
        }
    }

    // 2. Desplazamiento vertical (Slide Down/Up) y Escala
    transform: [
        Translate {
            id: menuTranslate
            y: menuRoot.isOpen ? 0 : -12
            Behavior on y {
                NumberAnimation {
                    duration: 250
                    easing.type: Easing.OutBack // Efecto "bounce" sutil al desplegar
                }
            }
        },
        Scale {
            id: menuScale
            origin.x: menuRoot.width / 2
            origin.y: 0
            xScale: menuRoot.isOpen ? 1.0 : 0.92
            yScale: menuRoot.isOpen ? 1.0 : 0.92
            Behavior on xScale { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
            Behavior on yScale { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
        }
    ]

    // --- CONTENIDO E INTERACTIVIDAD CON HOVER ---
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 6

        // Header del menú
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                width: 8
                height: 8
                radius: 4
                color: menuRoot.accent
            }

            Text {
                text: menuRoot.title
                color: Theme.white
                font.family: Theme.fontMain
                font.pixelSize: 12
                font.bold: true
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Qt.alpha(Theme.white, 0.1)
        }

        // Elementos de información con Hover semitransparente
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            // Fila 1 con hover interactivo glass
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 22
                radius: 6
                color: itemHover1.containsMouse ? Qt.alpha(Theme.white, 0.10) : "transparent"
                Behavior on color { ColorAnimation { duration: 150 } }

                MouseArea {
                    id: itemHover1
                    anchors.fill: parent
                    hoverEnabled: true
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    text: menuRoot.info1
                    color: Theme.white
                    font.family: Theme.fontMain
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            // Fila 2 con hover interactivo glass
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 20
                radius: 6
                color: itemHover2.containsMouse ? Qt.alpha(Theme.white, 0.10) : "transparent"
                Behavior on color { ColorAnimation { duration: 150 } }

                MouseArea {
                    id: itemHover2
                    anchors.fill: parent
                    hoverEnabled: true
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    text: menuRoot.info2
                    color: Theme.grey1
                    font.family: Theme.fontMain
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }
        }
    }
}