import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// AI Selection: independent, persistent Quickshell instance.
// No process is launched per click: Hyprland dispatches a native shortcut.
Scope {
    id: service

    property bool opening: false
    property bool active: false
    property int session: 0
    property int pendingScreens: 0
    property bool selectionCompleted: false
    property bool selectionInProgress: false
    property double snapshotStartedAt: 0

    signal snapshotRequested(int session)
    signal dismissed()
    signal selectionsCleared()

    function openSelection() {
        if (opening || active)
            return

        pendingScreens = Quickshell.screens.length
        if (pendingScreens === 0)
            return

        ++session
        selectionCompleted = false
        selectionInProgress = false
        snapshotStartedAt = Date.now()
        opening = true
        snapshotRequested(session)
    }

    function snapshotReady(requestSession) {
        if (!opening || requestSession !== session)
            return

        --pendingScreens
        if (pendingScreens === 0) {
            opening = false
            active = true
            console.info("AI Selection: frozen screenshots ready in "
                         + (Date.now() - snapshotStartedAt) + " ms")
        }
    }

    // Blue overlay fades across all monitors when a region begins.
    function beginRegionSelection() {
        selectionCompleted = false
        selectionInProgress = true
        selectionsCleared()
    }

    function completeRegionSelection() {
        selectionCompleted = true
        selectionInProgress = false
    }

    function cancelRegionSelection() {
        selectionInProgress = false
        selectionCompleted = false
    }

    function abortSelection() {
        if (!opening && !active)
            return

        active = false
        opening = false
        selectionCompleted = false
        selectionInProgress = false
        ++session
        dismissed()
    }

    // Fast path: Hyprland's global-shortcuts Wayland protocol, avoiding
    // spawning the `qs ipc` command for every Super + left-click.
    GlobalShortcut {
        name: "ai_selection"
        description: "Open AI Selection"
        onPressed: service.openSelection()
    }

    // Keep the previous IPC interface for testing and manual invocation.
    IpcHandler {
        target: "aiselection"

        function open(): void {
            service.openSelection()
        }

        function close(): void {
            service.abortSelection()
        }
    }

    Variants {
        model: Quickshell.screens

        AISelectionOverlay {
            controller: service
        }
    }
}
