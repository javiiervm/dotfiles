import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick.Controls
import ".."

PanelWindow {
    id: ncWindow

    property bool visible_state: false
    property bool isReallyVisible: false
    property bool dndState: false
    property ListModel modelData
    
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
                color: Qt.alpha(Theme.bg0, 0.9)
                border.color: Qt.alpha(Theme.white, 0.1)
                border.width: 1

                MouseArea { anchors.fill: parent }

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

                            Image { 
                                Layout.preferredWidth: 35
                                Layout.preferredHeight: 35
                                source: "image://icon/" + icon
                                fillMode: Image.PreserveAspectFit
                                
                                // Opcional: Desaturar el icono si no es crítica, o ponerle un tinte
                                layer.enabled: model.urgency === 2
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

            // CALENDARIO (Blanco)
            Rectangle {
                width: parent.width; height: 400; radius: 10
                color: Qt.alpha(Theme.bg0, 0.9); border.color: Qt.alpha(Theme.white, 0.1); border.width: 1
                
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 25; spacing: 15
                    RowLayout {
                        Layout.fillWidth: true; spacing: 15
                        Text { text: "󰅖"; font.family: Theme.fontIcons; font.pixelSize: 22; color: Theme.grey1; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (displayMonth === 0) { displayMonth = 11; displayYear--; } else { displayMonth--; } } } }
                        Text { text: Qt.formatDateTime(new Date(displayYear, displayMonth, 1), "MMMM yyyy"); color: Theme.white; font.bold: true; font.pixelSize: 18; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { displayMonth = new Date().getMonth(); displayYear = new Date().getFullYear(); } } }
                        Text { text: "󰅂"; font.family: Theme.fontIcons; font.pixelSize: 22; color: Theme.grey1; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (displayMonth === 11) { displayMonth = 0; displayYear++; } else { displayMonth++; } } } }
                    }
                    DayOfWeekRow {
                        Layout.fillWidth: true; locale: Qt.locale("en_GB") 
                        delegate: Text { text: model.shortName; color: Theme.white; font.bold: true; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter }
                    }
                    MonthGrid {
                        id: grid; Layout.fillWidth: true; Layout.fillHeight: true; locale: Qt.locale("en_GB"); month: displayMonth; year: displayYear
                        delegate: Text {
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; opacity: model.month === grid.month ? 1 : 0.2
                            text: model.day; font.pixelSize: 14; font.bold: model.today; color: model.today ? Theme.white : Theme.grey1
                            Rectangle { anchors.centerIn: parent; width: 30; height: 30; radius: 15; color: Theme.white; opacity: 0.1; visible: model.today; z: -1 }
                        }
                    }
                    Item { Layout.preferredHeight: 5 }
                }
            }
        }
    }
}