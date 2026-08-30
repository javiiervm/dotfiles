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
    
    // Modos: 0: Apps, 1: Files Search, 4: System, 5: Wi-Fi, 6: Bluetooth, 9: Password, 10: Cleanup
    property int currentMode: 0 
    property string targetWifiSsid: ""
    property bool isWifiEnabled: false
    property bool isBtEnabled: false
    
    property bool isWifiLoading: false
    property bool isBtLoading: false
    property bool isFileLoading: false

    // Estado del panel Cleanup. Los datos vienen de ~/.local/bin/cleanup.py --status-json.
    property bool isCleanupLoading: false
    property bool isCleanupCleaning: false
    property bool cleanupConfirmVisible: false
    property string cleanupError: ""
    property string cleanupLastMessage: ""
    property var cleanupData: ({})
    // Navegación por teclado del panel Cleanup:
    // 0 = volver, 1 = Scan again, 2 = Clear removable cache
    property int cleanupSelection: 1
    // Navegación por teclado del diálogo de confirmación:
    // 0 = Cancel, 1 = Clear cache
    property int cleanupConfirmSelection: 0
    property bool recentKeyboardActive: false

    // System actions are queued until the Launcher has fully released
    // its layer-shell surface / keyboard focus.
    property string pendingSystemAction: ""
    
    property int activeHeaderButton: 0

    // Apps recientes: mantenemos una fila separada al estilo macOS.
    // Los nombres se leen de ~/.cache/qs_recents, que ya actualiza executeApp().
    property var recentNames: []

    signal requestIslandMsg(string icon, string color, string text)

    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: isReallyVisible ? WlrLayershell.OnDemand : WlrLayershell.None
    visible: isReallyVisible
    color: "transparent"

    BackgroundEffect.blurRegion: Glass.blurEnabled ? launcherBlurRegion : null

    /*
     * Do NOT bind the blur Region directly to mainCard.
     *
     * mainCard is animated with scale 0 -> 1 when the launcher opens/closes.
     * A Region attached directly to that transformed item can keep the small
     * geometry from the closing animation and reuse it on later openings.
     *
     * This proxy reproduces the visible geometry using normal width/height,
     * without a QML transform, so BackgroundEffect always receives a clean,
     * continuously updated region.
     */
    Item {
        id: launcherBlurTarget

        anchors.centerIn: parent

        width: Math.max(0, mainCard.width * mainCard.scale)
        height: Math.max(0, mainCard.height * mainCard.scale)
    }

    Region {
        id: launcherBlurRegion
        item: launcherBlurTarget
        radius: Math.max(0, mainCard.radius * mainCard.scale)
    }

    // Persistent application cache for the whole Quickshell session.
    // Apps are loaded once, so reopening the launcher is pure in-memory work.
    ListModel { id: appsModel }
    ListModel { id: rawModel }
    ListModel { id: filteredModel }
    ListModel { id: recentModel }

    Component.onCompleted: {
        loadAppsOnce();
        loadRecents();
    }

    MouseArea { anchors.fill: parent; onClicked: { if (visible_state) toggle(); } }

    Timer {
        id: closeTimer
        interval: 300
        onTriggered: {
            isReallyVisible = false;
            launcherWindow.currentMode = 0;
            launcherWindow.activeHeaderButton = 0;
            launcherWindow.cleanupConfirmVisible = false;
            launcherWindow.cleanupSelection = 1;
            launcherWindow.cleanupConfirmSelection = 0;
            searchInput.text = "";
            searchInput.echoMode = TextInput.Normal;
        }
    }

    Timer {
        id: systemActionTimer
        interval: 420
        repeat: false

        onTriggered: {
            var action = launcherWindow.pendingSystemAction;
            launcherWindow.pendingSystemAction = "";

            execProc.running = false;

            if (action === "lock") {
                execProc.command = ["loginctl", "lock-session"];
            } else if (action === "suspend") {
                execProc.command = ["systemctl", "suspend"];
            } else if (action === "logout") {
                // Hyprland >= 0.55 Lua dispatcher syntax.
                execProc.command = ["hyprctl", "dispatch", "hl.dsp.exit()"];
            } else if (action === "reboot") {
                execProc.command = ["systemctl", "reboot"];
            } else if (action === "shutdown") {
                execProc.command = ["systemctl", "poweroff"];
            } else {
                return;
            }

            execProc.startDetached();
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
        id: appsLoader
        stdout: SplitParser {
            onRead: (line) => {
                if (!line || line.trim() === "") return;
                var f = line.split("|");
                if (f.length >= 5) {
                    appendUnique(appsModel, {
                        name: f[0],
                        comment: f[1],
                        icon: f[2],
                        exec: f[3],
                        type: f[4]
                    });
                }
            }
        }
        onExited: {
            updateFilter();
            rebuildRecentModel();
        }
    }

    Process { id: recentWriteProc }

    Process {
        id: dataLoader
        stdout: SplitParser {
            onRead: (line) => {
                if (!line || line.trim() === "") return;
                var f = line.split("|");
                if (f.length >= 5) {
                    appendUnique(rawModel, {
                        name: f[0],
                        comment: f[1],
                        icon: f[2],
                        exec: f[3],
                        type: f[4]
                    });
                }
            }
        }
        onExited: {
            launcherWindow.isFileLoading = false;
            updateFilter();
        }
    }

    Process {
        id: recentLoader
        stdout: SplitParser {
            onRead: (line) => {
                var name = (line || "").trim();
                if (name === "") return;

                var names = launcherWindow.recentNames.slice();
                if (names.indexOf(name) === -1 && names.length < 6) {
                    names.push(name);
                    launcherWindow.recentNames = names;
                }
            }
        }
        onExited: rebuildRecentModel()
    }

    Process { id: execProc }

    Process {
        id: cleanupStatusProc
        property string output: ""
        stdout: SplitParser {
            onRead: (line) => {
                if (!line || line.trim() === "") return;
                cleanupStatusProc.output += line;
            }
        }
        onExited: function(exitCode) {
            launcherWindow.isCleanupLoading = false;
            if (exitCode !== 0) {
                launcherWindow.cleanupError = "Unable to read cleanup status.";
                return;
            }
            try {
                launcherWindow.cleanupData = JSON.parse(cleanupStatusProc.output);
                launcherWindow.cleanupError = "";
            } catch (error) {
                launcherWindow.cleanupError = "Invalid response from cleanup.py";
            }
        }
    }

    Process {
        id: cleanupActionProc
        property string output: ""
        stdout: SplitParser {
            onRead: (line) => {
                if (!line || line.trim() === "") return;
                cleanupActionProc.output += line;
            }
        }
        onExited: function(exitCode) {
            launcherWindow.isCleanupCleaning = false;
            launcherWindow.cleanupConfirmVisible = false;
            if (exitCode === 0) {
                try {
                    var result = JSON.parse(cleanupActionProc.output);
                    launcherWindow.cleanupLastMessage = result.message || "Cleanup complete.";
                } catch (error) {
                    launcherWindow.cleanupLastMessage = "Cleanup complete.";
                }
                loadCleanupStatus();
            } else {
                launcherWindow.cleanupError = "Cleanup failed. Run cleanup.py in a terminal for details.";
            }
        }
    }

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
    GlassSurface {
        id: mainCard
        property int targetWidth: {
            if (launcherWindow.currentMode === 1 || launcherWindow.currentMode === 4 || launcherWindow.currentMode === 5 || launcherWindow.currentMode === 6) return 420;
            if (launcherWindow.currentMode === 10) return 620;
            if (launcherWindow.currentMode === 9) return 320; 
            return 720; 
        }

        width: targetWidth
        height: contentColumn.height + 40 
        anchors.centerIn: parent
        transformOrigin: Item.Center
        glassRadius: 20
        clip: true

        scale: launcherWindow.visible_state ? 1.0 : 0.0
        opacity: launcherWindow.visible_state ? 1.0 : 0.0

        Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.OutQuint } }
        Behavior on height { NumberAnimation { duration: 350; easing.type: Easing.OutQuint } }
        Behavior on scale { NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }
        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutQuad } }

        MouseArea { anchors.fill: parent }

        Rectangle {
            z: 50
            anchors.fill: parent
            visible: launcherWindow.cleanupConfirmVisible
            color: Qt.rgba(0, 0, 0, 0.34)

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    launcherWindow.cleanupConfirmVisible = false
                    launcherWindow.cleanupConfirmSelection = 0
                    searchInput.forceActiveFocus()
                }
            }

            Rectangle {
                width: Math.min(390, parent.width - 48)
                height: 190
                radius: 20
                anchors.centerIn: parent
                color: Qt.alpha(Theme.bg0, 0.94)
                border.color: Qt.alpha(Theme.white, 0.20)
                border.width: 1

                MouseArea { anchors.fill: parent }

                Column {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 10

                    Text {
                        width: parent.width
                        text: "Clear removable cache?"
                        color: Theme.white
                        font.family: Theme.fontMain
                        font.pixelSize: 17
                        font.bold: true
                        horizontalAlignment: Text.AlignLeft
                    }

                    Text {
                        width: parent.width
                        text: "This will clear the configured yay, paru, Spotify and Mozilla caches. It will not wipe all of ~/.cache."
                        color: Qt.alpha(Theme.white, 0.62)
                        font.family: Theme.fontMain
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignLeft
                    }

                    Item { width: 1; height: 4 }

                    Row {
                        width: parent.width
                        spacing: 10

                        Rectangle {
                            width: (parent.width - 10) / 2
                            height: 40
                            radius: 12
                            color: launcherWindow.cleanupConfirmSelection === 0
                                   ? Theme.white
                                   : (cancelCleanupMouse.containsMouse ? Qt.alpha(Theme.white, 0.15) : Qt.alpha(Theme.white, 0.09))
                            border.color: launcherWindow.cleanupConfirmSelection === 0
                                          ? Theme.white
                                          : Qt.alpha(Theme.white, 0.12)
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: "Cancel"
                                color: launcherWindow.cleanupConfirmSelection === 0 ? Theme.bg0 : Theme.white
                                font.family: Theme.fontMain
                                font.pixelSize: 13
                                font.bold: true
                            }

                            MouseArea {
                                id: cancelCleanupMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: launcherWindow.cleanupConfirmSelection = 0
                                onClicked: {
                                    launcherWindow.cleanupConfirmVisible = false
                                    launcherWindow.cleanupConfirmSelection = 0
                                    searchInput.forceActiveFocus()
                                }
                            }
                        }

                        Rectangle {
                            width: (parent.width - 10) / 2
                            height: 40
                            radius: 12
                            color: launcherWindow.cleanupConfirmSelection === 1
                                   ? Theme.white
                                   : (confirmCleanupMouse.containsMouse ? Qt.alpha(Theme.white, 0.15) : Qt.alpha(Theme.white, 0.09))
                            border.color: launcherWindow.cleanupConfirmSelection === 1
                                          ? Theme.white
                                          : Qt.alpha(Theme.white, 0.12)
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: "Clear cache"
                                color: launcherWindow.cleanupConfirmSelection === 1 ? Theme.bg0 : Theme.white
                                font.family: Theme.fontMain
                                font.pixelSize: 13
                                font.bold: true
                            }

                            MouseArea {
                                id: confirmCleanupMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: launcherWindow.cleanupConfirmSelection = 1
                                onClicked: runCleanup()
                            }
                        }
                    }
                }
            }
        }

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
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: launcherWindow.currentMode === 9 ? parent.width : Math.min(parent.width, 470)
                    height: launcherWindow.currentMode === 9 ? 50 : 38
                    visible: launcherWindow.currentMode === 0 || launcherWindow.currentMode === 9
                    radius: height / 2
                    color: launcherWindow.currentMode === 9
                        ? Qt.alpha(Theme.white, 0.05)
                        : Qt.alpha(Theme.white, 0.075)
                    border.color: launcherWindow.currentMode === 9
                        ? Qt.alpha(Theme.white, 0.15)
                        : Qt.alpha(Theme.white, 0.18)
                    border.width: 1

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: launcherWindow.currentMode === 9 ? 8 : 14
                        anchors.rightMargin: launcherWindow.currentMode === 9 ? 20 : 14
                        spacing: launcherWindow.currentMode === 9 ? 12 : 9

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
                            color: Qt.alpha(Theme.white, 0.58)
                            font.pixelSize: 14
                            visible: launcherWindow.currentMode === 0
                        }

                        TextInput {
                            id: searchInput
                            width: parent.width - (launcherWindow.currentMode === 9 ? 50 : 32)
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.white
                            font.pixelSize: launcherWindow.currentMode === 9 ? 16 : 14
                            selectionColor: Theme.blue
                            selectedTextColor: Theme.bg0
                            clip: true

                            Text {
                                text: launcherWindow.currentMode === 9 ? "Password" : "Search"
                                color: Qt.alpha(Theme.white, 0.48)
                                font.pixelSize: launcherWindow.currentMode === 9 ? 16 : 14
                                anchors.verticalCenter: parent.verticalCenter
                                visible: searchInput.text === ""
                            }

                            onTextChanged: {
                                launcherWindow.recentKeyboardActive = false;
                                recentGrid.currentIndex = -1;

                                // Si escribe/borra algo mientras está en la vista de archivos, lo devolvemos a la vista general
                                // y recargamos el modelo de apps (si no, quedan los resultados de archivos "pegados").
                                if (launcherWindow.currentMode === 1) {
                                    launcherWindow.currentMode = 0;
                                    showApps();
                                    return;
                                }
                                updateFilter();
                            }

                            Keys.onPressed: (event) => {

                                // Cleanup has its own keyboard navigation.
                                if (launcherWindow.currentMode === 10) {
                                    // Confirmation dialog: Left/Right chooses, Enter confirms, Esc cancels.
                                    if (launcherWindow.cleanupConfirmVisible) {
                                        if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
                                            launcherWindow.cleanupConfirmSelection = 0
                                            event.accepted = true
                                            return
                                        }
                                        if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
                                            launcherWindow.cleanupConfirmSelection = 1
                                            event.accepted = true
                                            return
                                        }
                                        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) {
                                            launcherWindow.cleanupConfirmVisible = false
                                            launcherWindow.cleanupConfirmSelection = 0
                                            event.accepted = true
                                            return
                                        }
                                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                            if (launcherWindow.cleanupConfirmSelection === 1)
                                                runCleanup()
                                            else {
                                                launcherWindow.cleanupConfirmVisible = false
                                                launcherWindow.cleanupConfirmSelection = 0
                                            }
                                            event.accepted = true
                                            return
                                        }
                                    }

                                    if (event.key === Qt.Key_Up) {
                                        launcherWindow.cleanupSelection = 0
                                        event.accepted = true
                                        return
                                    }
                                    if (event.key === Qt.Key_Down) {
                                        if (launcherWindow.cleanupSelection === 0)
                                            launcherWindow.cleanupSelection = 1
                                        event.accepted = true
                                        return
                                    }
                                    if (event.key === Qt.Key_Left) {
                                        if (launcherWindow.cleanupSelection === 2)
                                            launcherWindow.cleanupSelection = 1
                                        else if (launcherWindow.cleanupSelection === 1)
                                            launcherWindow.cleanupSelection = 0
                                        event.accepted = true
                                        return
                                    }
                                    if (event.key === Qt.Key_Right) {
                                        if (launcherWindow.cleanupSelection === 0)
                                            launcherWindow.cleanupSelection = 1
                                        else if (launcherWindow.cleanupSelection === 1)
                                            launcherWindow.cleanupSelection = 2
                                        event.accepted = true
                                        return
                                    }
                                    if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) {
                                        launcherWindow.currentMode = 0
                                        launcherWindow.cleanupSelection = 1
                                        launcherWindow.activeHeaderButton = 0
                                        searchInput.text = ""
                                        showApps()
                                        event.accepted = true
                                        return
                                    }
                                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                        if (launcherWindow.cleanupSelection === 0) {
                                            launcherWindow.currentMode = 0
                                            launcherWindow.cleanupSelection = 1
                                            launcherWindow.activeHeaderButton = 0
                                            searchInput.text = ""
                                            showApps()
                                        } else if (launcherWindow.cleanupSelection === 1) {
                                            if (!launcherWindow.isCleanupLoading && !launcherWindow.isCleanupCleaning)
                                                loadCleanupStatus()
                                        } else if (launcherWindow.cleanupSelection === 2) {
                                            if (!launcherWindow.isCleanupLoading
                                                    && !launcherWindow.isCleanupCleaning
                                                    && launcherWindow.cleanupData.removable_cache
                                                    && launcherWindow.cleanupData.removable_cache.total_bytes > 0) {
                                                launcherWindow.cleanupConfirmSelection = 0
                                                launcherWindow.cleanupConfirmVisible = true
                                            }
                                        }
                                        event.accepted = true
                                        return
                                    }
                                }
                                if (event.key === Qt.Key_Escape) {
                                    if (launcherWindow.currentMode === 9) { launcherWindow.currentMode = 5; searchInput.echoMode = TextInput.Normal; searchInput.text = ""; loadTabData("--wifi"); }
                                    else { toggle(); }
                                    event.accepted = true;
                                }
                                
                                if (event.key === Qt.Key_Backspace && searchInput.text === "") {
                                    if (launcherWindow.currentMode === 9) {
                                        launcherWindow.currentMode = 5; searchInput.echoMode = TextInput.Normal; loadTabData("--wifi");
                                    } else if (launcherWindow.currentMode === 1 || launcherWindow.currentMode === 4 || launcherWindow.currentMode === 5 || launcherWindow.currentMode === 6 || launcherWindow.currentMode === 10) {
                                        launcherWindow.currentMode = 0; launcherWindow.activeHeaderButton = 0; showApps();
                                    }
                                    event.accepted = true;
                                }
                                
                                if (event.key === Qt.Key_Down && launcherWindow.calcResult === "") { 
                                    if (launcherWindow.currentMode === 0) {
                                        if (launcherWindow.recentKeyboardActive) {
                                            var recentColumnDown = Math.max(0, recentGrid.currentIndex);
                                            launcherWindow.recentKeyboardActive = false;
                                            recentGrid.currentIndex = -1;
                                            if (filteredModel.count > 0)
                                                appGrid.currentIndex = Math.min(recentColumnDown, filteredModel.count - 1);
                                        } else {
                                            appGrid.moveCurrentIndexDown(); 
                                        }
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
                                        if (launcherWindow.recentKeyboardActive) {
                                            // Already in Recent: keep the current item selected.
                                        } else if (recentSection.visible && appGrid.currentIndex >= 0 && appGrid.currentIndex < 6) {
                                            launcherWindow.recentKeyboardActive = true;
                                            recentGrid.currentIndex = Math.min(appGrid.currentIndex, recentModel.count - 1);
                                        } else {
                                            appGrid.moveCurrentIndexUp(); 
                                        }
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
                                    if (launcherWindow.currentMode === 0) {
                                        if (launcherWindow.recentKeyboardActive) {
                                            if (recentGrid.currentIndex < recentModel.count - 1)
                                                recentGrid.currentIndex++;
                                        } else {
                                            appGrid.moveCurrentIndexRight();
                                        }
                                    }
                                    else if ((launcherWindow.currentMode === 5 || launcherWindow.currentMode === 6) && launcherWindow.activeHeaderButton > 0) {
                                        launcherWindow.activeHeaderButton = Math.min(3, launcherWindow.activeHeaderButton + 1);
                                    }
                                    event.accepted = true;
                                }
                                
                                if (event.key === Qt.Key_Left) {
                                    if (launcherWindow.currentMode === 0) {
                                        if (launcherWindow.recentKeyboardActive) {
                                            if (recentGrid.currentIndex > 0)
                                                recentGrid.currentIndex--;
                                        } else {
                                            appGrid.moveCurrentIndexLeft();
                                        }
                                    }
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
                                            launcherWindow.currentMode = 0; launcherWindow.activeHeaderButton = 0; showApps(); 
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
                                        if (launcherWindow.currentMode === 0 && launcherWindow.recentKeyboardActive) {
                                            if (recentModel.count > 0 && recentGrid.currentIndex >= 0) {
                                                var recentItem = recentModel.get(recentGrid.currentIndex);
                                                executeApp(recentItem.exec, recentItem.name);
                                            }
                                            event.accepted = true;
                                            return;
                                        }

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
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { launcherWindow.currentMode = 0; launcherWindow.activeHeaderButton = 0; showApps(); } }
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
                    visible: launcherWindow.currentMode === 1 || launcherWindow.currentMode === 4 || launcherWindow.currentMode === 10

                    Rectangle {
                        id: backBtnSys
                        width: 40; height: 40; radius: 20
                        color: launcherWindow.activeHeaderButton === 1 ? Qt.alpha(Theme.white, 0.2) : Qt.alpha(Theme.white, 0.08)
                        border.color: launcherWindow.activeHeaderButton === 1 ? Theme.white : "transparent"
                        border.width: 1
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        Text { anchors.centerIn: parent; text: ""; font.family: Theme.fontIcons; color: Theme.white; font.pixelSize: 16 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onEntered: { if (launcherWindow.currentMode === 10) launcherWindow.cleanupSelection = 0 }
                            onClicked: {
                                launcherWindow.currentMode = 0;
                                launcherWindow.activeHeaderButton = 0;
                                launcherWindow.cleanupSelection = 1;
                                searchInput.text = "";
                                showApps();
                            } }
                    }

                    Text {
                        text: launcherWindow.currentMode === 1 ? "File Search Results" : (launcherWindow.currentMode === 10 ? "Cleanup" : "System Options")
                        color: Theme.white; font.pixelSize: 16; font.bold: true
                        anchors.left: backBtnSys.right; anchors.leftMargin: 15; anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // ------------------------------------------
            // 2. CLEANUP (Modo 10)
            // ------------------------------------------
            Column {
                id: cleanupPanel
                width: parent.width
                spacing: 14
                visible: launcherWindow.currentMode === 10

                Rectangle {
                    width: parent.width
                    height: 108
                    radius: 18
                    color: Qt.alpha(Theme.white, 0.06)
                    border.color: Qt.alpha(Theme.white, 0.12)
                    border.width: 1

                    Column {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 8

                        Item {
                            width: parent.width
                            height: 22

                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 10

                                Text {
                                    text: "󰋊"
                                    font.family: Theme.fontIcons
                                    color: Theme.white
                                    font.pixelSize: 19
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: "Disk"
                                    color: Theme.white
                                    font.family: Theme.fontMain
                                    font.pixelSize: 15
                                    font.bold: true
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(250, parent.width * 0.48)
                                text: launcherWindow.cleanupData.disk
                                      ? launcherWindow.cleanupData.disk.used_human + " / " + launcherWindow.cleanupData.disk.total_human
                                      : "—"
                                color: Qt.alpha(Theme.white, 0.58)
                                font.family: Theme.fontMain
                                font.pixelSize: 12
                                horizontalAlignment: Text.AlignRight
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 9
                            radius: 4.5
                            color: Qt.alpha(Theme.white, 0.10)

                            Rectangle {
                                width: parent.width * Math.max(0, Math.min(1, launcherWindow.cleanupData.disk ? launcherWindow.cleanupData.disk.percentage / 100 : 0))
                                height: parent.height
                                radius: parent.radius
                                color: Theme.white
                            }
                        }

                        Text {
                            width: parent.width
                            text: launcherWindow.cleanupData.disk
                                  ? Math.round(launcherWindow.cleanupData.disk.percentage) + "% used  •  " + launcherWindow.cleanupData.disk.free_human + " available"
                                  : "Scanning storage…"
                            color: Qt.alpha(Theme.white, 0.58)
                            font.family: Theme.fontMain
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignLeft
                            elide: Text.ElideRight
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: 12

                    Rectangle {
                        width: (parent.width - 12) / 2
                        height: 128
                        radius: 18
                        color: Qt.alpha(Theme.white, 0.06)
                        border.color: Qt.alpha(Theme.white, 0.12)
                        border.width: 1
                        clip: true

                        Column {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 8

                            Text {
                                width: parent.width
                                text: "Removable cache"
                                color: Theme.white
                                font.family: Theme.fontMain
                                font.pixelSize: 14
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: launcherWindow.cleanupData.removable_cache ? launcherWindow.cleanupData.removable_cache.total_human : "—"
                                color: Theme.white
                                font.family: Theme.fontMain
                                font.pixelSize: 26
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: launcherWindow.cleanupData.removable_cache ? launcherWindow.cleanupData.removable_cache.summary : "yay • paru • Spotify • Mozilla"
                                color: Qt.alpha(Theme.white, 0.52)
                                font.family: Theme.fontMain
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Rectangle {
                        width: (parent.width - 12) / 2
                        height: 128
                        radius: 18
                        color: Qt.alpha(Theme.white, 0.06)
                        border.color: Qt.alpha(Theme.white, 0.12)
                        border.width: 1
                        clip: true

                        Column {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 8

                            Text {
                                width: parent.width
                                text: "System"
                                color: Theme.white
                                font.family: Theme.fontMain
                                font.pixelSize: 14
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Item {
                                width: parent.width
                                height: 16
                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width * 0.62
                                    text: "Package cache"
                                    color: Qt.alpha(Theme.white, 0.72)
                                    font.family: Theme.fontMain
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width * 0.34
                                    text: launcherWindow.cleanupData.package_cache ? launcherWindow.cleanupData.package_cache.human : "—"
                                    color: Qt.alpha(Theme.white, 0.58)
                                    font.family: Theme.fontMain
                                    font.pixelSize: 12
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideRight
                                }
                            }

                            Item {
                                width: parent.width
                                height: 16
                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width * 0.62
                                    text: "Journal"
                                    color: Qt.alpha(Theme.white, 0.72)
                                    font.family: Theme.fontMain
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width * 0.34
                                    text: launcherWindow.cleanupData.journal ? launcherWindow.cleanupData.journal.human : "—"
                                    color: Qt.alpha(Theme.white, 0.58)
                                    font.family: Theme.fontMain
                                    font.pixelSize: 12
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideRight
                                }
                            }

                            Item {
                                width: parent.width
                                height: 16
                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width * 0.62
                                    text: "Orphan packages"
                                    color: Qt.alpha(Theme.white, 0.72)
                                    font.family: Theme.fontMain
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width * 0.34
                                    text: launcherWindow.cleanupData.orphans ? launcherWindow.cleanupData.orphans.count : "—"
                                    color: Qt.alpha(Theme.white, 0.58)
                                    font.family: Theme.fontMain
                                    font.pixelSize: 12
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: 7
                    visible: launcherWindow.cleanupData.removable_cache && launcherWindow.cleanupData.removable_cache.entries

                    Repeater {
                        model: launcherWindow.cleanupData.removable_cache && launcherWindow.cleanupData.removable_cache.entries
                               ? launcherWindow.cleanupData.removable_cache.entries
                               : []

                        delegate: Rectangle {
                            required property var modelData
                            width: cleanupPanel.width
                            height: 34
                            radius: 10
                            color: Qt.alpha(Theme.white, 0.035)

                            Item {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width * 0.60
                                    text: modelData.name
                                    color: Qt.alpha(Theme.white, 0.76)
                                    font.family: Theme.fontMain
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }

                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width * 0.35
                                    text: modelData.human
                                    color: Qt.alpha(Theme.white, 0.52)
                                    font.family: Theme.fontMain
                                    font.pixelSize: 12
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    visible: launcherWindow.cleanupError !== "" || launcherWindow.cleanupLastMessage !== ""
                    text: launcherWindow.cleanupError !== "" ? launcherWindow.cleanupError : launcherWindow.cleanupLastMessage
                    color: launcherWindow.cleanupError !== "" ? "#ff6961" : Qt.alpha(Theme.white, 0.65)
                    font.family: Theme.fontMain
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                Row {
                    width: parent.width
                    spacing: 12

                    Rectangle {
                        width: (parent.width - 12) / 2
                        height: 42
                        radius: 14
                        color: launcherWindow.cleanupSelection === 1
                               ? Theme.white
                               : (refreshCleanupMouse.containsMouse ? Qt.alpha(Theme.white, 0.14) : Qt.alpha(Theme.white, 0.08))
                        border.color: launcherWindow.cleanupSelection === 1
                                      ? Theme.white
                                      : Qt.alpha(Theme.white, 0.13)
                        border.width: 1
                        opacity: launcherWindow.isCleanupLoading || launcherWindow.isCleanupCleaning ? 0.55 : 1

                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 20
                            text: launcherWindow.isCleanupLoading ? "Scanning…" : "↻  Scan again"
                            color: launcherWindow.cleanupSelection === 1 ? Theme.bg0 : Theme.white
                            font.family: Theme.fontMain
                            font.pixelSize: 13
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            id: refreshCleanupMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: !launcherWindow.isCleanupLoading && !launcherWindow.isCleanupCleaning
                            onEntered: launcherWindow.cleanupSelection = 1
                            onClicked: loadCleanupStatus()
                        }
                    }

                    Rectangle {
                        width: (parent.width - 12) / 2
                        height: 42
                        radius: 14
                        color: launcherWindow.cleanupSelection === 2
                               ? Theme.white
                               : (clearCleanupMouse.containsMouse ? Qt.alpha(Theme.white, 0.14) : Qt.alpha(Theme.white, 0.08))
                        border.color: launcherWindow.cleanupSelection === 2
                                      ? Theme.white
                                      : Qt.alpha(Theme.white, 0.13)
                        border.width: 1
                        opacity: (!launcherWindow.cleanupData.removable_cache
                                  || launcherWindow.cleanupData.removable_cache.total_bytes <= 0
                                  || launcherWindow.isCleanupCleaning) ? 0.45 : 1

                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 20
                            text: launcherWindow.isCleanupCleaning ? "Cleaning…" : "Clear removable cache"
                            color: launcherWindow.cleanupSelection === 2 ? Theme.bg0 : Theme.white
                            font.family: Theme.fontMain
                            font.pixelSize: 13
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            id: clearCleanupMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: !launcherWindow.isCleanupLoading
                                     && !launcherWindow.isCleanupCleaning
                                     && launcherWindow.cleanupData.removable_cache
                                     && launcherWindow.cleanupData.removable_cache.total_bytes > 0
                            onEntered: launcherWindow.cleanupSelection = 2
                            onClicked: {
                                launcherWindow.cleanupConfirmSelection = 0
                                launcherWindow.cleanupConfirmVisible = true
                                searchInput.forceActiveFocus()
                            }
                        }
                    }
                }
            }

            // ------------------------------------------
            // 3. APLICACIONES (Modo 0)
            // ------------------------------------------

            // Fila independiente de aplicaciones usadas recientemente.
            // Solo aparece en la vista normal, sin texto de búsqueda.
            Column {
                id: recentSection
                width: parent.width
                spacing: 8
                visible: launcherWindow.currentMode === 0
                    && searchInput.text === ""
                    && launcherWindow.calcResult === ""
                    && recentModel.count > 0

                Item {
                    width: parent.width
                    height: 16

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Recent"
                        color: Qt.alpha(Theme.white, 0.52)
                        font.pixelSize: 11
                        font.family: Theme.fontMain
                        font.bold: true
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 47
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 1
                        color: Qt.alpha(Theme.white, 0.10)
                    }
                }

                GridView {
                    id: recentGrid
                    width: parent.width
                    model: recentModel
                    cellWidth: parent.width / 6
                    cellHeight: 98
                    height: cellHeight
                    interactive: false
                    clip: true
                    currentIndex: -1

                    delegate: Rectangle {
                        width: recentGrid.cellWidth - 10
                        height: recentGrid.cellHeight - 8
                        radius: 14
                        color: launcherWindow.recentKeyboardActive && GridView.isCurrentItem
                            ? Qt.alpha(Theme.white, 0.15)
                            : "transparent"

                        Column {
                            width: parent.width
                            anchors.centerIn: parent
                            spacing: 7

                            Item {
                                width: 52
                                height: 52
                                anchors.horizontalCenter: parent.horizontalCenter

                                Image {
                                    anchors.fill: parent
                                    visible: icon !== "__qs_cleanup__"
                                    source: visible
                                        ? (icon.startsWith("/")
                                            ? "file://" + icon
                                            : "image://icon/" + icon)
                                        : ""
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: false
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: icon === "__qs_cleanup__"
                                    text: ""
                                    color: Theme.white
                                    font.family: Theme.fontIcons
                                    font.pixelSize: 38
                                }
                            }

                            Text {
                                width: parent.width - 8
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: name
                                color: Theme.white
                                font.pixelSize: 11
                                font.family: Theme.fontMain
                                horizontalAlignment: Text.AlignHCenter
                                maximumLineCount: 1
                                wrapMode: Text.NoWrap
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                launcherWindow.recentKeyboardActive = true
                                recentGrid.currentIndex = index
                                executeApp(exec, name)
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Qt.alpha(Theme.white, 0.10)
                }
            }

            // Todas las aplicaciones siguen apareciendo aquí en orden alfabético.
            GridView {
                id: appGrid
                width: parent.width
                model: filteredModel
                cellWidth: parent.width / 6
                cellHeight: 110
                height: Math.min(Math.ceil(count / 6) * cellHeight,
                    recentSection.visible ? 330 : 440)
                currentIndex: 0
                clip: true
                visible: count > 0
                    && launcherWindow.calcResult === ""
                    && launcherWindow.currentMode === 0

                delegate: Rectangle {
                    width: appGrid.cellWidth - 10
                    height: appGrid.cellHeight - 10
                    anchors.margins: 5
                    radius: 14

                    color: GridView.isCurrentItem && !launcherWindow.recentKeyboardActive
                        ? Qt.alpha(Theme.white, 0.15)
                        : "transparent"

                    Column {
                        width: parent.width
                        anchors.centerIn: parent
                        spacing: 8

                        Item {
                            width: 56
                            height: 56
                            anchors.horizontalCenter: parent.horizontalCenter

                            Image {
                                anchors.fill: parent
                                visible: icon !== "__qs_cleanup__"
                                source: visible
                                    ? (icon.startsWith("/")
                                        ? "file://" + icon
                                        : "image://icon/" + icon)
                                    : ""
                                fillMode: Image.PreserveAspectFit
                                asynchronous: false
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: icon === "__qs_cleanup__"
                                text: ""
                                color: Theme.white
                                font.family: Theme.fontIcons
                                font.pixelSize: 40
                            }
                        }

                        Text {
                            width: parent.width - 8
                            anchors.horizontalCenter: parent.horizontalCenter

                            text: name
                            color: Theme.white

                            font.pixelSize: 12
                            font.family: Theme.fontMain

                            horizontalAlignment: Text.AlignHCenter

                            maximumLineCount: 1
                            wrapMode: Text.NoWrap
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor

                        onClicked: {
                            launcherWindow.recentKeyboardActive = false
                            recentGrid.currentIndex = -1
                            appGrid.currentIndex = index
                            executeApp(exec, name)
                        }
                    }
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

    function appendUnique(model, item) {
        var key = item.name + "\u001f" + item.exec + "\u001f" + item.type;
        for (var i = 0; i < model.count; i++) {
            var existing = model.get(i);
            var existingKey = existing.name + "\u001f" + existing.exec + "\u001f" + existing.type;
            if (existingKey === key)
                return;
        }
        model.append(item);
    }

    function loadAppsOnce() {
        if (appsModel.count > 0 || appsLoader.running)
            return;

        appsLoader.command = [
            "/bin/bash",
            "/home/javier/.config/quickshell/scripts/provider.sh",
            "--apps"
        ];
        appsLoader.running = true;
    }

    function showApps() {
        launcherWindow.currentMode = 0;
        launcherWindow.activeHeaderButton = 0;
        launcherWindow.recentKeyboardActive = false;
        recentGrid.currentIndex = -1;
        updateFilter();
        rebuildRecentModel();
    }

    function rememberRecent(name) {
        if (!name || name.trim() === "")
            return;

        var names = launcherWindow.recentNames.slice();
        var existingIndex = names.indexOf(name);
        if (existingIndex !== -1)
            names.splice(existingIndex, 1);

        names.unshift(name);
        if (names.length > 6)
            names = names.slice(0, 6);

        launcherWindow.recentNames = names;
        rebuildRecentModel();

        // Persist only on a user action. No daemon, polling or background loop.
        recentWriteProc.running = false;
        recentWriteProc.command = [
            "/bin/bash", "-c",
            "mkdir -p \"$HOME/.cache\"; printf '%s\\n' \"$1\" >> \"$HOME/.cache/qs_recents\"",
            "bash", name
        ];
        recentWriteProc.running = true;
    }

    function recentItemByName(name) {
        if (name === "Cleanup")
            return { name: "Cleanup", comment: "Storage & cache cleanup", icon: "__qs_cleanup__", exec: "qs_cleanup", type: "cmd" };

        for (var i = 0; i < appsModel.count; i++) {
            var app = appsModel.get(i);
            if (app.name === name)
                return app;
        }
        return null;
    }

    function loadRecents() {
        // One startup read only. Reopening never waits for disk/process I/O.
        launcherWindow.recentNames = [];
        recentLoader.running = false;
        recentLoader.command = [
            "/bin/bash", "-c",
            "test -f ~/.cache/qs_recents && tac ~/.cache/qs_recents | awk 'NF && !seen[$0]++' | head -n 6 || true"
        ];
        recentLoader.running = true;
    }

    function rebuildRecentModel() {
        recentModel.clear();
        if (launcherWindow.currentMode !== 0 || appsModel.count === 0)
            return;

        var added = {};
        for (var r = 0; r < launcherWindow.recentNames.length; r++) {
            var wanted = launcherWindow.recentNames[r];
            if (added[wanted])
                continue;

            var app = recentItemByName(wanted);
            if (app !== null) {
                recentModel.append(app);
                added[wanted] = true;
            }

            if (recentModel.count >= 6)
                break;
        }
    }

    function loadTabData(arg, extra = "") {
        // Nunca dejamos dos ejecuciones del provider solapadas. Si cambiamos
        // de vista mientras una anterior sigue produciendo stdout, sus líneas
        // podrían acabar mezclándose y duplicando aplicaciones.
        dataLoader.running = false;
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
        var sourceModel = launcherWindow.currentMode === 0 ? appsModel : rawModel;
        var seenResults = {};

        // Acción interna del launcher; no depende de provider.sh y se mantiene junto
        // a las apps normales para que también pueda encontrarse buscando "cleanup".
        var cleanupItem = { name: "Cleanup", comment: "Storage & cache cleanup", icon: "__qs_cleanup__", exec: "qs_cleanup", type: "cmd" };
        if (launcherWindow.currentMode === 0) {
            if (search === "" || cleanupItem.name.toLowerCase().includes(search) || cleanupItem.comment.toLowerCase().includes(search)) {
                var cleanupScore = 0;
                if (search !== "") {
                    cleanupScore = cleanupItem.name.toLowerCase().startsWith(search) ? 1
                                 : cleanupItem.name.toLowerCase().includes(search) ? 2
                                 : 3;
                }
                results.push({ item: cleanupItem, score: cleanupScore });
                seenResults[cleanupItem.name.toLowerCase()] = true;
            }
        }

        for (var j = 0; j < sourceModel.count; j++) {
            var item = sourceModel.get(j);
            if (item.type === "dummy" || item.type === "cmd" || item.exec.startsWith("qs_")) {
                if (item.exec !== "qs_sys" && item.exec !== "qs_wifi" && item.exec !== "qs_bt" && item.exec !== "qs_cleanup") continue; 
            }
            var itemName = item.name.toLowerCase();
            var itemComment = item.comment.toLowerCase();
            
            // De-duplicate by visible app name. This also protects the UI if
            // two .desktop sources expose the same application entry.
            var resultKey = item.name.toLowerCase();
            if (seenResults[resultKey])
                continue;

            if (search === "") {
                results.push({ item: item, score: 0 });
                seenResults[resultKey] = true;
            } else {
                if (itemName.startsWith(search)) {
                    results.push({ item: item, score: 1 });
                    seenResults[resultKey] = true;
                } else if (itemName.includes(search)) {
                    results.push({ item: item, score: 2 });
                    seenResults[resultKey] = true;
                } else if (itemComment.includes(search)) {
                    results.push({ item: item, score: 3 });
                    seenResults[resultKey] = true;
                }
            }
        }
        results.sort(function(a, b) { if (a.score !== b.score) return a.score - b.score; return a.item.name.localeCompare(b.item.name); });
        for (var k = 0; k < results.length; k++) { filteredModel.append(results[k].item); }
        appGrid.currentIndex = 0;
    }

    function executeApp(cmd, name) {
        if (!cmd || cmd === "") return;

        // Every selectable launcher entry participates in Recent.
        rememberRecent(name);

        if (cmd === "qs_sys") { launcherWindow.currentMode = 4; launcherWindow.activeHeaderButton = 0; searchInput.text = ""; loadTabData("--system"); return; }
        if (cmd === "qs_wifi") { launcherWindow.currentMode = 5; launcherWindow.activeHeaderButton = 0; searchInput.text = ""; loadTabData("--wifi"); return; }
        if (cmd === "qs_bt") { launcherWindow.currentMode = 6; launcherWindow.activeHeaderButton = 0; searchInput.text = ""; loadTabData("--bt"); return; }
        if (cmd === "qs_cleanup") {
            launcherWindow.currentMode = 10;
            launcherWindow.activeHeaderButton = 0;
            launcherWindow.cleanupSelection = 1;
            launcherWindow.cleanupConfirmSelection = 0;
            launcherWindow.cleanupConfirmVisible = false;
            launcherWindow.cleanupLastMessage = "";
            searchInput.text = "";
            loadCleanupStatus();
            return;
        }
        
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

        // System actions come from provider.sh as semantic tokens instead of
        // shell command strings. This avoids quoting/parsing issues and keeps
        // session-control logic out of the generic application launcher path.
        if (cmd === "qs_lock" || cmd === "qs_suspend" || cmd === "qs_logout"
                || cmd === "qs_reboot" || cmd === "qs_shutdown") {
            if (cmd === "qs_lock") launcherWindow.pendingSystemAction = "lock";
            else if (cmd === "qs_suspend") launcherWindow.pendingSystemAction = "suspend";
            else if (cmd === "qs_logout") launcherWindow.pendingSystemAction = "logout";
            else if (cmd === "qs_reboot") launcherWindow.pendingSystemAction = "reboot";
            else if (cmd === "qs_shutdown") launcherWindow.pendingSystemAction = "shutdown";

            // Release the Launcher surface/focus first. Lock is deliberately
            // started after the close animation so WlSessionLock does not race
            // with the overlay that initiated it.
            toggle();
            systemActionTimer.restart();
            return;
        }

        var cleanCmd = cmd.replace(/%[fFuUdDnNickvm]/g, "").replace("~", "/home/javier");
        WlrLayershell.keyboardFocus = WlrLayershell.None;

        // Backward compatibility for stale cached/provider entries.
        if (cleanCmd === "loginctl lock-session" || cleanCmd === "hyprlock") {
            launcherWindow.pendingSystemAction = "lock";
            toggle();
            systemActionTimer.restart();
            return;
        }

        if (cleanCmd === "systemctl suspend") {
            launcherWindow.pendingSystemAction = "suspend";
            toggle();
            systemActionTimer.restart();
            return;
        }

        if (cleanCmd === "hyprctl dispatch exit"
                || cleanCmd === "hyprctl dispatch 'hl.dsp.exit()'") {
            launcherWindow.pendingSystemAction = "logout";
            toggle();
            systemActionTimer.restart();
            return;
        }

        if (cleanCmd === "systemctl reboot") {
            launcherWindow.pendingSystemAction = "reboot";
            toggle();
            systemActionTimer.restart();
            return;
        }

        if (cleanCmd === "systemctl poweroff") {
            launcherWindow.pendingSystemAction = "shutdown";
            toggle();
            systemActionTimer.restart();
            return;
        }

        // Normal applications/files keep the existing launcher behaviour.
        // Hyprland >= 0.55 requires Lua dispatcher syntax.
        // History was already updated/persisted by rememberRecent().
        var fullCmd = "(" + cleanCmd + " & disown)";

        execProc.command = ["bash", "-c", fullCmd];
        execProc.running = true;

        toggle();
    }


    function loadCleanupStatus() {
        launcherWindow.isCleanupLoading = true;
        launcherWindow.cleanupError = "";
        cleanupStatusProc.output = "";
        cleanupStatusProc.command = ["/home/javier/.local/bin/cleanup.py", "--status-json"];
        cleanupStatusProc.running = true;
    }

    function runCleanup() {
        launcherWindow.isCleanupCleaning = true;
        launcherWindow.cleanupError = "";
        launcherWindow.cleanupLastMessage = "";
        cleanupActionProc.output = "";
        cleanupActionProc.command = ["/home/javier/.local/bin/cleanup.py", "--clear-cache-json"];
        cleanupActionProc.running = true;
    }

    function toggle() {
        if (visible_state) {
            // Hide immediately, but also clear transient modal state so it can
            // never survive into the next opening.
            visible_state = false;
            launcherWindow.cleanupConfirmVisible = false;
            launcherWindow.cleanupConfirmSelection = 0;
            closeTimer.start();
        } else {
            // Every fresh opening starts from the normal applications view,
            // even if the previous session was closed from Cleanup/Wi-Fi/etc.
            closeTimer.stop();
            launcherWindow.currentMode = 0;
            launcherWindow.activeHeaderButton = 0;
            launcherWindow.cleanupConfirmVisible = false;
            launcherWindow.cleanupConfirmSelection = 0;
            launcherWindow.cleanupSelection = 1;
            launcherWindow.recentKeyboardActive = false;
            recentGrid.currentIndex = -1;
            launcherWindow.targetWifiSsid = "";
            searchInput.echoMode = TextInput.Normal;
            searchInput.text = "";
            launcherWindow.calcResult = "";

            // La vista de apps ya se precarga al iniciar y también al terminar
            // el cierre. No volvemos a lanzar provider.sh aquí: evita carreras,
            // duplicados y hace que el launcher reaparezca de forma inmediata.
            updateFilter();

            isReallyVisible = true;
            visible_state = true;
            WlrLayershell.keyboardFocus = WlrLayershell.OnDemand;

            // App grid and Recent row are already cached in memory.
            rebuildRecentModel();
            searchInput.forceActiveFocus();
        }
    }
}