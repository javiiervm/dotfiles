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
    property string calcResult: "" // <-- Variable para guardar el resultado dinámico
    
    signal requestIslandMsg(string icon, string color, string text)

    // ==========================================
    // CONFIGURACIÓN DE LA VENTANA (WAYLAND)
    // ==========================================
    anchors { 
        top: true; bottom: true; left: true; right: true 
    }

    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: isReallyVisible ? WlrLayershell.OnDemand : WlrLayershell.None

    visible: isReallyVisible
    color: "transparent"

    // ==========================================
    // MODELOS DE DATOS
    // ==========================================
    ListModel { id: rawModel }
    ListModel { id: filteredModel }

    // ==========================================
    // CARGA INICIAL
    // ==========================================
    Component.onCompleted: {
        loadTabData("--apps");
    }

    MouseArea {
        anchors.fill: parent
        onClicked: { if (visible_state) toggle(); }
    }

    Timer {
        id: closeTimer
        interval: 300
        onTriggered: {
            isReallyVisible = false;
            searchInput.text = "";
            loadTabData("--apps"); 
        }
    }

    // ==========================================
    // PROCESOS EN SEGUNDO PLANO
    // ==========================================
    Process {
        id: dataLoader
        stdout: SplitParser {
            onRead: (line) => {
                if (!line || line.trim() === "") return;
                var f = line.split("|");
                if (f.length >= 5) {
                    rawModel.append({ name: f[0], comment: f[1], icon: f[2], exec: f[3], type: f[4] });
                }
            }
        }
        onExited: updateFilter()
    }

    Process { id: execProc }

    // ==========================================
    // INTERFAZ VISUAL (UI)
    // ==========================================
    Rectangle {
        id: mainCard
        
        width: 720
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
            // 1. BARRA DE BÚSQUEDA (Top, Estilo Píldora)
            // ------------------------------------------
            Rectangle {
                width: parent.width
                height: 50
                radius: height / 2
                color: Qt.alpha(Theme.white, 0.05)
                border.color: Qt.alpha(Theme.white, 0.15)
                border.width: 1

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    spacing: 12

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: ""
                        font.family: Theme.fontIcons
                        color: Theme.grey1
                        font.pixelSize: 18
                    }

                    TextInput {
                        id: searchInput
                        width: parent.width - 32
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.white
                        font.pixelSize: 16
                        selectionColor: Theme.blue
                        selectedTextColor: Theme.bg0
                        clip: true

                        Text {
                            text: "Search Applications..."
                            color: Theme.grey1
                            font.pixelSize: 16
                            anchors.verticalCenter: parent.verticalCenter
                            visible: searchInput.text === ""
                        }

                        onTextChanged: updateFilter()

                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Escape) {
                                toggle();
                                event.accepted = true;
                            }
                            
                            // NAVEGACIÓN EN CUADRÍCULA
                            if (event.key === Qt.Key_Down && launcherWindow.calcResult === "") { appGrid.moveCurrentIndexDown(); event.accepted = true; }
                            if (event.key === Qt.Key_Up && launcherWindow.calcResult === "") { appGrid.moveCurrentIndexUp(); event.accepted = true; }
                            if (event.key === Qt.Key_Right && launcherWindow.calcResult === "") { appGrid.moveCurrentIndexRight(); event.accepted = true; }
                            if (event.key === Qt.Key_Left && launcherWindow.calcResult === "") { appGrid.moveCurrentIndexLeft(); event.accepted = true; }

                            // EJECUCIÓN (Copiar cálculo o Abrir app)
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                if (launcherWindow.calcResult !== "") {
                                    // 1. Si hay cálculo, copiar a portapapeles
                                    execProc.command = ["/bin/bash", "-c", "wl-copy '" + launcherWindow.calcResult + "' && notify-send 'Calculator' 'Copied: " + launcherWindow.calcResult + "' -i accessories-calculator"];
                                    execProc.running = true;
                                    toggle();
                                } else if (filteredModel.count > 0 && appGrid.currentIndex >= 0) {
                                    // 2. Si hay app, ejecutar app
                                    var item = filteredModel.get(appGrid.currentIndex);
                                    executeApp(item.exec, item.name);
                                }
                                event.accepted = true;
                            }
                        }
                    }
                }
            }

            // ------------------------------------------
            // 2. CUADRÍCULA DE APLICACIONES
            // ------------------------------------------
            GridView {
                id: appGrid
                width: parent.width
                model: filteredModel
                
                cellWidth: parent.width / 6
                cellHeight: 110
                height: Math.min(Math.ceil(count / 6) * cellHeight, 440)
                
                currentIndex: 0
                clip: true
                // Ocultar si estamos mostrando un resultado matemático
                visible: count > 0 && launcherWindow.calcResult === ""

                delegate: Rectangle {
                    width: appGrid.cellWidth - 10
                    height: appGrid.cellHeight - 10
                    anchors.margins: 5
                    radius: 14
                    color: GridView.isCurrentItem ? Qt.alpha(Theme.white, 0.15) : "transparent"

                    Column {
                        anchors.centerIn: parent
                        spacing: 8
                        
                        Image {
                            width: 56
                            height: 56
                            anchors.horizontalCenter: parent.horizontalCenter
                            source: icon.startsWith("/") ? "file://" + icon : "image://icon/" + icon
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                        
                        Text {
                            width: parent.width - 10
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: name
                            color: Theme.white
                            font.pixelSize: 12
                            font.family: Theme.fontMain
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.WordWrap
                        }
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { appGrid.currentIndex = index; executeApp(exec, name); }
                    }
                }
            }

            // ------------------------------------------
            // 3. TARJETA DE RESULTADO MATEMÁTICO (Nueva)
            // ------------------------------------------
            Rectangle {
                width: parent.width
                height: 75
                radius: 16
                color: Qt.alpha(Theme.white, 0.05)
                border.color: Qt.alpha(Theme.white, 0.15)
                border.width: 1
                visible: launcherWindow.calcResult !== ""

                Row {
                    anchors.fill: parent
                    anchors.margins: 15
                    spacing: 15

                    Rectangle {
                        width: 45; height: 45
                        radius: 12
                        color: Theme.blue
                        anchors.verticalCenter: parent.verticalCenter
                        
                        Text {
                            anchors.centerIn: parent
                            text: ""
                            font.family: Theme.fontIcons
                            color: Theme.bg0
                            font.pixelSize: 22
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        
                        Text {
                            text: launcherWindow.calcResult
                            color: Theme.white
                            font.pixelSize: 24
                            font.bold: true
                        }
                        Text {
                            text: "Press Enter to copy to clipboard"
                            color: Theme.grey1
                            font.pixelSize: 12
                        }
                    }
                }
            }
            
            // ------------------------------------------
            // 4. TEXTO VACÍO (Si no hay resultados)
            // ------------------------------------------
            Item {
                width: parent.width
                height: 60
                // Ocultar si estamos mostrando un resultado matemático
                visible: filteredModel.count === 0 && searchInput.text !== "" && launcherWindow.calcResult === ""
                
                Text {
                    anchors.centerIn: parent
                    text: "No applications found"
                    color: Theme.grey1
                    font.pixelSize: 15
                }
            }
        }
    }

    // ==========================================
    // LÓGICA DE CONTROLADORES
    // ==========================================

    function loadTabData(arg) {
        rawModel.clear();
        dataLoader.command = ["/bin/bash", "/home/javier/.config/quickshell/scripts/provider.sh", arg];
        dataLoader.running = true;
    }

    function updateFilter() {
        var search = searchInput.text.toLowerCase().trim();
        filteredModel.clear();
        launcherWindow.calcResult = "";

        // --- DETECTOR MATEMÁTICO EN TIEMPO REAL ---
        // Verifica si la cadena contiene solo números, puntos, paréntesis y operadores, 
        // exigiendo que al menos haya un operador para evitar confundirlo con apps que sean solo números
        if (search !== "" && /^[0-9+\-*/().\s]+$/.test(search) && /[+\-*/]/.test(search)) {
            try {
                // Limpieza preventiva contra inyección
                var cleanMath = search.replace(/[^-()\d/*+.]/g, ''); 
                var res = Function('"use strict";return (' + cleanMath + ')')();
                
                if (res !== undefined && !isNaN(res)) {
                    launcherWindow.calcResult = res.toString();
                    return; // Detenemos la búsqueda de apps, ya tenemos un cálculo
                }
            } catch(e) {}
        }

        var results = [];

        for (var i = 0; i < rawModel.count; i++) {
            var item = rawModel.get(i);
            if (item.type === "dummy") continue; 
            
            var itemName = item.name.toLowerCase();
            var itemComment = item.comment.toLowerCase();
            
            if (search === "") {
                results.push({ item: item, score: 0 });
            } else {
                if (itemName.startsWith(search)) results.push({ item: item, score: 1 }); 
                else if (itemName.includes(search)) results.push({ item: item, score: 2 }); 
                else if (itemComment.includes(search)) results.push({ item: item, score: 3 }); 
            }
        }

        results.sort(function(a, b) {
            if (a.score !== b.score) return a.score - b.score;
            return a.item.name.localeCompare(b.item.name);
        });

        for (var j = 0; j < results.length; j++) {
            filteredModel.append(results[j].item);
        }
        
        appGrid.currentIndex = 0;
    }

    function executeApp(cmd, name) {
        if (!cmd || cmd === "") return;

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