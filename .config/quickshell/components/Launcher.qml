import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".."

PanelWindow {
    id: launcherWindow

    // ==========================================
    // PROPIEDADES DE ESTADO
    // ==========================================
    property bool visible_state: false
    property bool isReallyVisible: false
    signal requestIslandMsg(string icon, string color, string text)
    
    // Modos del menú:
    // 0:Apps, 1:Files, 2:Term, 3:Web Search
    // 4:System, 5:Wifi, 6:Bluetooth, 7:Wallpapers, 8:Calculadora
    // 9:Wifi (Contraseña), 10:Bluetooth (Dispositivo), 11:Wifi (Manual)
    property int currentMode: 0 
    
    // Variables temporales para submenús
    property string targetWifiSsid: ""
    property string targetBtMac: ""
    property string targetBtName: ""

    // Nombres y argumentos de las pestañas principales
    property var tabArgs: ["--apps", "--files", "--run", ""]
    property var tabNames: ["󰀻   Apps", "   Files", "   Terminal", "   Web Search"]

    // ==========================================
    // CONFIGURACIÓN DE LA VENTANA (WAYLAND)
    // ==========================================
    anchors { 
        top: true 
        bottom: true 
        left: true 
        right: true 
    }

    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.exclusiveZone: -1
    
    // Solo roba el foco del teclado cuando el menú está visible
    WlrLayershell.keyboardFocus: isReallyVisible ? WlrLayershell.OnDemand : WlrLayershell.None

    visible: isReallyVisible
    color: "transparent"

    // ==========================================
    // MODELOS DE DATOS
    // ==========================================
    ListModel { id: rawModel }
    ListModel { id: filteredModel }
    ListModel { id: wallpaperModel }

    // ==========================================
    // CARGA INICIAL (PRE-LOADER)
    // ==========================================
    Component.onCompleted: {
        loadTabData("--apps");
        wallLoader.running = true; // Carga asíncrona de wallpapers al iniciar
    }

    // Clic fuera del menú para cerrar
    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (visible_state) {
                toggle();
            }
        }
    }

    // ==========================================
    // TEMPORIZADORES (TIMERS)
    // ==========================================
    // Temporizador para la animación de cierre suave
    Timer {
        id: closeTimer
        interval: 300
        onTriggered: {
            isReallyVisible = false;
            launcherWindow.currentMode = 0;
            searchInput.text = "";
            searchInput.echoMode = TextInput.Normal;
            loadTabData("--apps"); 
        }
    }

    // Temporizador para refrescar submenús sin cerrarlos (Wi-Fi, Bluetooth)
    Timer {
        id: refreshTimer
        interval: 800
        onTriggered: {
            if (launcherWindow.currentMode === 5) {
                loadTabData("--wifi");
            } else if (launcherWindow.currentMode === 6) {
                loadTabData("--bt");
            } else if (launcherWindow.currentMode === 10) {
                loadTabData("--bt_device", targetBtMac);
            }
        }
    }

    // ==========================================
    // PROCESOS EN SEGUNDO PLANO (BASH)
    // ==========================================
    // Proceso específico para leer los wallpapers
    Process {
        id: wallLoader
        command: ["/bin/bash", "-c", "/home/javier/.config/quickshell/scripts/provider.sh --wallpaper"]
        stdout: SplitParser {
            onRead: (line) => {
                if (!line || line.trim() === "") return;
                var f = line.split("|");
                if (f.length >= 5) {
                    wallpaperModel.append({ 
                        name: f[0], 
                        comment: f[1], 
                        icon: f[2], 
                        exec: f[3], 
                        type: f[4] 
                    });
                }
            }
        }
    }

    // Proceso principal para cargar el resto de datos
    Process {
        id: dataLoader
        stdout: SplitParser {
            onRead: (line) => {
                if (!line || line.trim() === "") return;
                var f = line.split("|");
                if (f.length >= 5) {
                    rawModel.append({ 
                        name: f[0], 
                        comment: f[1], 
                        icon: f[2], 
                        exec: f[3], 
                        type: f[4] 
                    });
                }
            }
        }
        onExited: updateFilter()
    }

    // Proceso para ejecutar las aplicaciones finales
    Process { 
        id: execProc 
    }

    // Proceso para ejecutar conexiones de red de forma asíncrona
    Process {
        id: netConnectProc
        property string targetName: ""
        property string targetType: "" // "WIFI" o "BT"
        
        // Usamos la función clásica para atrapar el código de salida exacto
        onExited: function(exitCode) {
            var success = (exitCode === 0);
            var icon = targetType === "WIFI" ? "" : "";
            var color = success ? "#30d158" : "#ff3b30";
            var status = success ? "Connected to " : "Failed to connect to ";
            
            // Usamos la señal correcta que ya tienes declarada arriba
            launcherWindow.requestIslandMsg(icon, color, status + targetName);
        }
    }

    // ==========================================
    // INTERFAZ VISUAL (UI)
    // ==========================================
    Rectangle {
        id: mainCard
        width: 720
        height: contentColumn.height + 40
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 20
        radius: 16
        
        color: Qt.alpha(Theme.bg0, 0.95)
        border.color: Qt.alpha(Theme.white, 0.1)
        border.width: 1

        // ANIMACIÓN SIMÉTRICA (Entrada y Salida)
        transform: Translate {
            y: launcherWindow.visible_state ? 0 : 50
            Behavior on y { 
                NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } 
            }
        }
        opacity: launcherWindow.visible_state ? 1 : 0
        Behavior on opacity { 
            NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } 
        }

        // Bloquear clics fantasma detrás del menú
        MouseArea { 
            anchors.fill: parent 
        }

        Column {
            id: contentColumn
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 20
            spacing: 15

            // ------------------------------------------
            // 1. PESTAÑAS (TABS)
            // ------------------------------------------
            Row {
                width: parent.width
                height: launcherWindow.currentMode > 3 ? 0 : 40
                spacing: 10
                visible: launcherWindow.currentMode <= 3

                Repeater {
                    model: tabNames
                    delegate: Rectangle {
                        width: (parent.width - 30) / 4
                        height: 40
                        radius: 10
                        color: index === launcherWindow.currentMode ? Qt.alpha(Theme.white, 0.15) : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: index === launcherWindow.currentMode ? Theme.white : Theme.grey1
                            font.pixelSize: 14
                            font.bold: index === launcherWindow.currentMode
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                launcherWindow.currentMode = index;
                                searchInput.text = "";
                                loadTabData(tabArgs[index]);
                                searchInput.forceActiveFocus();
                            }
                        }
                    }
                }
            }

            // ------------------------------------------
            // 2. BOTÓN DE RETROCESO (BACK BUTTON)
            // ------------------------------------------
            Rectangle {
                width: parent.width
                height: launcherWindow.currentMode > 3 && launcherWindow.currentMode !== 9 && launcherWindow.currentMode !== 11 ? 40 : 0
                radius: 10
                color: Qt.alpha(Theme.white, 0.1)
                visible: launcherWindow.currentMode > 3 && launcherWindow.currentMode !== 9 && launcherWindow.currentMode !== 11

                Row {
                    anchors.centerIn: parent
                    spacing: 10
                    Text { 
                        text: ""
                        font.family: Theme.fontIcons
                        color: Theme.white
                        font.pixelSize: 14 
                    }
                    Text { 
                        text: (launcherWindow.currentMode === 10 ? "Back to Bluetooth" : "Back to Main Menu")
                        color: Theme.white
                        font.pixelSize: 14
                        font.bold: true 
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (launcherWindow.currentMode === 10) {
                            launcherWindow.currentMode = 6;
                            loadTabData("--bt");
                        } else {
                            launcherWindow.currentMode = 0;
                            searchInput.text = "";
                            loadTabData("--apps");
                            searchInput.forceActiveFocus();
                        }
                    }
                }
            }

            // ------------------------------------------
            // 3. LISTA NORMAL (Apps, Files, Terminal, System...)
            // ------------------------------------------
            ListView {
                id: appList
                width: parent.width
                
                // Optmización cero lag: Leer directamente el modelo en bruto si no hay búsqueda
                property int itemCount: (searchInput.text === "" && launcherWindow.currentMode !== 8) ? rawModel.count : filteredModel.count
                model: (searchInput.text === "" && launcherWindow.currentMode !== 8) ? rawModel : filteredModel
                
                height: Math.min(itemCount * 55, 420)
                currentIndex: 0
                clip: true
                spacing: 0
                
                visible: launcherWindow.currentMode !== 3 && launcherWindow.currentMode !== 7 && launcherWindow.currentMode !== 9 && launcherWindow.currentMode !== 11 && itemCount > 0

                delegate: Rectangle {
                    width: appList.width
                    height: type === "dummy" ? 40 : 55
                    radius: 10
                    color: (type !== "dummy" && ListView.isCurrentItem) ? Theme.blue : "transparent"

                    // ESTILO DUMMY (Títulos separadores, no clickeables)
                    Item {
                        anchors.fill: parent
                        visible: type === "dummy"
                        Text { 
                            anchors.centerIn: parent
                            text: name
                            color: Theme.blue
                            font.pixelSize: 13
                            font.bold: true 
                        }
                    }

                    // ESTILO NORMAL (Apps, archivos, etc.)
                    Row {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 15
                        visible: type !== "dummy"

                        Image {
                            width: 32
                            height: 32
                            anchors.verticalCenter: parent.verticalCenter
                            fillMode: Image.PreserveAspectCrop
                            source: icon.startsWith("/") ? "file://" + icon : "image://icon/" + icon
                        }

                        Column {
                            width: parent.width - 47
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                width: parent.width
                                text: name
                                color: ListView.isCurrentItem ? Theme.bg0 : Theme.white
                                font.pixelSize: 15
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: comment
                                // Contraste perfecto para la descripción al estar seleccionado
                                color: ListView.isCurrentItem ? Qt.rgba(0, 0, 0, 0.65) : Theme.grey1
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                visible: text !== ""
                            }
                        }
                    }

                    MouseArea { 
                        anchors.fill: parent
                        enabled: type !== "dummy"
                        onClicked: { 
                            appList.currentIndex = index; 
                            executeApp(exec, name); 
                        } 
                    }
                }
            }

            // ------------------------------------------
            // 4. CUADRÍCULA DE WALLPAPERS (Sin Lag)
            // ------------------------------------------
            GridView {
                id: wallGrid
                width: parent.width
                
                property int itemCount: searchInput.text === "" ? wallpaperModel.count : filteredModel.count
                model: searchInput.text === "" ? wallpaperModel : filteredModel
                
                height: Math.min(Math.ceil(itemCount / 5) * 135, 405)
                currentIndex: 0
                clip: true
                cellWidth: parent.width / 5
                cellHeight: 135
                
                visible: launcherWindow.currentMode === 7 && itemCount > 0

                delegate: Rectangle {
                    width: wallGrid.cellWidth - 10
                    height: wallGrid.cellHeight - 10
                    radius: 12
                    color: wallGrid.currentIndex === index ? Theme.blue : "transparent"

                    Column {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8
                        
                        Rectangle {
                            width: parent.width
                            height: parent.height - 25
                            radius: 8
                            clip: true
                            
                            Image {
                                anchors.fill: parent
                                source: "file://" + icon
                                fillMode: Image.PreserveAspectCrop
                                // FIX: Carga asíncrona a baja resolución para matar el lag 4K
                                asynchronous: true
                                sourceSize.width: 250
                                sourceSize.height: 150
                            }
                        }
                        
                        Text {
                            width: parent.width
                            text: name
                            color: wallGrid.currentIndex === index ? Theme.bg0 : Theme.white
                            font.pixelSize: 12
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea { 
                        anchors.fill: parent
                        onClicked: { 
                            wallGrid.currentIndex = index; 
                            executeApp(exec, name); 
                        } 
                    }
                }
            }

            // ------------------------------------------
            // 5. TEXTO DE AYUDA (Estados Vacíos)
            // ------------------------------------------
            Item {
                width: parent.width
                height: 60
                visible: launcherWindow.currentMode !== 0 && launcherWindow.currentMode !== 3 && launcherWindow.currentMode !== 7 && launcherWindow.currentMode !== 8 && launcherWindow.currentMode !== 9 && launcherWindow.currentMode !== 11 && appList.itemCount === 0 && searchInput.text === ""
                
                Text {
                    anchors.centerIn: parent
                    text: {
                        if (launcherWindow.currentMode === 1) return "Type a path to open...";
                        if (launcherWindow.currentMode === 2) return "Type a command to run...";
                        return "";
                    }
                    color: Theme.grey1
                    font.pixelSize: 15
                }
            }

            // ------------------------------------------
            // 6. BARRA DE BÚSQUEDA (Y COMANDOS DE TECLADO)
            // ------------------------------------------
            Rectangle {
                width: parent.width
                height: 50
                radius: 12
                color: Theme.bg1
                border.color: Qt.alpha(Theme.white, 0.1)
                border.width: 1

                Row {
                    anchors.fill: parent
                    anchors.margins: 15
                    spacing: 10

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: ""
                        font.family: Theme.fontIcons
                        color: Theme.grey1
                        font.pixelSize: 18
                    }

                    TextInput {
                        id: searchInput
                        width: parent.width - 30
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.white
                        font.pixelSize: 16
                        selectionColor: Theme.blue
                        selectedTextColor: Theme.bg0
                        clip: true

                        // Texto Placeholder dinámico
                        Text {
                            text: {
                                if (launcherWindow.currentMode === 0) return "Search Apps...";
                                if (launcherWindow.currentMode === 1) return "Search Files...";
                                if (launcherWindow.currentMode === 2) return "Run Command...";
                                if (launcherWindow.currentMode === 3) return "Search the Web...";
                                if (launcherWindow.currentMode === 7) return "Search Wallpapers...";
                                if (launcherWindow.currentMode === 8) return "Type a math expression (e.g. 2+2)...";
                                if (launcherWindow.currentMode === 9) return "Password for " + targetWifiSsid;
                                if (launcherWindow.currentMode === 11) return "Type hidden SSID name...";
                                return "Filter options...";
                            }
                            color: Theme.grey1
                            font.pixelSize: 16
                            anchors.verticalCenter: parent.verticalCenter
                            visible: searchInput.text === ""
                        }

                        onTextChanged: updateFilter()

                        // ------------------------------------------
                        // GESTIÓN COMPLETA DEL TECLADO
                        // ------------------------------------------
                        Keys.onPressed: (event) => {
                            // CERRAR CON ESCAPE
                            if (event.key === Qt.Key_Escape) {
                                if (launcherWindow.currentMode === 9 || launcherWindow.currentMode === 11) {
                                    launcherWindow.currentMode = 5;
                                    searchInput.echoMode = TextInput.Normal;
                                    searchInput.text = "";
                                    loadTabData("--wifi");
                                } else if (launcherWindow.currentMode === 10) {
                                    launcherWindow.currentMode = 6;
                                    searchInput.text = "";
                                    loadTabData("--bt");
                                } else if (launcherWindow.currentMode > 3) {
                                    launcherWindow.currentMode = 0;
                                    searchInput.text = "";
                                    loadTabData("--apps");
                                } else {
                                    toggle();
                                }
                                event.accepted = true;
                            }
                            
                            // RETROCESO RÁPIDO CON BACKSPACE
                            if (event.key === Qt.Key_Backspace && searchInput.text === "" && launcherWindow.currentMode > 3) {
                                if (launcherWindow.currentMode === 9 || launcherWindow.currentMode === 11) { 
                                    launcherWindow.currentMode = 5; 
                                    searchInput.echoMode = TextInput.Normal; 
                                    loadTabData("--wifi"); 
                                } else if (launcherWindow.currentMode === 10) { 
                                    launcherWindow.currentMode = 6; 
                                    loadTabData("--bt"); 
                                } else { 
                                    launcherWindow.currentMode = 0; 
                                    loadTabData("--apps"); 
                                }
                                event.accepted = true;
                            }
                            
                            // NAVEGACIÓN EN LISTAS NORMALES (Ignorando los dummys)
                            if (launcherWindow.currentMode !== 7 && launcherWindow.currentMode !== 9 && launcherWindow.currentMode !== 11) {
                                var modelToUse = (searchInput.text === "" && launcherWindow.currentMode !== 8) ? rawModel : filteredModel;
                                
                                if (event.key === Qt.Key_Down) {
                                    do { 
                                        appList.incrementCurrentIndex(); 
                                    } while (modelToUse.get(appList.currentIndex).type === "dummy" && appList.currentIndex < modelToUse.count - 1);
                                    event.accepted = true;
                                }
                                
                                if (event.key === Qt.Key_Up) {
                                    do { 
                                        appList.decrementCurrentIndex(); 
                                    } while (modelToUse.get(appList.currentIndex).type === "dummy" && appList.currentIndex > 0);
                                    event.accepted = true;
                                }
                            } 
                            // NAVEGACIÓN EN EL GRID DE WALLPAPERS
                            else if (launcherWindow.currentMode === 7) {
                                if (event.key === Qt.Key_Down) { wallGrid.moveCurrentIndexDown(); event.accepted = true; }
                                if (event.key === Qt.Key_Up) { wallGrid.moveCurrentIndexUp(); event.accepted = true; }
                                if (event.key === Qt.Key_Right && !(event.modifiers & Qt.ShiftModifier)) { wallGrid.moveCurrentIndexRight(); event.accepted = true; }
                                if (event.key === Qt.Key_Left && !(event.modifiers & Qt.ShiftModifier)) { wallGrid.moveCurrentIndexLeft(); event.accepted = true; }
                            }

                            // CAMBIO DE PESTAÑAS (Shift + Flechas)
                            if (event.modifiers & Qt.ShiftModifier) {
                                if (event.key === Qt.Key_Right && launcherWindow.currentMode <= 3) {
                                    launcherWindow.currentMode = (launcherWindow.currentMode + 1) % 4;
                                    loadTabData(tabArgs[launcherWindow.currentMode]);
                                    event.accepted = true;
                                }
                                if (event.key === Qt.Key_Left && launcherWindow.currentMode <= 3) {
                                    launcherWindow.currentMode = (launcherWindow.currentMode + 3) % 4;
                                    loadTabData(tabArgs[launcherWindow.currentMode]);
                                    event.accepted = true;
                                }
                            }

                            // EJECUCIÓN (Enter o Return)
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                if (launcherWindow.currentMode === 9) {
                                    // 1. Notificamos inmediatamente por señal nativa
                                    launcherWindow.requestIslandMsg("", "white", "Trying to connect to " + targetWifiSsid + "...");
                                    
                                    // 2. Lanzamos la conexión real
                                    netConnectProc.targetName = targetWifiSsid;
                                    netConnectProc.targetType = "WIFI";
                                    netConnectProc.command = ["/bin/bash", "-c", "nmcli device wifi connect '" + targetWifiSsid + "' password '" + searchInput.text + "'"];
                                    netConnectProc.running = true;

                                    searchInput.echoMode = TextInput.Normal;
                                    searchInput.text = "";
                                    launcherWindow.currentMode = 5;
                                    refreshTimer.start();
                                } else if (launcherWindow.currentMode === 11) {
                                    targetWifiSsid = searchInput.text;
                                    launcherWindow.currentMode = 9;
                                    searchInput.text = "";
                                    searchInput.echoMode = TextInput.Password;
                                } else if (launcherWindow.currentMode === 3 && searchInput.text !== "") {
                                    executeApp("firefox 'https://duckduckgo.com/?q=" + encodeURIComponent(searchInput.text) + "'", "Web Search");
                                } else {
                                    var activeModel = launcherWindow.currentMode === 7 ? wallGrid.model : appList.model;
                                    var activeIndex = launcherWindow.currentMode === 7 ? wallGrid.currentIndex : appList.currentIndex;
                                    
                                    if (activeModel && activeModel.count > 0 && activeIndex >= 0) {
                                        var item = activeModel.get(activeIndex);
                                        if (launcherWindow.currentMode === 2) {
                                            executeApp("kitty -e bash -c '" + item.exec + " ; read -p \"Press Enter to close\"'", item.name);
                                        } else {
                                            executeApp(item.exec, item.name);
                                        }
                                    }
                                }
                                event.accepted = true;
                            }
                        }
                    }
                }
            }
        }
    }

    // ==========================================
    // LÓGICA DE CONTROLADORES
    // ==========================================

    function loadTabData(arg, extraArg = "") {
        if (arg === "--calc" || arg === "--wallpaper") return; 
        
        rawModel.clear();
        filteredModel.clear();

        if (arg !== "") {
            var cmd = ["/bin/bash", "/home/javier/.config/quickshell/scripts/provider.sh", arg];
            if (extraArg !== "") {
                cmd.push(extraArg);
            }
            dataLoader.command = cmd;
            dataLoader.running = true;
        }
    }

    function updateFilter() {
        var search = searchInput.text.toLowerCase().trim();

        // 1. MODO CALCULADORA EN TIEMPO REAL
        if (launcherWindow.currentMode === 8) {
            filteredModel.clear();
            if (search !== "") {
                try {
                    // Evita la ejecución de comandos dañinos
                    var cleanMath = search.replace(/[^-()\d/*+.]/g, ''); 
                    var res = Function('"use strict";return (' + cleanMath + ')')();
                    if (res !== undefined && !isNaN(res)) {
                        filteredModel.append({
                            name: res.toString(),
                            comment: "Press Enter to copy to clipboard",
                            icon: "accessories-calculator",
                            exec: "wl-copy '" + res + "' && notify-send 'Calculator' 'Copied to clipboard: " + res + "'",
                            type: "calc"
                        });
                    }
                } catch(e) {}
            }
            return;
        }

        // 2. SIN BÚSQUEDA (Caché directa)
        if (search === "") {
            var mToUse = (launcherWindow.currentMode === 7) ? wallpaperModel : rawModel;
            // Salta los dummys automáticamente
            if (mToUse.count > 0 && mToUse.get(0).type === "dummy") { 
                appList.currentIndex = 1; 
            } else { 
                appList.currentIndex = 0; 
                wallGrid.currentIndex = 0; 
            }
            return;
        }

        // 3. CON BÚSQUEDA: Scoring, Filtro ">" y Ordenación
        filteredModel.clear();
        var source = (launcherWindow.currentMode === 7) ? wallpaperModel : rawModel;
        var results = [];
        
        var isCmdSearch = search.startsWith(">");
        var actualSearch = isCmdSearch ? search.substring(1).trim() : search;

        for (var i = 0; i < source.count; i++) {
            var item = source.get(i);
            
            if (item.type === "dummy") continue; 
            
            // Si el usuario pone ">", descartar lo que no sea comando
            if (isCmdSearch && item.type !== "cmd") continue;
            
            var itemName = item.name.toLowerCase();
            var itemComment = item.comment.toLowerCase();
            
            if (actualSearch === "") {
                // Si solo pone ">", mostramos todos los comandos inmediatamente
                if (isCmdSearch) {
                    results.push({ item: item, score: 1 });
                }
            } else {
                // Sistema de prioridades (Scoring)
                if (itemName.startsWith(actualSearch)) {
                    results.push({ item: item, score: 1 }); 
                } else if (itemName.includes(actualSearch)) {
                    results.push({ item: item, score: 2 }); 
                } else if (itemComment.includes(actualSearch)) {
                    results.push({ item: item, score: 3 }); 
                }
            }
        }

        // Ordenar primero por prioridad (score) y luego alfabéticamente
        results.sort(function(a, b) {
            if (a.score !== b.score) return a.score - b.score;
            return a.item.name.localeCompare(b.item.name);
        });
        
        for (var j = 0; j < results.length; j++) {
            filteredModel.append(results[j].item);
        }
        
        appList.currentIndex = 0;
        wallGrid.currentIndex = 0;
    }

    function executeApp(cmd, name) {
        if (!cmd || cmd === "") return;

        // INTERCEPTOR DE COMANDOS SILENCIOSOS (Actualización sin cierre para Wi-Fi/BT)
        if (cmd.startsWith("qs_keep:")) {
            var keepCmd = cmd.substring(8);
            
            // Atrapa tanto redes nuevas ("connect") como redes guardadas ("up id")
            if (keepCmd.indexOf("nmcli") !== -1 && (keepCmd.indexOf("connect") !== -1 || keepCmd.indexOf("up id") !== -1)) {
                launcherWindow.requestIslandMsg("", "white", "Trying to connect to " + name + "...");
                netConnectProc.targetName = name;
                netConnectProc.targetType = "WIFI";
                netConnectProc.command = ["/bin/bash", "-c", keepCmd];
                netConnectProc.running = true;
            } 
            else if (keepCmd.indexOf("bluetoothctl") !== -1 && keepCmd.indexOf("connect") !== -1) {
                var btDevName = (launcherWindow.currentMode === 10) ? targetBtName : name;
                launcherWindow.requestIslandMsg("", "white", "Trying to connect to " + btDevName + "...");
                
                netConnectProc.targetName = btDevName;
                netConnectProc.targetType = "BT";
                netConnectProc.command = ["/bin/bash", "-c", keepCmd];
                netConnectProc.running = true;
            }
            else {
                execProc.command = ["/bin/bash", "-c", keepCmd];
                execProc.running = true;
            }
            refreshTimer.start(); 
            return;
        }

        // INTERCEPTOR DE NAVEGACIÓN DE DIRECTORIOS
        if (cmd.startsWith("qs_dir:")) {
            var newPath = cmd.substring(7);
            searchInput.text = "";
            loadTabData("--files", newPath);
            return;
        }

        // INTERCEPTORES DE SUBMENÚS
        if (cmd === "qs_sys") { launcherWindow.currentMode = 4; searchInput.text = ""; loadTabData("--system"); return; }
        if (cmd === "qs_wifi") { launcherWindow.currentMode = 5; searchInput.text = ""; loadTabData("--wifi"); return; }
        if (cmd === "qs_wifi_manual") { launcherWindow.currentMode = 11; searchInput.text = ""; return; }
        if (cmd.startsWith("qs_wifi_pass:")) { 
            targetWifiSsid = cmd.substring(13); 
            launcherWindow.currentMode = 9; 
            searchInput.text = ""; 
            searchInput.echoMode = TextInput.Password; 
            return; 
        }
        
        if (cmd === "qs_bt") { launcherWindow.currentMode = 6; searchInput.text = ""; loadTabData("--bt"); return; }
        if (cmd.startsWith("qs_bt_device:")) { 
            targetBtMac = cmd.substring(13); 
            targetBtName = name; 
            launcherWindow.currentMode = 10; 
            searchInput.text = ""; 
            loadTabData("--bt_device", targetBtMac); 
            return; 
        }
        
        if (cmd === "qs_wall") { launcherWindow.currentMode = 7; searchInput.text = ""; return; }
        if (cmd === "qs_calc") { launcherWindow.currentMode = 8; searchInput.text = ""; loadTabData("--calc"); return; }

        // HISTORIAL DE RECIENTES
        if (name && launcherWindow.currentMode === 0) {
            execProc.command = ["/bin/bash", "-c", "echo '" + name + "' >> ~/.cache/qs_recents"];
            execProc.running = true;
        }

        // LIMPIEZA Y EJECUCIÓN VÍA HYPRLAND (Foco garantizado)
        var cleanCmd = cmd.replace(/%[fFuUdDnNickvm]/g, "").replace("~", "/home/javier");
        
        WlrLayershell.keyboardFocus = WlrLayershell.None;
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