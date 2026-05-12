import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import ".."

Item {
    property bool showContainer: true
    Layout.preferredHeight: parent.height
    Layout.preferredWidth: 160

    Item {
        id: wsContainer
        width: 160
        height: 24
        anchors.centerIn: parent

        Row {
            spacing: 10
            anchors.fill: parent

            Repeater {
                model: [1, 2, 3, 4, 5]

                Rectangle {
                    id: wsRect
                    property int wsId: modelData
                    property bool isHovered: mouseArea.containsMouse

                    property bool hasWindows: {
                        var values = Hyprland.workspaces.values;
                        for (var i = 0; i < values.length; i++) {
                            if (values[i].id == wsId) return true;
                        }
                        return false;
                    }

                    // Versión retardada: se activa con delay, se desactiva al instante
                    property bool hasWindowsDelayed: false

                    onHasWindowsChanged: {
                        if (hasWindows) {
                            dotTimer.restart()
                        } else {
                            dotTimer.stop()
                            hasWindowsDelayed = false
                        }
                    }

                    Timer {
                        id: dotTimer
                        interval: 600   // ms de retardo para fantasma → punto
                        onTriggered: wsRect.hasWindowsDelayed = true
                    }

                    width: 24
                    height: 24
                    radius: 12
                    color: isHovered ? "#22ffffff" : "transparent"
                    Behavior on color { ColorAnimation { duration: 250 } }
                    opacity: {
                        var dist = Math.abs((pacman.x + 16) - (index * 34 + 12));
                        return dist < 22 ? Math.pow(dist / 22, 0.55) : 1.0;
                    }

                    Text {
                        id: wsIcon
                        anchors.centerIn: parent
                        text: wsRect.hasWindowsDelayed ? "󰧞" : "󰊠"
                        color: Theme.fg
                        font.family: Theme.fontIcons
                        font.pixelSize: 16
                        Behavior on color { ColorAnimation { duration: 300 } }
                    }

                    MouseArea {
                        id: mouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Hyprland.dispatch("workspace " + wsRect.wsId)
                    }
                }
            }
        }

        Rectangle {
            id: pacman
            width: 32
            height: 24
            radius: 12
            color: "#ffffff"
            z: 10
            y: 0

            property int activeIndex: {
                if (!Hyprland.focusedMonitor) return 0;
                return Math.max(0, Math.min(4,
                    Hyprland.focusedMonitor.activeWorkspace.id - 1));
            }

            x: activeIndex * 34 - 4

            Behavior on x {
                NumberAnimation {
                    duration: 250
                    easing.type: Easing.OutQuint
                }
            }

            Text {
                anchors.centerIn: parent
                text: "󰮯"
                color: "#0a0a0a"
                font.family: Theme.fontIcons
                font.pixelSize: 16
            }
        }
    }
}