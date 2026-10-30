
import QtQuick
import Quickshell
import Quickshell.Io

// AI Selection v0.4: separate, persistent Quickshell instance.
// The existing desktop shell and Xavion are intentionally untouched.
Scope {
    id: service

    property bool opening: false
    property bool active: false
    property int session: 0
    property int pendingScreens: 0
    property bool selectionCompleted: false
    property bool selectionInProgress: false

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
        }
    }

    // Shared state: the blue overlay fades from every screen as soon as
    // the user begins dragging on any monitor.
    function beginRegionSelection() {
        selectionCompleted = false
        selectionInProgress = true
        selectionsCleared()
    }

    function completeRegionSelection() {
        // Set the completed flag first so the blue overlay never flashes
        // back between releasing the mouse and showing the action menu.
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
