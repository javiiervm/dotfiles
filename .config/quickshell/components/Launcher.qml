import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".."

PanelWindow {
    id: launcherWindow

    // ==========================================
    // PROPIEDADES DE ESTADO BASES
    // ==========================================
    property bool visible_state: false
    property bool isReallyVisible: false
    property string calcResult: "" 
    
    // Modos: 0: Apps, 1: Files Search, 4: System, 5: Wi-Fi, 6: Bluetooth, 9: Password
    property int currentMode: 0 
    property string targetWifiSsid: ""
    property bool isWifiEnabled: false
    property bool isBtEnabled: false
    
    property bool isWifiLoading: false
    property bool isBtLoading: false
    property bool isFileLoading: false
    
    property int activeHeaderButton: 0 
    
    signal requestIslandMsg(string icon, string color, string text)

    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: isReallyVisible ? WlrLayershell.OnDemand : WlrLayershell.None
    visible: isReallyVisible
    color: "transparent"

    ListModel { id: rawModel }
    ListModel { id: filteredModel }

    Component.onCompleted: { loadTabData("--apps"); }

    MouseArea { anchors.fill: parent; onClicked: { if (visible_state) toggle(); } }

    Timer {
        id: closeTimer
        interval: 300
        onTriggered: {
            isReallyVisible = false;
            launcherWindow.currentMode = 0;
            launcherWindow.activeHeaderButton = 0;
            searchInput.text = "";
            searchInput.echoMode = TextInput.Normal;
            loadTabData("--apps"); 
        }
    }

    Timer {
        id: refreshTimer
        interval: 1500
        onTriggered: { 
            if (launcherWindow.currentMode === 5) loadTabData("--wifi"); 
            else if (launcherWindow.currentMode === 6) loadTabData("--bt");
        }
    }

    Process {
        id: dataLoader
        stdout: SplitParser {
            onRead: (line) => {
                if (!line || line.trim() === "") return;
                var f = line.split("|");
                if (f.length >= 5) { rawModel.append({ name: f[0], comment: f[1], icon: f[2], exec: f[3], type: f[4] }); }
            }
        }
        onExited: {
            launcherWindow.isFileLoading = false;
            updateFilter();
        }
    }

    Process { id: execProc }

    Process {
        id: netConnectProc
        property string targetName: ""
        onExited: function(exitCode) {
            var success = (exitCode === 0);
            var color = success ? "#30d158" : "#ff3b30";
            var status = success ? "Connected to " : "Failed to connect to ";
            launcherWindow.requestIslandMsg("", color, status + targetName);
            if (launcherWindow.currentMode === 5) loadTabData("--wifi");
        }
    }

    Process {
        id: btConnectProc
        property string targetName: ""
        onExited: function(exitCode) {
            var success = (exitCode === 0);
            var color = success ? "#30d158" : "#ff3b30";
            var status = success ? "Connected to " : "Failed to connect to ";
            launcherWindow.requestIslandMsg("", color, status + targetName);
            if (launcherWindow.currentMode === 6) loadTabData("--bt");
        }
    }

    // ==========================================
    // INTERFAZ VISUAL (UI)
    // ==========================================
    Rectangle {
        id: mainCard
        
        property int targetWidth: {
            if (launcherWindow.currentMode === 1 || launcherWindow.currentMode === 4 || launcherWindow.currentMode === 5 || launcherWindow.currentMode === 6) return 420; 
            if (launcherWindow.currentMode === 9) return 320; 
            return 720; 
        }

        width: targetWidth
        height: contentColumn.height + 40 
        anchors.centerIn: parent
        transformOrigin: Item.Center 
        radius: 20
        color: Theme.bgGlass
        border.color: Qt.alpha(Theme.white, 0.15)
        border.width: 1
        clip: true

        scale: launcherWindow.visible_state ? 1.0 : 0.0
        opacity: launcherWindow.visible_state ? 1.0 : 0.0

        Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.OutQuint } }
        Behavior on height { NumberAnimation { duration: 350; easing.type: Easing.OutQuint } }
        Behavior on scale { NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }
        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutQuad } }

        MouseArea { anchors.fill: parent }

        Column {
            id: contentColumn
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 20
            spacing: 20

            // ------------------------------------------
            // 1. CABECERA DINÁMICA
            // ------------------------------------------
            Item {
                width: parent.width
                height: launcherWindow.currentMode === 9 ? 85 : 50
                Behavior on height { NumberAnimation { duration: 350; easing.type: Easing.OutQuint } }

                Text {
                    anchors.top: parent.top
                    anchors.topMargin: 5
                    width: parent.width
                    text: launcherWindow.targetWifiSsid
                    color: Theme.white
                    font.pixelSize: 16
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    visible: launcherWindow.currentMode === 9
                    opacity: launcherWindow.currentMode === 9 ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 250 } }
                }

                // A) BUSCADOR Y CONTRASEÑA
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 50
                    visible: launcherWindow.currentMode === 0 || launcherWindow.currentMode === 9
                    radius: height / 2
                    color: Qt.alpha(Theme.white, 0.05)
                    border.color: Qt.alpha(Theme.white, 0.15)
                    border.width: 1

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: launcherWindow.currentMode === 9 ? 8 : 20
                        anchors.rightMargin: 20
                        spacing: 12

                        Rectangle {
                            width: 34; height: 34; radius: 17; color: "transparent"
                            anchors.verticalCenter: parent.verticalCenter
                            visible: launcherWindow.currentMode === 9
                            Text { anchors.centerIn: parent; text: ""; font.family: Theme.fontIcons; color: Theme.grey1; font.pixelSize: 16 }
                            MouseArea { 
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: { launcherWindow.currentMode = 5; searchInput.echoMode = TextInput.Normal; searchInput.text = ""; loadTabData("--wifi"); } 
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: ""
                            font.family: Theme.fontIcons
                            color: Theme.grey1
                            font.pixelSize: 18
                            visible: launcherWindow.currentMode === 0
                        }

                        TextInput {
                            id: searchInput
                            width: parent.width - (launcherWindow.currentMode === 9 ? 50 : 32)
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.white
                            font.pixelSize: 16
                            selectionColor: Theme.blue
                            selectedTextColor: Theme.bg0
                            clip: true

                            Text {
                                text: launcherWindow.currentMode === 9 ? "Password" : "Search"
                                color: Theme.grey1
                                font.pixelSize: 16
                                anchors.verticalCenter: parent.verticalCenter
                                visible: searchInput.text === ""
                            }

                            onTextChanged: {
                                // Si escribe/borra algo mientras está en la vista de archivos, lo devolvemos a la vista general
                                // y recargamos el modelo de apps (si no, quedan los resultados de archivos "pegados").
                                if (launcherWindow.currentMode === 1) {
                                    launcherWindow.currentMode = 0;
                                    loadTabData("--apps");
                                    return;
                                }
                                updateFilter();
                            }

                            Keys.onPressed: (event) => {
                                if (event.key === Qt.Key_Escape) {
                                    if (launcherWindow.currentMode === 9) { launcherWindow.currentMode = 5; searchInput.echoMode = TextInput.Normal; searchInput.text = ""; loadTabData("--wifi"); }
                                    else { toggle(); }
                                    event.accepted = true;
                                }
                                
                                if (event.key === Qt.Key_Backspace && searchInput.text === "") {
                                    if (launcherWindow.currentMode === 9) {
                                        launcherWindow.currentMode = 5; searchInput.echoMode = TextInput.Normal; loadTabData("--wifi");
                                    } else if (launcherWindow.currentMode === 1 || launcherWindow.currentMode === 4 || launcherWindow.currentMode === 5 || launcherWindow.currentMode === 6) {
                                        launcherWindow.currentMode = 0; launcherWindow.activeHeaderButton = 0; loadTabData("--apps");
                                    }
                                    event.accepted = true;
                                }
                                
                                if (event.key === Qt.Key_Down && launcherWindow.calcResult === "") { 
                                    if (launcherWindow.currentMode === 0) {
                                        appGrid.moveCurrentIndexDown(); 
                                    } else if (launcherWindow.currentMode === 1 || launcherWindow.currentMode === 4 || launcherWindow.currentMode === 5 || launcherWindow.currentMode === 6) {
                                        if (launcherWindow.activeHeaderButton > 0) {
                                            launcherWindow.activeHeaderButton = 0; 
                                        } else {
                                            var targetListDown = launcherWindow.currentMode === 1 ? fileList : (launcherWindow.currentMode === 4 ? sysList : (launcherWindow.currentMode === 5 ? wifiList : btList));
                                            if (launcherWindow.currentMode === 1 && filteredModel.get(targetListDown.currentIndex).type === "empty") return;
                                            do { targetListDown.incrementCurrentIndex(); } while (filteredModel.count > 0 && filteredModel.get(targetListDown.currentIndex).type === "dummy" && targetListDown.currentIndex < filteredModel.count - 1);
                                        }
                                    }
                                    event.accepted = true; 
                                }
                                
                                if (event.key === Qt.Key_Up && launcherWindow.calcResult === "") { 
                                    if (launcherWindow.currentMode === 0) {
                                        appGrid.moveCurrentIndexUp(); 
                                    } else if (launcherWindow.currentMode === 1 || launcherWindow.currentMode === 4 || launcherWindow.currentMode === 5 || launcherWindow.currentMode === 6) {
                                        if (launcherWindow.activeHeaderButton === 0) {
                                            var targetListUp = launcherWindow.currentMode === 1 ? fileList : (launcherWindow.currentMode === 4 ? sysList : (launcherWindow.currentMode === 5 ? wifiList : btList));
                                            if (targetListUp.currentIndex === 0 || (targetListUp.currentIndex === 1 && filteredModel.get(0).type === "dummy")) { 
                                                launcherWindow.activeHeaderButton = 1; 
                                            } else {
                                                do { targetListUp.decrementCurrentIndex(); } while (filteredModel.get(targetListUp.currentIndex).type === "dummy" && targetListUp.currentIndex > 0);
                                            }
                                        }
                                    }
                                    event.accepted = true; 
                                }
                                
                                if (event.key === Qt.Key_Right) {
                                    if (launcherWindow.currentMode === 0) { appGrid.moveCurrentIndexRight(); }
                                    else if ((launcherWindow.currentMode === 5 || launcherWindow.currentMode === 6) && launcherWindow.activeHeaderButton > 0) {
                                        launcherWindow.activeHeaderButton = Math.min(3, launcherWindow.activeHeaderButton + 1);
                                    }
                                    event.accepted = true;
                                }
                                
                                if (event.key === Qt.Key_Left) {
                                    if (launcherWindow.currentMode === 0) { appGrid.moveCurrentIndexLeft(); }
                                    else if ((launcherWindow.currentMode === 5 || launcherWindow.currentMode === 6) && launcherWindow.activeHeaderButton > 0) {
                                        launcherWindow.activeHeaderButton = Math.max(1, launcherWindow.activeHeaderButton - 1);
                                    }
                                    event.accepted = true;
                                }

                                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    // 1. FORZAR BÚSQUEDA DE ARCHIVOS (Ctrl + Enter)
                                    if (event.modifiers & Qt.ControlModifier && searchInput.text !== "" && launcherWindow.currentMode === 0) {
                                        launcherWindow.isFileLoading = true;
                                        launcherWindow.currentMode = 1; 
                                        loadTabData("--search-files", searchInput.text);
                                        event.accepted = true; return;
                                    }
                                    
                                    // 2. FORZAR BÚSQUEDA WEB (Shift + Enter)
                                    if (event.modifiers & Qt.ShiftModifier && searchInput.text !== "" && launcherWindow.currentMode === 0) {
                                        executeApp("firefox 'https://www.google.com/search?q=" + encodeURIComponent(searchInput.text) + "'", "Web Search");
                                        event.accepted = true; return;
                                    }

                                    // 3. NAVEGACIÓN EN CABECERAS
                                    if ((launcherWindow.currentMode === 1 || launcherWindow.currentMode === 4 || launcherWindow.currentMode === 5 || launcherWindow.currentMode === 6) && launcherWindow.activeHeaderButton > 0) {
                                        if (launcherWindow.activeHeaderButton === 1) { 
                                            launcherWindow.currentMode = 0; launcherWindow.activeHeaderButton = 0; loadTabData("--apps"); 
                                        }
                                        else if (launcherWindow.activeHeaderButton === 2) { 
                                            execProc.command = launcherWindow.currentMode === 5 ? ["nmcli", "device", "wifi", "rescan"] : ["bluetoothctl", "scan", "on"]; 
                                            execProc.running = true; refreshTimer.start(); 
                                        }
                                        else if (launcherWindow.activeHeaderButton === 3) { 
                                            if (launcherWindow.currentMode === 5) {
                                                launcherWindow.isWifiLoading = true;
                                                var cmdWifi = launcherWindow.isWifiEnabled ? "off" : "on"; 
                                                execProc.command = ["nmcli", "radio", "wifi", cmdWifi]; 
                                                execProc.running = true; refreshTimer.start();
                                            } else {
                                                launcherWindow.isBtLoading = true;
                                                var cmdBt = launcherWindow.isBtEnabled ? "off" : "on"; 
                                                execProc.command = ["/bin/bash", "-c", "rfkill unblock bluetooth; bluetoothctl power " + cmdBt]; 
                                                execProc.running = true; refreshTimer.start();
                                            }
                                        }
                                        event.accepted = true; return;
                                    }

                                    // 4. FALLBACK: SI NO HAY APPS, BUSCAR EN WEB
                                    if (launcherWindow.currentMode === 0 && filteredModel.count === 0 && searchInput.text !== "" && launcherWindow.calcResult === "") {
                                        executeApp("firefox 'https://www.google.com/search?q=" + encodeURIComponent(searchInput.text) + "'", "Web Search");
                                        event.accepted = true; return;
                                    }

                                    // 5. EJECUCIÓN NORMAL
                                    if (launcherWindow.currentMode === 9) {
                                        launcherWindow.requestIslandMsg("", "white", "Trying to connect to " + targetWifiSsid + "...");
                                        netConnectProc.targetName = targetWifiSsid;
                                        netConnectProc.command = ["nmcli", "device", "wifi", "connect", targetWifiSsid, "password", searchInput.text];
                                        netConnectProc.running = true; searchInput.echoMode = TextInput.Normal; searchInput.text = ""; launcherWindow.currentMode = 5; 
                                    } else if (launcherWindow.calcResult !== "") {
                                        execProc.command = ["/bin/bash", "-c", "wl-copy '" + launcherWindow.calcResult + "' && notify-send 'Calculator' 'Copied: " + launcherWindow.calcResult + "' -i accessories-calculator"];
                                        execProc.running = true; toggle();
                                    } else {
                                        var activeIndex = -1;
                                        if (launcherWindow.currentMode === 1) activeIndex = fileList.currentIndex;
                                        else if (launcherWindow.currentMode === 4) activeIndex = sysList.currentIndex;
                                        else if (launcherWindow.currentMode === 5) activeIndex = wifiList.currentIndex;
                                        else if (launcherWindow.currentMode === 6) activeIndex = btList.currentIndex;
                                        else activeIndex = appGrid.currentIndex;

                                        if (filteredModel.count > 0 && activeIndex >= 0) {
                                            var item = filteredModel.get(activeIndex);
                                            executeApp(item.exec, item.name);
                                        }
                                    }
                                    event.accepted = true;
                                }
                            }
                        }
                    }
                }

                // B) CONTROLES DE WI-FI Y BLUETOOTH (Ocultados por espacio si es necesario, iguales a antes)
                Item {
                    width: parent.width; height: parent.height
                    visible: launcherWindow.currentMode === 5 || launcherWindow.currentMode === 6

                    Rectangle {
                        id: backBtnNet
                        width: 40; height: 40; radius: 20
                        color: launcherWindow.activeHeaderButton === 1 ? Qt.alpha(Theme.white, 0.2) : Qt.alpha(Theme.white, 0.08)
                        border.color: launcherWindow.activeHeaderButton === 1 ? Theme.white : "transparent"
                        border.width: 1
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        Text { anchors.centerIn: parent; text: ""; font.family: Theme.fontIcons; color: Theme.white; font.pixelSize: 16 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { launcherWindow.currentMode = 0; launcherWindow.activeHeaderButton = 0; loadTabData("--apps"); } }
                    }

                    Text {
                        text: launcherWindow.currentMode === 5 ? "Wi-Fi Networks" : "Bluetooth Devices"
                        color: Theme.white; font.pixelSize: 16; font.bold: true
                        anchors.left: backBtnNet.right; anchors.leftMargin: 15; anchors.verticalCenter: parent.verticalCenter
                    }

                    Row {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                        Rectangle {
                            width: 40; height: 40; radius: 20
                            color: launcherWindow.activeHeaderButton === 2 ? Qt.alpha(Theme.white, 0.2) : Qt.alpha(Theme.white, 0.08)
                            border.color: launcherWindow.activeHeaderButton === 2 ? Theme.white : "transparent"
                            border.width: 1
                            Text { anchors.centerIn: parent; text: "󰑐"; font.family: Theme.fontIcons; color: Theme.white; font.pixelSize: 16 }
                            MouseArea { 
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor; 
                                onClicked: { 
                                    execProc.command = launcherWindow.currentMode === 5 ? ["nmcli", "device", "wifi", "rescan"] : ["bluetoothctl", "scan", "on"];
                                    execProc.running = true; refreshTimer.start(); 
                                } 
                            }
                        }
                        
                        Rectangle {
                            width: 40; height: 40; radius: 20
                            property bool loadState: launcherWindow.currentMode === 5 ? launcherWindow.isWifiLoading : launcherWindow.isBtLoading
                            property bool enableState: launcherWindow.currentMode === 5 ? launcherWindow.isWifiEnabled : launcherWindow.isBtEnabled
                            
                            color: loadState ? Qt.alpha(Theme.white, 0.4) : (enableState ? Theme.white : (launcherWindow.activeHeaderButton === 3 ? Qt.alpha(Theme.white, 0.2) : Qt.alpha(Theme.white, 0.08)))
                            border.color: launcherWindow.activeHeaderButton === 3 ? (enableState ? Theme.blue : Theme.white) : "transparent"
                            border.width: 2
                            Text { 
                                anchors.centerIn: parent; font.family: Theme.fontIcons; font.pixelSize: 16 
                                text: launcherWindow.currentMode === 5 ? "" : ""
                                color: parent.loadState ? Theme.white : (parent.enableState ? Theme.bg0 : Theme.white); 
                            }
                            MouseArea { 
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor; 
                                onClicked: { 
                                    var cmdBase = parent.enableState ? "off" : "on";
                                    if (launcherWindow.currentMode === 5) {
                                        launcherWindow.isWifiLoading = true;
                                        execProc.command = ["nmcli", "radio", "wifi", cmdBase];
                                    } else {
                                        launcherWindow.isBtLoading = true;
                                        execProc.command = ["/bin/bash", "-c", "rfkill unblock bluetooth; bluetoothctl power " + cmdBase]; 
                                    }
                                    execProc.running = true; refreshTimer.start();
                                } 
                            }
                        }
                    }
                }

                // C) CONTROLES DE SISTEMA Y ARCHIVOS (Modos 1 y 4)
                Item {
                    width: parent.width; height: parent.height
                    visible: launcherWindow.currentMode === 1 || launcherWindow.currentMode === 4

                    Rectangle {
                        id: backBtnSys
                        width: 40; height: 40; radius: 20
                        color: launcherWindow.activeHeaderButton === 1 ? Qt.alpha(Theme.white, 0.2) : Qt.alpha(Theme.white, 0.08)
                        border.color: launcherWindow.activeHeaderButton === 1 ? Theme.white : "transparent"
                        border.width: 1
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        Text { anchors.centerIn: parent; text: ""; font.family: Theme.fontIcons; color: Theme.white; font.pixelSize: 16 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { launcherWindow.currentMode = 0; launcherWindow.activeHeaderButton = 0; searchInput.text = ""; loadTabData("--apps"); } }
                    }

                    Text {
                        text: launcherWindow.currentMode === 1 ? "File Search Results" : "System Options"
                        color: Theme.white; font.pixelSize: 16; font.bold: true
                        anchors.left: backBtnSys.right; anchors.leftMargin: 15; anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // ------------------------------------------
            // 2. CUADRÍCULA DE APLICACIONES (Modo 0)
            // ------------------------------------------
            GridView {
                id: appGrid
                width: parent.width; model: filteredModel
                cellWidth: parent.width / 6; cellHeight: 110
                height: Math.min(Math.ceil(count / 6) * cellHeight, 440)
                currentIndex: 0; clip: true
                visible: count > 0 && launcherWindow.calcResult === "" && launcherWindow.currentMode === 0

                delegate: Rectangle {
                    width: appGrid.cellWidth - 10; height: appGrid.cellHeight - 10; anchors.margins: 5; radius: 14
                    color: GridView.isCurrentItem ? Qt.alpha(Theme.white, 0.15) : "transparent"

                    Column {
                        anchors.centerIn: parent; spacing: 8
                        Image { width: 56; height: 56; anchors.horizontalCenter: parent.horizontalCenter; source: icon.startsWith("/") ? "file://" + icon : "image://icon/" + icon; fillMode: Image.PreserveAspectFit; asynchronous: true }
                        Text { width: parent.width - 10; anchors.horizontalCenter: parent.horizontalCenter; text: name; color: Theme.white; font.pixelSize: 12; font.family: Theme.fontMain; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.WordWrap }
                    }
                    MouseArea { anchors.fill: parent; onClicked: { appGrid.currentIndex = index; executeApp(exec, name); } }
                }
            }

            // ------------------------------------------
            // 3. LISTAS VERTICALES (Archivos, Sistema, Wi-Fi, Bluetooth)
            // ------------------------------------------
            ListView {
                id: fileList
                width: parent.width; model: filteredModel; height: Math.min(count * 55, 440)
                currentIndex: 0; clip: true; spacing: 0
                visible: launcherWindow.currentMode === 1 && count > 0
                delegate: Rectangle {
                    width: fileList.width; height: type === "empty" ? 40 : 55; radius: 12
                    color: (type !== "empty" && ListView.isCurrentItem && launcherWindow.activeHeaderButton === 0) ? Qt.alpha(Theme.white, 0.1) : "transparent"
                    Item {
                        anchors.fill: parent; anchors.margins: 10
                        Text { id: fIcon; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: ""; font.family: Theme.fontIcons; font.pixelSize: 18; color: Theme.white; visible: type !== "empty" }
                        Column {
                            anchors.left: type !== "empty" ? fIcon.right : parent.left; anchors.leftMargin: type !== "empty" ? 15 : 0
                            anchors.right: parent.right; anchors.rightMargin: 15; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                            Text { width: parent.width; text: name; color: type === "empty" ? Qt.alpha(Theme.white, 0.5) : Theme.white; font.pixelSize: type === "empty" ? 11 : 15; font.bold: true; elide: Text.ElideRight }
                            Text { width: parent.width; text: comment; color: Theme.grey1; font.pixelSize: 11; elide: Text.ElideRight; visible: type !== "empty" }
                        }
                    }
                    MouseArea { anchors.fill: parent; enabled: type !== "empty"; onClicked: { launcherWindow.activeHeaderButton = 0; fileList.currentIndex = index; executeApp(exec, name); } }
                }
            }

            ListView {
                id: sysList
                width: parent.width; model: filteredModel; height: Math.min(count * 55, 440)
                currentIndex: 0; clip: true; spacing: 0
                visible: launcherWindow.currentMode === 4 && count > 0
                delegate: Rectangle {
                    width: sysList.width; height: 55; radius: 12
                    color: (ListView.isCurrentItem && launcherWindow.activeHeaderButton === 0) ? Qt.alpha(Theme.white, 0.1) : "transparent"
                    Item {
                        anchors.fill: parent; anchors.margins: 10
                        Image { id: sysIcon; width: 24; height: 24; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; source: icon.startsWith("/") ? "file://" + icon : "image://icon/" + icon }
                        Column {
                            anchors.left: sysIcon.right; anchors.leftMargin: 15; anchors.right: parent.right; anchors.rightMargin: 15; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                            Text { width: parent.width; text: name; color: Theme.white; font.pixelSize: 15; font.bold: true; elide: Text.ElideRight }
                            Text { width: parent.width; text: comment; color: Theme.grey1; font.pixelSize: 11; elide: Text.ElideRight }
                        }
                    }
                    MouseArea { anchors.fill: parent; onClicked: { launcherWindow.activeHeaderButton = 0; sysList.currentIndex = index; executeApp(exec, name); } }
                }
            }

            ListView {
                id: wifiList
                width: parent.width; model: filteredModel; height: Math.min(count * 55, 440)
                currentIndex: 0; clip: true; spacing: 0
                visible: launcherWindow.currentMode === 5 && count > 0
                delegate: Rectangle {
                    width: wifiList.width; height: type === "dummy" ? 40 : 55; radius: 12
                    color: (type !== "dummy" && ListView.isCurrentItem && launcherWindow.activeHeaderButton === 0) ? Qt.alpha(Theme.white, 0.1) : "transparent"
                    Item { anchors.fill: parent; visible: type === "dummy"; Text { anchors.left: parent.left; anchors.leftMargin: 5; anchors.verticalCenter: parent.verticalCenter; text: name; color: Qt.alpha(Theme.white, 0.5); font.pixelSize: 11; font.bold: true } }
                    Item {
                        anchors.fill: parent; anchors.margins: 10; visible: type !== "dummy"
                        Text { id: wifiIcon; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: ""; font.family: Theme.fontIcons; font.pixelSize: 18; color: type === "wifi_current" ? "#30d158" : Theme.white }
                        Text { id: checkIconWifi; anchors.right: parent.right; anchors.rightMargin: 5; anchors.verticalCenter: parent.verticalCenter; text: "󰄬"; font.family: Theme.fontIcons; color: "#30d158"; font.pixelSize: 20; visible: type === "wifi_current" }
                        Column {
                            anchors.left: wifiIcon.right; anchors.leftMargin: 15; anchors.right: checkIconWifi.visible ? checkIconWifi.left : parent.right; anchors.rightMargin: 15; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                            Text { width: parent.width; text: name; color: type === "wifi_current" ? "#30d158" : Theme.white; font.pixelSize: 15; font.bold: true; elide: Text.ElideRight }
                            Text { width: parent.width; text: comment; color: Theme.grey1; font.pixelSize: 11; elide: Text.ElideRight }
                        }
                    }
                    MouseArea { anchors.fill: parent; enabled: type !== "dummy"; onClicked: { launcherWindow.activeHeaderButton = 0; wifiList.currentIndex = index; executeApp(exec, name); } }
                }
            }

            ListView {
                id: btList
                width: parent.width; model: filteredModel; height: Math.min(count * 55, 440)
                currentIndex: 0; clip: true; spacing: 0
                visible: launcherWindow.currentMode === 6 && count > 0
                delegate: Rectangle {
                    width: btList.width; height: type === "dummy" ? 40 : 55; radius: 12
                    color: (type !== "dummy" && ListView.isCurrentItem && launcherWindow.activeHeaderButton === 0) ? Qt.alpha(Theme.white, 0.1) : "transparent"
                    Item { anchors.fill: parent; visible: type === "dummy"; Text { anchors.left: parent.left; anchors.leftMargin: 5; anchors.verticalCenter: parent.verticalCenter; text: name; color: Qt.alpha(Theme.white, 0.5); font.pixelSize: 11; font.bold: true } }
                    Item {
                        anchors.fill: parent; anchors.margins: 10; visible: type !== "dummy"
                        Text { id: btIcon; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: ""; font.family: Theme.fontIcons; font.pixelSize: 18; color: type === "bt_current" ? "#30d158" : Theme.white }
                        Text { id: checkIconBt; anchors.right: parent.right; anchors.rightMargin: 5; anchors.verticalCenter: parent.verticalCenter; text: "󰄬"; font.family: Theme.fontIcons; color: "#30d158"; font.pixelSize: 20; visible: type === "bt_current" }
                        Text { anchors.left: btIcon.right; anchors.leftMargin: 15; anchors.right: checkIconBt.visible ? checkIconBt.left : parent.right; anchors.rightMargin: 15; anchors.verticalCenter: parent.verticalCenter; text: name; color: type === "bt_current" ? "#30d158" : Theme.white; font.pixelSize: 15; font.bold: true; elide: Text.ElideRight }
                    }
                    MouseArea { anchors.fill: parent; enabled: type !== "dummy"; onClicked: { launcherWindow.activeHeaderButton = 0; btList.currentIndex = index; executeApp(exec, name); } }
                }
            }

            // ------------------------------------------
            // 4. TARJETAS ESPECIALES (Calculadora y Búsquedas Ocultas)
            // ------------------------------------------
            Rectangle {
                width: parent.width; height: 75; radius: 16; color: Qt.alpha(Theme.white, 0.05); border.color: Qt.alpha(Theme.white, 0.15); border.width: 1
                visible: launcherWindow.calcResult !== ""

                Row {
                    anchors.fill: parent; anchors.margins: 15; spacing: 15
                    Rectangle { width: 45; height: 45; radius: 12; color: Theme.blue; anchors.verticalCenter: parent.verticalCenter; Text { anchors.centerIn: parent; text: ""; font.family: Theme.fontIcons; color: Theme.bg0; font.pixelSize: 22 } }
                    Column { anchors.verticalCenter: parent.verticalCenter; spacing: 2; Text { text: launcherWindow.calcResult; color: Theme.white; font.pixelSize: 24; font.bold: true } Text { text: "Press Enter to copy to clipboard"; color: Theme.grey1; font.pixelSize: 12 } }
                }
            }
            
            // NUEVO: FILA DISCRETA PARA FALLBACKS DE BÚSQUEDA
            Row {
                width: parent.width; height: 75; spacing: 15
                // Solo aparece cuando estás escribiendo algo y estás en la vista normal
                visible: launcherWindow.currentMode === 0 && searchInput.text !== "" && launcherWindow.calcResult === ""

                // TARJETA DE BÚSQUEDA WEB
                Rectangle {
                    width: (parent.width - 15) / 2; height: parent.height; radius: 16
                    // Si no hay apps, se enciende en azul para avisarte de que es la acción por defecto
                    color: (filteredModel.count === 0) ? Theme.blue : Qt.alpha(Theme.white, 0.05)
                    border.color: Qt.alpha(Theme.white, 0.15); border.width: 1
                    
                    Row {
                        anchors.fill: parent; anchors.margins: 15; spacing: 15
                        Rectangle { 
                            width: 45; height: 45; radius: 12; color: (filteredModel.count === 0) ? Theme.bg0 : Theme.blue; anchors.verticalCenter: parent.verticalCenter; 
                            Text { anchors.centerIn: parent; text: "󰖟"; font.family: Theme.fontIcons; color: (filteredModel.count === 0) ? Theme.blue : Theme.bg0; font.pixelSize: 22 } 
                        }
                        Column { 
                            anchors.verticalCenter: parent.verticalCenter; spacing: 2; 
                            Text { text: "Web Search"; color: (filteredModel.count === 0) ? Theme.bg0 : Theme.white; font.pixelSize: 16; font.bold: true; width: parent.width - 90; elide: Text.ElideRight } 
                            Text { text: (filteredModel.count === 0) ? "Press Enter" : "Shift + Enter"; color: (filteredModel.count === 0) ? Qt.alpha(Theme.bg0, 0.8) : Theme.grey1; font.pixelSize: 12 } 
                        }
                    }
                    MouseArea { 
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor; 
                        onClicked: { executeApp("firefox 'https://www.google.com/search?q=" + encodeURIComponent(searchInput.text) + "'", "Web Search"); } 
                    }
                }

                // TARJETA DE BÚSQUEDA DE ARCHIVOS
                Rectangle {
                    width: (parent.width - 15) / 2; height: parent.height; radius: 16
                    color: Qt.alpha(Theme.white, 0.05); border.color: Qt.alpha(Theme.white, 0.15); border.width: 1
                    
                    Row {
                        anchors.fill: parent; anchors.margins: 15; spacing: 15
                        Rectangle { 
                            width: 45; height: 45; radius: 12; color: Theme.blue; anchors.verticalCenter: parent.verticalCenter; 
                            Text { anchors.centerIn: parent; text: ""; font.family: Theme.fontIcons; color: Theme.bg0; font.pixelSize: 22 } 
                        }
                        Column { 
                            anchors.verticalCenter: parent.verticalCenter; spacing: 2; 
                            Text { text: "Find Files"; color: Theme.white; font.pixelSize: 16; font.bold: true; width: parent.width - 90; elide: Text.ElideRight } 
                            Text { text: "Ctrl + Enter"; color: Theme.grey1; font.pixelSize: 12 } 
                        }
                    }
                    MouseArea { 
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor; 
                        onClicked: { 
                            launcherWindow.isFileLoading = true;
                            launcherWindow.currentMode = 1; 
                            loadTabData("--search-files", searchInput.text); 
                        } 
                    }
                }
            }

            Item {
                width: parent.width; height: 60
                visible: ((launcherWindow.currentMode === 5 || launcherWindow.currentMode === 6 || launcherWindow.currentMode === 1) && filteredModel.count === 0) || launcherWindow.isFileLoading
                Text { 
                    anchors.centerIn: parent
                    text: {
                        if (launcherWindow.currentMode === 1) return launcherWindow.isFileLoading ? "Searching files in ~/... " : "No files found";
                        if (launcherWindow.currentMode === 5) return launcherWindow.isWifiEnabled ? "Scanning networks..." : "Wi-Fi is disabled";
                        if (launcherWindow.currentMode === 6) return launcherWindow.isBtEnabled ? "Scanning devices..." : "Bluetooth is disabled";
                        return "";
                    }
                    color: Theme.grey1; font.pixelSize: 15 
                }
            }
        }
    }

    // ==========================================
    // LÓGICA DE CONTROLADORES
    // ==========================================

    function loadTabData(arg, extra = "") {
        rawModel.clear();
        var cmd = ["/bin/bash", "/home/javier/.config/quickshell/scripts/provider.sh", arg];
        if (extra !== "") cmd.push(extra);
        dataLoader.command = cmd;
        dataLoader.running = true;
    }

    function updateFilter() {
        var search = searchInput.text.toLowerCase().trim();
        filteredModel.clear();
        launcherWindow.calcResult = "";

        if (launcherWindow.currentMode === 1 || launcherWindow.currentMode === 4) {
            for (var s = 0; s < rawModel.count; s++) {
                filteredModel.append(rawModel.get(s));
            }
            if (launcherWindow.activeHeaderButton === 0 && filteredModel.count > 0) {
                if (launcherWindow.currentMode === 1) fileList.currentIndex = 0;
                else sysList.currentIndex = 0;
            }
            return;
        }

        if (launcherWindow.currentMode === 5) {
            launcherWindow.isWifiLoading = false; 
            var currentW = [], savedW = [], newNetsW = [];
            for (var w = 0; w < rawModel.count; w++) {
                var itmW = rawModel.get(w);
                if (itmW.type === "state") { launcherWindow.isWifiEnabled = (itmW.name === "enabled"); continue; }
                if (itmW.type === "wifi_current") currentW.push(itmW);
                else if (itmW.type === "wifi_saved") savedW.push(itmW);
                else if (itmW.type === "wifi_new") newNetsW.push(itmW);
            }
            if (launcherWindow.isWifiEnabled) {
                if (currentW.length > 0) { filteredModel.append({name: "Connected", comment: "", icon: "", exec: "", type: "dummy"}); for(var cw of currentW) filteredModel.append(cw); }
                if (savedW.length > 0) { filteredModel.append({name: "Saved Networks", comment: "", icon: "", exec: "", type: "dummy"}); for(var sw of savedW) filteredModel.append(sw); }
                if (newNetsW.length > 0) { filteredModel.append({name: "Available Networks", comment: "", icon: "", exec: "", type: "dummy"}); for(var nw of newNetsW) filteredModel.append(nw); }
            }
            if (launcherWindow.activeHeaderButton === 0) {
                for (var mw = 0; mw < filteredModel.count; mw++) {
                    if (filteredModel.get(mw).type !== "dummy") { wifiList.currentIndex = mw; break; }
                }
            }
            return;
        }

        if (launcherWindow.currentMode === 6) {
            launcherWindow.isBtLoading = false; 
            var currentB = [], savedB = [];
            for (var b = 0; b < rawModel.count; b++) {
                var itmB = rawModel.get(b);
                if (itmB.type === "state") { launcherWindow.isBtEnabled = (itmB.name === "enabled"); continue; }
                if (itmB.type === "bt_current") currentB.push(itmB);
                else if (itmB.type === "bt_saved") savedB.push(itmB);
            }
            if (launcherWindow.isBtEnabled) {
                if (currentB.length > 0) { filteredModel.append({name: "Connected Devices", comment: "", icon: "", exec: "", type: "dummy"}); for(var cb of currentB) filteredModel.append(cb); }
                if (savedB.length > 0) { filteredModel.append({name: "Paired Devices", comment: "", icon: "", exec: "", type: "dummy"}); for(var sb of savedB) filteredModel.append(sb); }
            }
            if (launcherWindow.activeHeaderButton === 0) {
                for (var mb = 0; mb < filteredModel.count; mb++) {
                    if (filteredModel.get(mb).type !== "dummy") { btList.currentIndex = mb; break; }
                }
            }
            return;
        }

        if (search !== "" && /^[0-9+\-*/().\s]+$/.test(search) && /[+\-*/]/.test(search) && launcherWindow.currentMode === 0) {
            try {
                var cleanMath = search.replace(/[^-()\d/*+.]/g, ''); 
                var res = Function('"use strict";return (' + cleanMath + ')')();
                if (res !== undefined && !isNaN(res)) { launcherWindow.calcResult = res.toString(); return; }
            } catch(e) {}
        }

        var results = [];
        for (var j = 0; j < rawModel.count; j++) {
            var item = rawModel.get(j);
            if (item.type === "dummy" || item.type === "cmd" || item.exec.startsWith("qs_")) {
                if (item.exec !== "qs_sys" && item.exec !== "qs_wifi" && item.exec !== "qs_bt") continue; 
            }
            var itemName = item.name.toLowerCase();
            var itemComment = item.comment.toLowerCase();
            
            if (search === "") { results.push({ item: item, score: 0 }); } 
            else {
                if (itemName.startsWith(search)) results.push({ item: item, score: 1 }); 
                else if (itemName.includes(search)) results.push({ item: item, score: 2 }); 
                else if (itemComment.includes(search)) results.push({ item: item, score: 3 }); 
            }
        }
        results.sort(function(a, b) { if (a.score !== b.score) return a.score - b.score; return a.item.name.localeCompare(b.item.name); });
        for (var k = 0; k < results.length; k++) { filteredModel.append(results[k].item); }
        appGrid.currentIndex = 0;
    }

    function executeApp(cmd, name) {
        if (!cmd || cmd === "") return;

        if (cmd === "qs_sys") { launcherWindow.currentMode = 4; launcherWindow.activeHeaderButton = 0; searchInput.text = ""; loadTabData("--system"); return; }
        if (cmd === "qs_wifi") { launcherWindow.currentMode = 5; launcherWindow.activeHeaderButton = 0; searchInput.text = ""; loadTabData("--wifi"); return; }
        if (cmd === "qs_bt") { launcherWindow.currentMode = 6; launcherWindow.activeHeaderButton = 0; searchInput.text = ""; loadTabData("--bt"); return; }
        
        if (cmd.startsWith("qs_wifi_pass:")) { 
            targetWifiSsid = cmd.substring(13); 
            launcherWindow.currentMode = 9; 
            searchInput.text = ""; 
            searchInput.echoMode = TextInput.Password; 
            return; 
        }

        if (cmd.startsWith("qs_keep:")) {
            var keepCmd = cmd.substring(8);
            execProc.running = false; 
            
            if (keepCmd.indexOf("nmcli") !== -1) {
                launcherWindow.requestIslandMsg("", "white", "Trying to connect to " + name + "...");
                netConnectProc.targetName = name; 
                netConnectProc.command = ["/bin/bash", "-c", keepCmd]; 
                netConnectProc.running = true;
            } else if (keepCmd.indexOf("bluetoothctl") !== -1) {
                if (keepCmd.indexOf("connect") !== -1 && keepCmd.indexOf("disconnect") === -1) {
                    launcherWindow.requestIslandMsg("", "white", "Trying to connect to " + name + "...");
                    btConnectProc.targetName = name;
                    btConnectProc.command = ["/bin/bash", "-c", "rfkill unblock bluetooth; " + keepCmd];
                    btConnectProc.running = true;
                } else if (keepCmd.indexOf("disconnect") !== -1) {
                    launcherWindow.requestIslandMsg("", "white", "Disconnecting " + name + "...");
                    execProc.command = ["/bin/bash", "-c", keepCmd];
                    execProc.running = true;
                } else {
                    execProc.command = ["/bin/bash", "-c", "rfkill unblock bluetooth 2>/dev/null; " + keepCmd];
                    execProc.running = true;
                }
            }
            refreshTimer.start(); 
            return;
        }

        execProc.command = ["/bin/bash", "-c", "echo '" + name + "' >> ~/.cache/qs_recents"];
        execProc.running = true;

        var cleanCmd = cmd.replace(/%[fFuUdDnNickvm]/g, "").replace("~", "/home/javier");
        
        WlrLayershell.keyboardFocus = WlrLayershell.None;
        execProc.running = false; 
        execProc.command = ["hyprctl", "dispatch", "exec", "--", "bash -c \"" + cleanCmd + " && hyprctl dispatch warpcursor 50 50\""];
        execProc.running = true;

        toggle(); 
    }

    function toggle() {
        if (visible_state) {
            visible_state = false;
            closeTimer.start();
        } else {
            isReallyVisible = true;
            visible_state = true;
            WlrLayershell.keyboardFocus = WlrLayershell.OnDemand; 
            searchInput.forceActiveFocus();
        }
    }
}