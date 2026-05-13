import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".."

PanelWindow {
    id: wallCarouselWindow

    property bool visible_state: false
    property bool isReallyVisible: false
    property string wallpaperDir: "~/Pictures/wallpapers"
    
    // VARIABLES DE BÚSQUEDA Y FILTRO
    property string activeColorFilter: ""
    property var colorNames: {
        "#ff3b30": "red", "#ff9500": "orange", "#ffcc00": "yellow", 
        "#34c759": "green", "#007aff": "blue", "#5856d6": "purple", 
        "#ff2d55": "pink", "#8e8e93": "gray"
    }

    anchors { 
        top: true 
        bottom: true 
        left: true 
        right: true 
    }
    
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.namespace: "wall_carousel"
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: isReallyVisible ? WlrLayershell.OnDemand : WlrLayershell.None
    
    visible: isReallyVisible
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.25)
        opacity: wallCarouselWindow.visible_state ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    }

    ListModel { id: wallpaperModel }
    ListModel { id: filteredModel } 

    Component.onCompleted: {
        wallLoader.running = true;
    }

    MouseArea {
        anchors.fill: parent
        onClicked: toggle()
    }

    Timer {
        id: closeTimer
        interval: 300
        onTriggered: isReallyVisible = false
    }

    Process {
        id: wallLoader
        command: ["/bin/bash", "-c", "/home/javier/.config/quickshell/scripts/provider.sh --wallpaper " + wallpaperDir]
        stdout: SplitParser {
            onRead: (line) => {
                if (!line || line.trim() === "") return;
                var f = line.split("|");
                if (f.length >= 5) {
                    wallpaperModel.append({ 
                        name: f[0], comment: f[1], icon: f[2], exec: f[3], type: f[4] 
                    });
                }
            }
        }
        onExited: updateFilter()
    }

    // Proceso para leer la ruta del fondo actual desde el archivo persistente
    Process {
        id: getCurrentWallProc
        command: ["bash", "-c", "cat /home/javier/.cache/qs_wall_path 2>/dev/null || cat /tmp/current_wallpaper 2>/dev/null"]
        stdout: SplitParser {
            onRead: (data) => {
                var currentPath = data.trim().replace("~", "/home/javier");
                if (currentPath === "") return;

                // Buscamos en el modelo filtrado qué índice coincide con esta ruta
                for (var i = 0; i < filteredModel.count; i++) {
                    var itemPath = filteredModel.get(i).icon.replace("~", "/home/javier");
                    if (itemPath === currentPath) {
                        carousel.currentIndex = i;
                        // Salta instantáneamente a la imagen sin hacer la animación de scroll inicial
                        carousel.positionViewAtIndex(i, ListView.Center);
                        break;
                    }
                }
            }
        }
    }

    Process { id: execProc }

    function updateFilter() {
        filteredModel.clear();
        var searchStr = searchInput.text.toLowerCase().trim();
        var colorName = activeColorFilter !== "" ? colorNames[activeColorFilter] : "";

        for (var i = 0; i < wallpaperModel.count; i++) {
            var item = wallpaperModel.get(i);
            var itemName = item.name.toLowerCase();
            var itemComment = item.comment.toLowerCase();
            var itemType = item.type ? item.type.toLowerCase() : "";

            // 1. EL BUSCADOR DE TEXTO SOLO MIRA EL NOMBRE
            var matchText = (searchStr === "") || itemName.includes(searchStr);
            
            // 2. EL FILTRO DE COLOR SOLO MIRA EL COMENTARIO O TIPO (Ignora el nombre del archivo)
            var matchColor = true;
            if (activeColorFilter !== "") {
                matchColor = itemComment.includes(colorName) || itemComment.includes(activeColorFilter) ||
                             itemType.includes(colorName) || itemType.includes(activeColorFilter);
            }

            if (matchText && matchColor) {
                filteredModel.append({
                    name: item.name, comment: item.comment, icon: item.icon, exec: item.exec, type: item.type
                });
            }
        }
        carousel.currentIndex = 0;
    }

    function executeWall(cmd, iconPath) {
        if (!cmd || cmd === "") return;
        var syncCmd = "mkdir -p /home/javier/.cache/hyprlock && cp '" + iconPath + "' /home/javier/.cache/hyprlock/current_wallpaper.png && echo '" + iconPath + "' > /home/javier/.cache/qs_wall_path && ";
        var finalCmd = syncCmd + cmd;
        var cleanCmd = finalCmd.replace(/%[fFuUdDnNickvm]/g, "").replace("~", "/home/javier");

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
            
            // 1. Reseteamos filtros
            searchInput.text = "";
            activeColorFilter = "";
            updateFilter();
            
            // 2. Buscamos y seleccionamos el fondo actual
            getCurrentWallProc.running = false;
            getCurrentWallProc.running = true;
            
            // 3. El foco inicial siempre es el carrusel (Modo flechas)
            carousel.forceActiveFocus(); 
        }
    }

    Item {
        anchors.fill: parent
        opacity: wallCarouselWindow.visible_state ? 1 : 0
        transform: Translate {
            y: wallCarouselWindow.visible_state ? 0 : 30
            Behavior on y { NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }
        }
        Behavior on opacity { NumberAnimation { duration: 250 } }

        ListView {
            id: carousel
            anchors.centerIn: parent
            width: parent.width
            height: 320 
            orientation: ListView.Horizontal
            spacing: -81 
            
            model: filteredModel
            clip: false
            
            preferredHighlightBegin: parent.width / 2 - 150
            preferredHighlightEnd: parent.width / 2 + 150
            highlightRangeMode: ListView.StrictlyEnforceRange

            // NUEVO: Acelera drásticamente el tiempo de scroll entre elementos (150ms en vez del defecto)
            highlightMoveDuration: 150
            
            // GESTIÓN DEL TECLADO DEL CARRUSEL (Modo Flechas Activo)
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Left) { decrementCurrentIndex(); event.accepted = true; }
                else if (event.key === Qt.Key_Right) { incrementCurrentIndex(); event.accepted = true; }
                else if (event.key === Qt.Key_Escape) { toggle(); event.accepted = true; }
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    var item = filteredModel.get(currentIndex);
                    if (item) executeWall(item.exec, item.icon);
                    event.accepted = true;
                }
                // Si pulsas una letra/número, salta al buscador y escribe la letra
                else if (event.text !== "" && event.key !== Qt.Key_Space && event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backspace) {
                    searchInput.text = event.text;
                    searchInput.forceActiveFocus();
                    searchInput.cursorPosition = searchInput.text.length;
                    event.accepted = true;
                }
            }

            delegate: Item {
                width: 300 
                height: carousel.height
                z: ListView.isCurrentItem ? 10 : 1
                
                scale: ListView.isCurrentItem ? 1.12 : 1.0
                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

                Item {
                    anchors.fill: parent
                    clip: true
                    
                    transform: Matrix4x4 {
                        matrix: Qt.matrix4x4(1, -0.25, 0, 0,
                                             0,     1, 0, 0,
                                             0,     0, 1, 0,
                                             0,     0, 0, 1)
                    }

                    Image {
                        transform: Matrix4x4 {
                            matrix: Qt.matrix4x4(1, 0.25, 0, 0,
                                                 0,    1, 0, 0,
                                                 0,    0, 1, 0,
                                                 0,    0, 0, 1)
                        }
                        
                        width: parent.width + (parent.height * 0.25) + 160 
                        height: parent.height + 120 
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenterOffset: -40 
                        anchors.verticalCenterOffset: -10   
                        
                        source: "file://" + icon
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 700 
                        sourceSize.height: 500
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: "black"
                        opacity: carousel.currentIndex === index ? 0.0 : 0.65
                        Behavior on opacity { NumberAnimation { duration: 300 } }
                    }
                    
                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        border.color: carousel.currentIndex === index ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
                        border.width: 1
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (carousel.currentIndex === index) {
                            executeWall(exec, icon);
                        } else {
                            carousel.currentIndex = index;
                        }
                    }
                }
            }
        }

        Rectangle {
            id: topPill
            anchors.bottom: carousel.top
            anchors.bottomMargin: 40 
            anchors.horizontalCenter: parent.horizontalCenter
            width: pillRow.implicitWidth + 40
            height: 44 
            radius: 22
            color: Qt.rgba(0.08, 0.08, 0.08, 0.85)
            border.color: Qt.rgba(1, 1, 1, 0.1)
            border.width: 1

            RowLayout {
                id: pillRow
                anchors.centerIn: parent
                spacing: 12

                Text { text: "󰀻"; color: "white"; font.pixelSize: 18; font.family: "Symbols Nerd Font" }
                Text { text: "▶"; color: "gray"; font.pixelSize: 12 }
                
                Row {
                    spacing: 8
                    Repeater {
                        model: ["#ff3b30", "#ff9500", "#ffcc00", "#34c759", "#007aff", "#5856d6", "#ff2d55", "#8e8e93"]
                        Rectangle { 
                            width: 18; height: 18; radius: 9; color: modelData 
                            
                            border.color: "white"
                            border.width: activeColorFilter === modelData ? 2 : 0
                            scale: activeColorFilter === modelData ? 1.2 : 1.0
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    activeColorFilter = (activeColorFilter === modelData) ? "" : modelData;
                                    updateFilter();
                                }
                            }
                        }
                    }
                }
                
                Text { text: ""; color: "gray"; font.pixelSize: 14; font.family: "Symbols Nerd Font"; Layout.leftMargin: 8 }
                
                TextInput {
                    id: searchInput
                    Layout.preferredWidth: 150
                    Layout.alignment: Qt.AlignVCenter
                    color: "white"
                    font.pixelSize: 15
                    clip: true
                    selectionColor: "#007aff"

                    Text {
                        text: "Search..."
                        color: "gray"
                        font.pixelSize: 15
                        anchors.verticalCenter: parent.verticalCenter
                        visible: searchInput.text === ""
                    }

                    // Magia del foco: si se vacía la caja, devolvemos el foco al carrusel
                    onTextChanged: {
                        updateFilter();
                        if (text === "" && activeFocus) {
                            carousel.forceActiveFocus();
                        }
                    }

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Escape) {
                            text = "";
                            carousel.forceActiveFocus();
                            event.accepted = true;
                        }
                        // Navegar con flechas por el carrusel aunque estés editando el texto
                        if (event.key === Qt.Key_Down || event.key === Qt.Key_Right) { 
                            carousel.incrementCurrentIndex(); 
                            event.accepted = true; 
                        }
                        if (event.key === Qt.Key_Up || event.key === Qt.Key_Left) { 
                            carousel.decrementCurrentIndex(); 
                            event.accepted = true; 
                        }
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            var item = filteredModel.get(carousel.currentIndex);
                            if (item) executeWall(item.exec, item.icon);
                            event.accepted = true;
                        }
                    }
                }
            }
        }

        Text {
            anchors.top: carousel.bottom
            anchors.topMargin: 40
            anchors.horizontalCenter: parent.horizontalCenter
            
            text: {
                if (filteredModel.count === 0) return "No wallpapers match this color/name";
                var item = filteredModel.get(carousel.currentIndex);
                return item ? item.name : "";
            }
            
            color: filteredModel.count === 0 ? "gray" : "white"
            font.pixelSize: 20
            font.bold: true
            
            style: Text.Outline
            styleColor: Qt.rgba(0,0,0, 0.5)
            
            Behavior on text { 
                SequentialAnimation {
                    NumberAnimation { target: parent; property: "opacity"; to: 0; duration: 100 }
                    PropertyAction { target: parent; property: "text" }
                    NumberAnimation { target: parent; property: "opacity"; to: 1; duration: 150 }
                }
            }
        }
    }
}