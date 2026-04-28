import QtQuick
import QtQuick.Layouts
import ".."

Item {
    id: toggleRoot
    property string icon: ""
    property color accent: "white"
    property bool isActive: false
    signal clicked() 
    
    Layout.preferredWidth: 46 
    Layout.preferredHeight: 46 
    
    Rectangle {
        anchors.fill: parent; radius: 12 
        color: isActive ? accent : Theme.notifBgBtn
        opacity: isActive ? 0.9 : 0.5 
    }
    
    Text {
        anchors.centerIn: parent
        text: icon; color: "white"; font.family: Theme.fontIcons; font.pixelSize: 22
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        // El fix final: acepta el clic aquí para que no se cierre el panel
        onClicked: { 
            mouse.accepted = true; 
            toggleRoot.clicked(); 
        }
    }
}