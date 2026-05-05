import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import ".."

Item {
    property bool showContainer: true
    Layout.preferredHeight: parent.height
    Layout.preferredWidth: mainRow.implicitWidth 
    
    RowLayout {
        id: mainRow
        anchors.centerIn: parent
        spacing: 8

        Repeater {
            model: [1, 2, 3, 4, 5]
            Rectangle {
                property bool isActive: Hyprland.focusedMonitor && Hyprland.focusedMonitor.activeWorkspace.id === modelData
                property bool isHovered: mouseArea.containsMouse
                
                Layout.preferredWidth: (isActive || isHovered) ? 60 : 24
                Layout.preferredHeight: 24
                radius: 12
                color: isActive ? Theme.white : (isHovered ? "#33ffffff" : "#1Affffff")
                
                Behavior on Layout.preferredWidth { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }
                
                Text {
                    anchors.centerIn: parent
                    text: modelData.toString()
                    color: (isActive || isHovered) ? Theme.bg0 : Theme.fg
                    font.family: Theme.fontMain; font.pixelSize: 13; font.bold: true
                }

                MouseArea {
                    id: mouseArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Hyprland.dispatch("workspace " + modelData)
                    }
                }
            }
        }
    }
}