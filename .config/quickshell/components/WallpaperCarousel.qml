import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Qt5Compat.GraphicalEffects
import ".."

PanelWindow {
    id: wallCarouselWindow

    property bool visible_state: false
    property bool isReallyVisible: false
    property string wallpaperDir: "~/Pictures/wallpapers"
    
    // Almacena el wallpaper actual para volver a él al limpiar filtros
    property string currentWallPath: ""
    
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

    // El blur se limita exclusivamente a la barra de búsqueda/filtros.
    // Las previews conservan exactamente su transparencia y selección actuales.
    BackgroundEffect.blurRegion: Glass.blurEnabled ? searchPillBlurRegion : null

    Region {
        id: searchPillBlurRegion
        item: topPill
        radius: topPill.radius
    }

    // Antes había una capa translúcida a pantalla completa que oscurecía todo
    // el escritorio (efecto "blur"/glass). Se ha eliminado a petición: ahora
    // el menú aparece directamente sobre el escritorio, sin capa de fondo.

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
        onExited: {
            getCurrentWallProc.running = true;
        }
    }

    Process {
        id: getCurrentWallProc
        command: ["bash", "-c", "cat /home/javier/.cache/qs_wall_path 2>/dev/null || cat /tmp/current_wallpaper 2>/dev/null"]
        stdout: SplitParser {
            onRead: (data) => {
                var currentPath = data.trim().replace("~", "/home/javier");
                if (currentPath === "") return;
                wallCarouselWindow.currentWallPath = currentPath;

                // Reevaluar filtros tras actualizar la ruta para asegurar el índice correcto
                updateFilter();
            }
        }
    }

    Process { id: execProc }

    function updateFilter() {
        filteredModel.clear();
        var searchStr = searchInput.text.toLowerCase().trim();
        var colorName = activeColorFilter !== "" ? colorNames[activeColorFilter] : "";
        var isFilterEmpty = (searchStr === "" && activeColorFilter === "");
        var targetIndex = 0;

        for (var i = 0; i < wallpaperModel.count; i++) {
            var item = wallpaperModel.get(i);
            // Tolerancia a nulos para evitar roturas silenciosas del script
            var itemName = (item.name || "").toLowerCase();
            var itemComment = (item.comment || "").toLowerCase();
            var itemType = (item.type || "").toLowerCase();

            var matchText = (searchStr === "") || itemName.includes(searchStr);
            
            var matchColor = true;
            if (activeColorFilter !== "") {
                // Validación estricta que ahora INCLUYE el nombre del archivo para fallbacks lógicos
                matchColor = itemComment.includes(colorName) || itemComment.includes(activeColorFilter) ||
                             itemType.includes(colorName) || itemType.includes(activeColorFilter) ||
                             itemName.includes(colorName);
            }

            if (matchText && matchColor) {
                filteredModel.append({
                    name: item.name, comment: item.comment, icon: item.icon, exec: item.exec, type: item.type
                });
                
                // Buscar si este fondo filtrado es el actual para restaurar la vista
                var currentItemPath = (item.icon || "").replace("~", "/home/javier");
                if (isFilterEmpty && wallCarouselWindow.currentWallPath !== "" && currentItemPath === wallCarouselWindow.currentWallPath) {
                    targetIndex = filteredModel.count - 1;
                }
            }
        }
        
        /*carousel.currentIndex = targetIndex;
        // Solo desplazamos la vista físicamente si hemos limpiado los filtros y encontrado la coincidencia
        if (isFilterEmpty && targetIndex !== 0) {
            carousel.positionViewAtIndex(targetIndex, ListView.Center);
        }*/
        Qt.callLater(function() {
            carousel.currentIndex = targetIndex;
            if (isFilterEmpty) {
                // Al ejecutarse en el siguiente ciclo, la geometría ya incluye los anchos de 550px
                carousel.positionViewAtIndex(targetIndex, ListView.Center);
            }
        });
    }

    /*function executeWall(cmd, iconPath) {
        if (!cmd || cmd === "") return;
        
        // Actualizamos la ruta actual en memoria instantáneamente
        wallCarouselWindow.currentWallPath = (iconPath || "").replace("~", "/home/javier");

        var syncCmd = "mkdir -p /home/javier/.cache/hyprlock && cp '" + iconPath + "' /home/javier/.cache/hyprlock/current_wallpaper.png && echo '" + iconPath + "' > /home/javier/.cache/qs_wall_path && ";
        var finalCmd = syncCmd + cmd;
        var cleanCmd = finalCmd.replace(/%[fFuUdDnNickvm]/g, "").replace("~", "/home/javier");

        WlrLayershell.keyboardFocus = WlrLayershell.None;
        execProc.running = false;
        execProc.command = ["hyprctl", "dispatch", "exec", "--", "bash -c \"" + cleanCmd + " && hyprctl dispatch warpcursor 50 50\""];
        execProc.running = true;

        toggle();
    }*/
    /*function executeWall(cmd, iconPath) {
        if (!cmd || cmd === "") return;
        
        // Actualizamos la ruta actual en memoria instantáneamente
        wallCarouselWindow.currentWallPath = (iconPath || "").replace("~", "/home/javier");

        var syncCmd = "mkdir -p /home/javier/.cache/hyprlock && cp '" + iconPath + "' /home/javier/.cache/hyprlock/current_wallpaper.png && echo '" + iconPath + "' > /home/javier/.cache/qs_wall_path && ";
        var finalCmd = syncCmd + cmd;
        var cleanCmd = finalCmd.replace(/%[fFuUdDnNickvm]/g, "").replace("~", "/home/javier");

        WlrLayershell.keyboardFocus = WlrLayershell.None;
        execProc.running = false;
        
        // Redirigimos la salida de BASH a un archivo de log temporal para ver qué falla al ejecutarse
        var debugCmd = "(" + cleanCmd + ") > /tmp/qs_wall_debug.log 2>&1";
        console.log("COMANDO EJECUTADO:", debugCmd); // Esto saldrá por la terminal de quickshell
        
        execProc.command = ["hyprctl", "dispatch", "exec", "--", "bash -c \"" + debugCmd + "\""];
        
        execProc.running = true;

        toggle();
    }*/
    function executeWall(cmd, iconPath) {
        if (!cmd || cmd === "") return;
        
        // Actualizamos la ruta actual en memoria instantáneamente
        wallCarouselWindow.currentWallPath = (iconPath || "").replace("~", "/home/javier");

        var syncCmd = "mkdir -p /home/javier/.cache/hyprlock && cp '" + iconPath + "' /home/javier/.cache/hyprlock/current_wallpaper.png && echo '" + iconPath + "' > /home/javier/.cache/qs_wall_path && ";
        var finalCmd = syncCmd + cmd;
        var cleanCmd = finalCmd.replace(/%[fFuUdDnNickvm]/g, "").replace("~", "/home/javier");

        WlrLayershell.keyboardFocus = WlrLayershell.None;
        
        // Ejecutamos la cadena directamente mediante BASH sin pasar por comillas en hyprctl
        execProc.running = false;
        execProc.command = ["/bin/bash", "-c", cleanCmd + " && hyprctl dispatch warpcursor 50 50 >/tmp/qs_wall_debug.log 2>&1"];
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
            
            searchInput.text = "";
            activeColorFilter = "";
            
            // Forzar recarga del último wallpaper y aplicar filtros
            getCurrentWallProc.running = false;
            getCurrentWallProc.running = true;
            
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
            spacing: 15
            
            model: filteredModel
            clip: false
            
            preferredHighlightBegin: parent.width / 2 - 275
            preferredHighlightEnd: parent.width / 2 + 275
            highlightRangeMode: ListView.ApplyRange

            highlightMoveDuration: 250
            // Recicla delegates al hacer scroll en vez de crear/destruirlos.
            // No cambia nada visual, solo reduce trabajo al desplazar la lista.
            reuseItems: true

            // Colchón invisible al principio y al final: sin esto, al llegar al
            // primer o último wallpaper el ListView no tiene más contenido que
            // desplazar y el item seleccionado se queda pegado al borde en vez
            // de centrarse. El ancho es tal que, incluso expandido a 550px,
            // ese item extremo puede llegar exactamente al centro de la ventana.
            header: Item {
                width: Math.max(0, carousel.width / 2 - 275)
                height: 1
            }
            footer: Item {
                width: Math.max(0, carousel.width / 2 - 275)
                height: 1
            }
            
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Left) { decrementCurrentIndex(); event.accepted = true; }
                else if (event.key === Qt.Key_Right) { incrementCurrentIndex(); event.accepted = true; }
                else if (event.key === Qt.Key_Escape) { toggle(); event.accepted = true; }
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    var item = filteredModel.get(currentIndex);
                    if (item) executeWall(item.exec, item.icon);
                    event.accepted = true;
                }
                else if (event.text !== "" && event.key !== Qt.Key_Space && event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backspace) {
                    searchInput.text = event.text;
                    searchInput.forceActiveFocus();
                    searchInput.cursorPosition = searchInput.text.length;
                    event.accepted = true;
                }
            }

            delegate: Item {
                // Ancho dinámico que se expande al enfocar
                width: ListView.isCurrentItem ? 550 : 200 
                height: carousel.height
                z: ListView.isCurrentItem ? 10 : 1
                
                // Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutQuart } }
                Behavior on width { 
                    NumberAnimation { 
                        // Anula la interpolación geométrica mientras el menú se abre para garantizar 
                        // que positionViewAtIndex disponga del contentWidth real.
                        duration: wallCarouselWindow.opacity === 1.0 ? 300 : 0 
                        easing.type: Easing.OutQuart 
                    } 
                }

                Item {
                    anchors.fill: parent
                    // clip: true (Se debe eliminar estrictamente para que la máscara redondeada funcione)

                    // Los wallpapers NO seleccionados quedan ligeramente
                    // transparentes (se deja ver el escritorio a través).
                    opacity: carousel.currentIndex === index ? 1.0 : 0.6
                    Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

                    transform: Matrix4x4 {
                        matrix: Qt.matrix4x4(1, -0.25, 0, 0,
                                            0,     1, 0, 0,
                                            0,     0, 1, 0,
                                            0,     0, 0, 1)
                    }

                    Rectangle {
                        id: maskRect
                        anchors.fill: parent
                        radius: 20 // Valor que define la suavidad del redondeado de las esquinas
                        visible: false
                    }

                    Item {
                        id: contentItem
                        anchors.fill: parent
                        visible: false

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
                            color: Qt.alpha(Theme.bgGlass, 0.4)
                            opacity: carousel.currentIndex === index ? 0.0 : 1.0
                            Behavior on opacity { NumberAnimation { duration: 300 } }
                        }
                    }

                    OpacityMask {
                        anchors.fill: parent
                        source: contentItem
                        maskSource: maskRect
                    }
                    
                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        border.color: carousel.currentIndex === index ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
                        border.width: 1
                        radius: 20 // Debe coincidir obligatoriamente con el radio de maskRect
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

        GlassSurface {
            id: topPill
            anchors.bottom: carousel.top
            anchors.bottomMargin: 40
            anchors.horizontalCenter: parent.horizontalCenter
            width: pillRow.implicitWidth + 40
            height: 44
            glassRadius: 22
            
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 3
                radius: 1.5
                color: activeColorFilter !== "" ? activeColorFilter : "transparent"
                opacity: activeColorFilter !== "" ? 0.6 : 0
                Behavior on color { ColorAnimation { duration: 200 } }
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }

            RowLayout {
                id: pillRow
                anchors.centerIn: parent
                spacing: 12

                Text { text: "󰀻"; color: Theme.grey1; font.pixelSize: 18; font.family: Theme.fontIcons }
                Text { text: "▶"; color: Theme.grey1; font.pixelSize: 12; font.family: Theme.fontIcons }
                
                Row {
                    spacing: 8
                    Repeater {
                        model: ["#ff3b30", "#ff9500", "#ffcc00", "#34c759", "#007aff", "#5856d6", "#ff2d55", "#8e8e93"]
                        Rectangle { 
                            width: 18; height: 18; radius: 9; color: modelData 
                            
                            border.color: Theme.white
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
                
                Text { text: ""; color: Theme.grey1; font.pixelSize: 14; font.family: Theme.fontIcons; Layout.leftMargin: 8 }
                
                TextInput {
                    id: searchInput
                    Layout.preferredWidth: 150
                    Layout.alignment: Qt.AlignVCenter
                    color: Theme.fg
                    font.pixelSize: 15
                    font.family: Theme.fontMain
                    clip: true
                    selectionColor: Theme.blue

                    Text {
                        text: "Search..."
                        color: Theme.grey1
                        font.pixelSize: 15
                        font.family: Theme.fontMain
                        anchors.verticalCenter: parent.verticalCenter
                        visible: searchInput.text === ""
                    }

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
            
            color: filteredModel.count === 0 ? Theme.grey1 : Theme.fg
            font.pixelSize: 20
            font.bold: true
            font.family: Theme.fontMain
            
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