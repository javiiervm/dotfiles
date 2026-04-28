import QtQuick
pragma Singleton 

QtObject {
    readonly property color bg0: "#050505" 
    readonly property color bg1: "#121212"
    readonly property color fg: "#abb2bf"
    readonly property color blue: "#61afef"
    readonly property color red: "#e08c75"
    readonly property color green: "#98c379"
    readonly property color yellow: "#e5c07b"
    readonly property color purple: "#c678dd"
    readonly property color grey1: "#828997"
    
    readonly property string fontMain: "Adwaita Sans"
    readonly property string fontIcons: "CaskaydiaCove Nerd Font Propo"

    readonly property color notifBg: "#282c34"
    readonly property color notifBgAlt: "#21252b"
    readonly property color notifBgBtn: "#3e4451"
    readonly property color notifBg3: "#4b5263"   // ✅ añadido
    readonly property color orange: "#d19a66"
    readonly property color white: "#ffffff"
}
