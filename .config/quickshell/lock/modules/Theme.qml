import QtQuick
pragma Singleton 

QtObject {
    readonly property color bg0: "#050505" 
    readonly property color bgGlass: Qt.alpha("#1e1e24", 0.60)
    readonly property color fg: "#abb2bf"
    readonly property color blue: "#61afef"
    readonly property color red: "#e08c75"
    readonly property color grey1: "#828997"
    readonly property color white: "#ffffff"
    
    readonly property string fontMain: "Adwaita Sans"
    readonly property string fontIcons: "CaskaydiaCove Nerd Font Propo"

    property real scale: 1.25
}