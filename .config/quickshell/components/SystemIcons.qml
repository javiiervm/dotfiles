import QtQuick
import QtQuick.Layouts
import ".."

Row {
    id: iconsRoot
    property var rootRef 
    
    property string ssid: ""
    property string wifiSignal: "" 
    property string freq: ""
    property bool btOn: false
    property string btDev: ""
    property int vol: 0 
    property bool volMute: false
    property string volDesc: ""
    property string perf: ""
    
    spacing: 8 

    function updateMenu(open, title, info1, info2, color, offset) {
        if (!rootRef) return;
        rootRef.activeMenuTitle = title;
        rootRef.activeMenuInfo1 = info1;
        rootRef.activeMenuInfo2 = info2;
        rootRef.activeMenuAccent = color;
        rootRef.activeMenuOffset = offset;
        rootRef.isMenuOpen = open;
    }

    // --- Wi-Fi () ---
    Item {
        width: 20; height: 44
        Text {
            anchors.centerIn: parent
            text: "" 
            color: (ssid === "Disconnected" || ssid === "") ? "#8c8c8c" : "#ffffff"
            font.family: Theme.fontIcons
            font.pixelSize: 14 
        }
        MouseArea { 
            anchors.fill: parent
            hoverEnabled: true 
            onEntered: iconsRoot.updateMenu(true, "Wi-Fi Network", "SSID: " + ssid, "Signal: " + wifiSignal + "%", "#3498db", 142)
            onExited: iconsRoot.updateMenu(false, "", "", "", "#ffffff", 142)
            onClicked: {
                rootRef.controlCenterTab = "wifi"
                rootRef.isControlCenterOpen = !rootRef.isControlCenterOpen
            }
        }
    }

    // --- Bluetooth () ---
    Item {
        width: 20; height: 44
        Text {
            anchors.centerIn: parent
            text: "" 
            color: btOn ? "#ffffff" : "#8c8c8c"
            font.family: Theme.fontIcons
            font.pixelSize: 16
        }
        MouseArea { 
            anchors.fill: parent
            hoverEnabled: true 
            onEntered: iconsRoot.updateMenu(true, "Bluetooth", btOn ? "Active" : "Off", "Device: " + btDev, "#3b82f6", 112)
            onExited: iconsRoot.updateMenu(false, "", "", "", "#ffffff", 112)
            onClicked: {
                rootRef.controlCenterTab = "bluetooth"
                rootRef.isControlCenterOpen = !rootRef.isControlCenterOpen
            }
        }
    }

    // --- Volumen (Mute a 0) ---
    Item {
        width: 20; height: 44
        Text {
            anchors.centerIn: parent
            text: {
                if (volMute || vol === 0) return "󰝟";
                var d = volDesc.toLowerCase();
                if (d.includes("bluez") || d.includes("buds") || d.includes("headphone")) return "󰋋";
                if (vol >= 66) return "󰕾";
                if (vol >= 33) return "󰖀";
                return "󰕿";
            }
            color: (volMute || vol === 0) ? "#8c8c8c" : "#ffffff"
            font.family: Theme.fontIcons
            font.pixelSize: 16
        }
        MouseArea { 
            anchors.fill: parent
            hoverEnabled: true 
            onEntered: iconsRoot.updateMenu(true, "Audio", (volMute || vol === 0) ? "Muted" : "Level: " + vol + "%", "Output: " + volDesc, "#e74c3c", 82)
            onExited: iconsRoot.updateMenu(false, "", "", "", "#ffffff", 82)
        }
    }

    // --- Rendimiento (Color Dinámico) ---
    Item {
        width: 20; height: 44
        
        // Definimos el color según el perfil activo para usarlo en el icono y el menú
        readonly property color currentPerfColor: {
            if (perf === "power-saver") return "#2ecc71"; // Verde
            if (perf === "performance") return "#f39c12"; // Naranja
            return "#ffffff"; // Blanco (Balanced)
        }

        Text {
            anchors.centerIn: parent
            text: "󰓅"
            color: parent.currentPerfColor
            font.family: Theme.fontIcons
            font.pixelSize: 16
        }
        MouseArea { 
            anchors.fill: parent
            hoverEnabled: true 
            onEntered: {
                // Pasamos el color calculado a la ventanita emergente
                iconsRoot.updateMenu(true, "Power Mode", "Profile: " + perf, "Mode: System Controlled", parent.currentPerfColor, 52);
            }
            onExited: {
                iconsRoot.updateMenu(false, "", "", "", "#ffffff", 52);
            }
        }
    }
}