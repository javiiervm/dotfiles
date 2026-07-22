import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import ".."

PanelWindow {
    id: ncWindow

    property bool visible_state: false
    property bool isReallyVisible: false
    property bool dndState: false
    property ListModel modelData

    // --- LÓGICA DE NOTION (Extraída de la Isla Dinámica) ---
    property var notionEventsData: []
    property var selectedDateObj: new Date()
    property string selectedDateString: Qt.formatDateTime(selectedDateObj, "dd MMMM yyyy")
    property var selectedEvents: []

    // Función para cruzar fechas del calendario con el JSON
    function getEventsForDate(date) {
        if (!notionEventsData || notionEventsData.length === 0) return [];
        // Formateamos la fecha al estilo de tu Notion (ej: "16 Jul" o "17 Jul")
        var formatStr1 = Qt.formatDate(date, "d MMM");  
        var formatStr2 = Qt.formatDate(date, "dd MMM"); 
        
        for (var i = 0; i < notionEventsData.length; i++) {
            var dLabel = notionEventsData[i].date_label || "";
            var dayLabel = notionEventsData[i].day_label || "";
            
            // Si el texto del JSON contiene nuestra fecha, devolvemos sus eventos
            if (dLabel.indexOf(formatStr1) !== -1 || dLabel.indexOf(formatStr2) !== -1 ||
                dayLabel.indexOf(formatStr1) !== -1 || dayLabel.indexOf(formatStr2) !== -1) {
                return notionEventsData[i].events;
            }
        }
        return [];
    }

    // Motor que lee el JSON en segundo plano (solo cuando se abre el panel)
    Process {
        id: notionSyncProc
        running: ncWindow.visible_state
        command: [
            "bash", "-c", 
            "source ~/.config/quickshell/secrets.env 2>/dev/null; " +
            "python3 ~/.config/quickshell/scripts/notion_sync.py; " +
            "cat ~/.cache/qs_notion.json 2>/dev/null || echo '{\"header\": \"Not Configured\", \"events\": []}'"
        ]
        stdout: SplitParser {
            onRead: function(data) {
                try {
                    var parsed = JSON.parse(data.trim());
                    ncWindow.notionEventsData = parsed.days || [];
                    
                    // Refrescar los eventos del día seleccionado (hoy) en cuanto llegan los datos
                    if (ncWindow.selectedDateString !== "") {
                        ncWindow.selectedEvents = ncWindow.getEventsForDate(ncWindow.selectedDateObj);
                    }
                } catch(e) {}
            }
        }
    }
    
    // Estados para los botones del panel superior
    property bool wifiState: false
    property bool btState: false
    property bool airplaneState: false
    property bool caffeineState: false

    // Señales para comunicación con shell.qml
    signal toggleWifiRequested()
    signal toggleBtRequested()
    signal toggleAirplaneRequested()
    signal toggleCaffeineRequested()
    signal powerRequested()

    Process { id: ncCommand }
    function execCmd(cmd) { ncCommand.command = ["bash", "-c", cmd]; ncCommand.running = true; }
    
    // Propiedades internas para la navegación del calendario
    property int displayMonth: new Date().getMonth()
    property int displayYear: new Date().getFullYear()
    
    signal requestClose()
    signal toggleDndRequested()
    signal clearRequested()

    // --- LÓGICA DE ESTADO PENDIENTE ("Cargando") ---
    property bool wifiPending: false
    property bool btPending: false
    property bool airplanePending: false
    property bool caffeinePending: false

    // En cuanto el sistema confirme el cambio real, quitamos el color gris
    onWifiStateChanged: wifiPending = false
    onBtStateChanged: btPending = false
    onAirplaneStateChanged: airplanePending = false
    onCaffeineStateChanged: caffeinePending = false

    // Temporizadores de seguridad por si el script de fondo falla
    Timer { id: wifiTimer; interval: 3000; onTriggered: ncWindow.wifiPending = false }
    Timer { id: btTimer; interval: 3000; onTriggered: ncWindow.btPending = false }
    Timer { id: airplaneTimer; interval: 3000; onTriggered: ncWindow.airplanePending = false }
    Timer { id: caffeineTimer; interval: 3000; onTriggered: ncWindow.caffeinePending = false }

    screen: Quickshell.screens[0]
    
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true 
    
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: visible_state ? WlrLayershell.OnDemand : WlrLayershell.None

    visible: isReallyVisible
    color: "transparent"
    
    onVisible_stateChanged: {
        if (visible_state) {
            closeTimer.stop()
            isReallyVisible = true
            
            // Seleccionar automáticamente el día de hoy al abrir
            selectedDateObj = new Date();
            selectedDateString = Qt.formatDateTime(selectedDateObj, "dd MMMM yyyy");
            selectedEvents = getEventsForDate(selectedDateObj);
        } else {
            displayMonth = new Date().getMonth()
            displayYear = new Date().getFullYear()
            closeTimer.start()
        }
    }
    
    Timer { 
        id: closeTimer
        interval: 350 // Tiempo suficiente para que termine la animación de salida
        onTriggered: isReallyVisible = false 
    }

    MouseArea {
        anchors.fill: parent
        onClicked: ncWindow.requestClose()
    }

    Item {
        id: animationContainer
        width: 440
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.rightMargin: 12 
        anchors.topMargin: 0

        // --- NUEVA ANIMACIÓN DE DESLIZAMIENTO ---
        transform: Translate {
            x: ncWindow.visible_state ? 0 : 460 // Se desplaza a la derecha cuando se cierra
            Behavior on x { 
                NumberAnimation { 
                    duration: 350
                    easing.type: Easing.OutQuart 
                } 
            }
        }
        
        opacity: ncWindow.visible_state ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 250 } }

        Column {
            anchors.right: parent.right
            width: 400
            spacing: 12

            // PANEL DE NOTIFICACIONES
            Rectangle {
                width: parent.width
                height: 480
                radius: 10
                color: Theme.bgGlass 
                border.color: Qt.alpha(Theme.white, 0.15) 
                border.width: 1

                // Disparador principal para abrir la app desde la notificación
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    // z: 0 permite que el botón "X" (que está dentro del RowLayout) se superponga correctamente
                    z: 0 
                    onClicked: {
                        // Cierra el centro de notificaciones
                        ncWindow.requestClose()
                        // Envía el comando de acción al daemon (invocando la acción por defecto)
                        execCmd("echo 'ACTION|" + model.id + "|default' > /tmp/qs_notif_cmd")
                        // Fuerza la eliminación visual inmediata
                        execCmd("echo 'REMOVE|" + model.id + "' > /tmp/qs_notif_cmd")
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 15

                    // PANEL DE BOTONES RÁPIDOS
                    // PANEL DE BOTONES RÁPIDOS
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            Layout.preferredWidth: 64; Layout.preferredHeight: 48; radius: 12
                            // Color del fondo: Si está pendiente -> Gris. Si no -> Blanco o Transparente
                            color: ncWindow.wifiPending ? Theme.grey1 : (ncWindow.wifiState ? Theme.white : Qt.alpha(Theme.white, 0.1))
                            Text { 
                                anchors.centerIn: parent; text: ""; font.family: Theme.fontIcons; font.pixelSize: 18; 
                                color: ncWindow.wifiPending ? Theme.white : (ncWindow.wifiState ? Theme.bg0 : Theme.white) 
                            }
                            MouseArea { 
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor; 
                                onClicked: {
                                    if (!ncWindow.wifiPending) {
                                        ncWindow.wifiPending = true;
                                        wifiTimer.restart();
                                        ncWindow.toggleWifiRequested();
                                    }
                                } 
                            }
                        }
                        Rectangle {
                            Layout.preferredWidth: 64; Layout.preferredHeight: 48; radius: 12
                            color: ncWindow.btPending ? Theme.grey1 : (ncWindow.btState ? Theme.white : Qt.alpha(Theme.white, 0.1))
                            Text { 
                                anchors.centerIn: parent; text: ""; font.family: Theme.fontIcons; font.pixelSize: 18; 
                                color: ncWindow.btPending ? Theme.white : (ncWindow.btState ? Theme.bg0 : Theme.white) 
                            }
                            MouseArea { 
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor; 
                                onClicked: {
                                    if (!ncWindow.btPending) {
                                        ncWindow.btPending = true;
                                        btTimer.restart();
                                        ncWindow.toggleBtRequested();
                                    }
                                } 
                            }
                        }
                        Rectangle {
                            Layout.preferredWidth: 64; Layout.preferredHeight: 48; radius: 12
                            color: ncWindow.airplanePending ? Theme.grey1 : (ncWindow.airplaneState ? Theme.white : Qt.alpha(Theme.white, 0.1))
                            Text { 
                                anchors.centerIn: parent; text: ""; font.family: Theme.fontIcons; font.pixelSize: 18; 
                                color: ncWindow.airplanePending ? Theme.white : (ncWindow.airplaneState ? Theme.bg0 : Theme.white) 
                            }
                            MouseArea { 
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor; 
                                onClicked: {
                                    if (!ncWindow.airplanePending) {
                                        ncWindow.airplanePending = true;
                                        airplaneTimer.restart();
                                        ncWindow.toggleAirplaneRequested();
                                    }
                                } 
                            }
                        }
                        Rectangle {
                            Layout.preferredWidth: 64; Layout.preferredHeight: 48; radius: 12
                            color: ncWindow.caffeinePending ? Theme.grey1 : (ncWindow.caffeineState ? Theme.white : Qt.alpha(Theme.white, 0.1))
                            Text { 
                                anchors.centerIn: parent; text: ncWindow.caffeineState ? "" : ""; font.family: Theme.fontIcons; font.pixelSize: 18; 
                                color: ncWindow.caffeinePending ? Theme.white : (ncWindow.caffeineState ? Theme.bg0 : Theme.white) 
                            }
                            MouseArea { 
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor; 
                                onClicked: {
                                    if (!ncWindow.caffeinePending) {
                                        ncWindow.caffeinePending = true;
                                        caffeineTimer.restart();
                                        ncWindow.toggleCaffeineRequested();
                                    }
                                } 
                            }
                        }
                        Rectangle {
                            Layout.preferredWidth: 64; Layout.preferredHeight: 48; radius: 12
                            color: Qt.alpha(Theme.white, 0.1)
                            Text { anchors.centerIn: parent; text: "⏻"; font.family: Theme.fontIcons; font.pixelSize: 18; color: Theme.white }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ncWindow.powerRequested() }
                        }
                    }

                    // CABECERA
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Notifications"; color: Theme.white; font.bold: true; font.pixelSize: 15 }
                        Item { Layout.fillWidth: true }
                        Text { 
                            text: ncWindow.dndState ? "󰂠" : ""; font.family: Theme.fontIcons; 
                            color: ncWindow.dndState ? Theme.white : Theme.grey1; font.pixelSize: 18
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ncWindow.toggleDndRequested() }
                        }
                        Item { Layout.preferredWidth: 5 }
                        Rectangle {
                            id: clearAllBtn
                            width: 80; height: 26; radius: 8; 
                            property bool hasNotifs: ncWindow.modelData && ncWindow.modelData.count > 0
                            color: hasNotifs ? (clearMouse.containsMouse ? Qt.alpha(Theme.white, 0.2) : Qt.alpha(Theme.white, 0.1)) : "transparent"
                            border.color: hasNotifs ? "transparent" : Qt.alpha(Theme.white, 0.05)
                            Text { anchors.centerIn: parent; text: "Clear All"; color: clearAllBtn.hasNotifs ? Theme.white : Theme.grey1; font.pixelSize: 11; font.bold: true }
                            MouseArea { id: clearMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: clearAllBtn.hasNotifs ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: { if(clearAllBtn.hasNotifs) ncWindow.clearRequested() } }
                        }
                    }

                    ListView {
                        Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 10
                        model: ncWindow.modelData
                        Text { text: "No new notifications"; color: Theme.grey1; font.pixelSize: 14; anchors.centerIn: parent; visible: ncWindow.modelData && ncWindow.modelData.count === 0 }
                        delegate: Rectangle {
                        width: 360
                        height: 75
                        radius: 15
                        
                        // 1. Fondo ligeramente rojizo si es crítica
                        color: model.urgency === 2 ? Qt.alpha(Theme.red, 0.15) : Qt.alpha(Theme.white, 0.05)
                        
                        // 2. Borde rojo para destacar
                        border.color: model.urgency === 2 ? Theme.red : "transparent"
                        border.width: model.urgency === 2 ? 2 : 0

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 12

                            Item {
                                Layout.preferredWidth: 35
                                Layout.preferredHeight: 35

                                Image {
                                    id: notifImgCenter
                                    anchors.fill: parent
                                    source: String(icon).startsWith("/") ? "file://" + icon : "image://icon/" + icon
                                    fillMode: Image.PreserveAspectCrop // Corrección crítica
                                    visible: false // Se oculta la imagen original sin recortar
                                }

                                Rectangle {
                                    id: maskCenter
                                    anchors.fill: parent
                                    radius: width / 2
                                    visible: false // Se oculta la máscara de referencia
                                }

                                OpacityMask {
                                    anchors.fill: parent
                                    source: notifImgCenter
                                    maskSource: maskCenter
                                    layer.enabled: model.urgency === 2 // Mantiene tu lógica de borde rojo
                                }
                            }

                            ColumnLayout {
                                spacing: 2
                                
                                Text { 
                                    text: app + (model.urgency === 2 ? " • CRITICAL" : "") 
                                    color: model.urgency === 2 ? Theme.red : Theme.blue
                                    font.pixelSize: 10
                                    font.bold: true 
                                }
                                
                                Text { 
                                    text: title
                                    color: Theme.white
                                    font.pixelSize: 12
                                    font.bold: true
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                
                                Text { 
                                    text: body
                                    color: Theme.grey1
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                    maximumLineCount: 1
                                }
                            }
                            
                            // Botón de cerrar (X)
                            Item {
                                Layout.alignment: Qt.AlignTop | Qt.AlignRight
                                width: 20
                                height: 20
                                Text { 
                                    anchors.centerIn: parent
                                    text: "󰅖"
                                    font.family: Theme.fontIcons
                                    color: xMouse.containsMouse ? Theme.white : Theme.grey1
                                    font.pixelSize: 14 
                                }
                                MouseArea { 
                                    id: xMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { execCmd("echo 'REMOVE|" + model.id + "' > /tmp/qs_notif_cmd") }
                                }
                            }
                        }
                    }
                    }
                }
            }

            // CALENDARIO Y AGENDA
            Rectangle {
                width: parent.width
                // Altura dinámica: se expande si hay ALGÚN día seleccionado
                height: ncWindow.selectedDateString !== "" ? 520 : 400 
                Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutQuart } }
                radius: 10
                color: Theme.bgGlass 
                border.color: Qt.alpha(Theme.white, 0.15) 
                border.width: 1
                clip: true
                
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 25
                    spacing: 15
                    
                    // Controles del Mes (Limpiamos la selección al cambiar de mes manualmente)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 15
                        Text { 
                            text: "󰅁"; font.family: Theme.fontIcons; font.pixelSize: 22; color: Theme.grey1; // CAMBIADO: Ahora es flecha izquierda
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (displayMonth === 0) { displayMonth = 11; displayYear--; } else { displayMonth--; }; ncWindow.selectedDateString = ""; ncWindow.selectedEvents = []; } } 
                        }
                        Text { 
                            text: Qt.formatDateTime(new Date(displayYear, displayMonth, 1), "MMMM yyyy");
                            color: Theme.white; font.bold: true; font.pixelSize: 18; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; 
                            MouseArea { 
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor; 
                                onClicked: { 
                                    displayMonth = new Date().getMonth(); 
                                    displayYear = new Date().getFullYear(); 
                                    // SOLUCIÓN 1: Al volver a hoy, forzamos la selección del día actual para que no se pliegue
                                    ncWindow.selectedDateObj = new Date();
                                    ncWindow.selectedDateString = Qt.formatDateTime(ncWindow.selectedDateObj, "dd MMMM yyyy");
                                    ncWindow.selectedEvents = ncWindow.getEventsForDate(ncWindow.selectedDateObj);
                                } 
                            } 
                        }
                        Text { 
                            text: "󰅂"; font.family: Theme.fontIcons; font.pixelSize: 22; color: Theme.grey1; 
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (displayMonth === 11) { displayMonth = 0; displayYear++; } else { displayMonth++; }; ncWindow.selectedDateString = ""; ncWindow.selectedEvents = []; } } 
                        }
                    }

                    // Días de la semana
                    DayOfWeekRow {
                        Layout.fillWidth: true
                        locale: Qt.locale("en_GB") 
                        delegate: Text { text: model.shortName; color: Theme.white; font.bold: true; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter }
                    }

                    // El Grid del Mes
                    MonthGrid {
                        id: grid
                        Layout.fillWidth: true
                        Layout.preferredHeight: 220
                        locale: Qt.locale("en_GB")
                        month: displayMonth
                        year: displayYear
                        
                        delegate: Item {
                            implicitWidth: 30
                            implicitHeight: 30
                            opacity: model.month === grid.month ? 1 : 0.2
                            
                            property var dayEvents: ncWindow.getEventsForDate(model.date)
                            property bool hasEvents: dayEvents.length > 0
                            property bool isSelected: Qt.formatDateTime(model.date, "dd MMMM yyyy") === ncWindow.selectedDateString

                            // Círculo de selección / hoy
                            Rectangle { 
                                anchors.centerIn: parent
                                width: 30; height: 30; radius: 15
                                color: isSelected ? Theme.blue : Theme.white
                                opacity: isSelected ? 0.3 : (dayMouseArea.containsMouse ? 0.2 : (model.today ? 0.1 : 0))
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                z: -1 
                            }
                            
                            // Número del día
                            Text {
                                anchors.centerIn: parent
                                text: model.day
                                font.pixelSize: 14
                                font.bold: model.today || hasEvents || isSelected
                                color: isSelected ? Theme.white : (model.today ? Theme.white : (hasEvents ? Theme.blue : Theme.grey1))
                            }

                            // Puntito indicador de eventos
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 2
                                width: 4; height: 4; radius: 2
                                color: isSelected ? Theme.white : Theme.blue
                                visible: hasEvents
                            }

                            MouseArea {
                                id: dayMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (isSelected) {
                                        ncWindow.selectedDateString = "";
                                        ncWindow.selectedEvents = [];
                                    } else {
                                        ncWindow.selectedDateObj = model.date;
                                        ncWindow.selectedDateString = Qt.formatDateTime(model.date, "dd MMMM yyyy");
                                        ncWindow.selectedEvents = dayEvents;
                                    }
                                }
                            }
                        }
                    }

                    // Separador animado
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Qt.alpha(Theme.white, 0.1)
                        visible: ncWindow.selectedDateString !== ""
                    }

                    // Texto para días seleccionados SIN eventos
                    Text {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        text: "No events today"
                        color: Qt.alpha(Theme.white, 0.5)
                        font.family: Theme.fontMain
                        font.pixelSize: 13
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        visible: ncWindow.selectedDateString !== "" && ncWindow.selectedEvents.length === 0
                    }

                    // Lista de Eventos del día seleccionado
                    ListView {
                        id: eventList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 8
                        model: ncWindow.selectedEvents
                        visible: ncWindow.selectedEvents.length > 0
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: RowLayout {
                            width: ListView.view.width
                            spacing: 12

                            Text { 
                                text: modelData.time
                                color: Theme.blue
                                font.family: Theme.fontMain
                                font.pixelSize: 12
                                font.bold: true
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    text: modelData.title
                                    color: Theme.white
                                    font.family: Theme.fontMain
                                    font.pixelSize: 12
                                    font.bold: true
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                                Text {
                                    text: modelData.location || ""
                                    color: Qt.alpha(Theme.white, 0.5)
                                    font.family: Theme.fontMain
                                    font.pixelSize: 10
                                    visible: modelData.location !== undefined && modelData.location !== ""
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}