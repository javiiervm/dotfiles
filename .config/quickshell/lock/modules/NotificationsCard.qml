import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Io
import "." as Local
import "../../"

Local.Card {
    id: root
    implicitWidth: 260 * Theme.scale
    implicitHeight: 236 * Theme.scale

    // Recibe el ListModel de notificaciones de tu sistema
    property ListModel modelData

    Process { id: ncCommand }
    function execCmd(cmd) { ncCommand.command = ["bash", "-c", cmd]; ncCommand.running = true; }

    content: ColumnLayout {
        anchors.fill: parent
        spacing: 10 * Theme.scale

        // --- CABECERA ---
        RowLayout {
            Layout.fillWidth: true

            Text {
                property int count: root.modelData ? root.modelData.count : 0
                text: count + (count === 1 ? " notification" : " notifications")
                color: Qt.alpha(Theme.white, 0.8)
                font.family: Theme.fontMain
                font.pixelSize: 11 * Theme.scale
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            // Botón Clear All
            Rectangle {
                id: clearAllBtn
                width: 65 * Theme.scale
                height: 22 * Theme.scale
                radius: 6 * Theme.scale
                property bool hasNotifs: root.modelData && root.modelData.count > 0
                visible: hasNotifs
                color: clearMouse.containsMouse ? Qt.alpha(Theme.white, 0.2) : Qt.alpha(Theme.white, 0.1)

                Text {
                    anchors.centerIn: parent
                    text: "Clear All"
                    color: Theme.white
                    font.family: Theme.fontMain
                    font.pixelSize: 10 * Theme.scale
                    font.bold: true
                }

                MouseArea {
                    id: clearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: clearAllBtn.hasNotifs ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (clearAllBtn.hasNotifs) {
                            root.execCmd("echo 'CLEAR_ALL' > /tmp/qs_notif_cmd")
                        }
                    }
                }
            }
        }

        // --- CONTENIDO: LISTA O MENSAJE VACÍO ---
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Estado Sin Notificaciones
            Text {
                anchors.centerIn: parent
                text: "No new notifications"
                color: Qt.alpha(Theme.white, 0.4)
                font.family: Theme.fontMain
                font.pixelSize: 12 * Theme.scale
                visible: !root.modelData || root.modelData.count === 0
            }

            // Lista de Notificaciones
            ListView {
                anchors.fill: parent
                clip: true
                spacing: 8 * Theme.scale
                model: root.modelData
                visible: root.modelData && root.modelData.count > 0

                delegate: Rectangle {
                    width: ListView.view.width
                    height: 64 * Theme.scale
                    radius: 12 * Theme.scale

                    // Estilo según urgencia
                    color: model.urgency === 2 ? Qt.alpha(Theme.red, 0.15) : Qt.alpha(Theme.white, 0.05)
                    border.color: model.urgency === 2 ? Theme.red : Qt.alpha(Theme.white, 0.08)
                    border.width: model.urgency === 2 ? 2 : 1

                    // Acción principal al hacer clic
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        z: 0
                        onClicked: {
                            root.execCmd("echo 'ACTION|" + model.id + "|default' > /tmp/qs_notif_cmd")
                            root.execCmd("echo 'REMOVE|" + model.id + "' > /tmp/qs_notif_cmd")
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10 * Theme.scale
                        spacing: 10 * Theme.scale

                        // Avatar / Icono circular
                        Item {
                            Layout.preferredWidth: 32 * Theme.scale
                            Layout.preferredHeight: 32 * Theme.scale

                            Image {
                                id: notifImg
                                anchors.fill: parent
                                source: String(icon).startsWith("/") ? "file://" + icon : "image://icon/" + icon
                                fillMode: Image.PreserveAspectCrop
                                visible: false
                            }

                            Rectangle {
                                id: mask
                                anchors.fill: parent
                                radius: width / 2
                                visible: false
                            }

                            OpacityMask {
                                anchors.fill: parent
                                source: notifImg
                                maskSource: mask
                            }
                        }

                        // Textos Informativos
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2 * Theme.scale

                            Text {
                                text: app + (model.urgency === 2 ? " • CRITICAL" : "")
                                color: model.urgency === 2 ? Theme.red : Theme.blue
                                font.family: Theme.fontMain
                                font.pixelSize: 9 * Theme.scale
                                font.bold: true
                            }

                            Text {
                                text: title
                                color: Theme.white
                                font.family: Theme.fontMain
                                font.pixelSize: 11 * Theme.scale
                                font.bold: true
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Text {
                                text: body
                                color: Qt.alpha(Theme.white, 0.5)
                                font.family: Theme.fontMain
                                font.pixelSize: 10 * Theme.scale
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                maximumLineCount: 1
                            }
                        }

                        // Botón cerrar (X)
                        Item {
                            Layout.alignment: Qt.AlignTop | Qt.AlignRight
                            width: 18 * Theme.scale
                            height: 18 * Theme.scale
                            z: 1

                            Text {
                                anchors.centerIn: parent
                                text: "󰅖"
                                font.family: Theme.fontIcons
                                color: xMouse.containsMouse ? Theme.white : Qt.alpha(Theme.white, 0.5)
                                font.pixelSize: 12 * Theme.scale
                            }

                            MouseArea {
                                id: xMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.execCmd("echo 'REMOVE|" + model.id + "' > /tmp/qs_notif_cmd")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}