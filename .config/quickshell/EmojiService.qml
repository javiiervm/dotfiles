import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "components"

pragma Singleton

Singleton {
    id: root

    // DockConfig references this singleton, which keeps the picker alive for
    // the lifetime of the main Quickshell instance.
    property alias picker: pickerWindow

    EmojiPicker {
        id: pickerWindow
    }

    // Native Hyprland global-shortcut protocol. This is considerably faster
    // than spawning `qs ipc ...` every time SUPER + . is pressed.
    GlobalShortcut {
        name: "emoji"
        description: "Emoji picker"

        onPressed: root.picker.togglePicker()
    }

    // Keep IPC available for manual testing/debugging.
    IpcHandler {
        target: "emoji"

        function toggle(): void {
            root.picker.togglePicker()
        }

        function open(): void {
            root.picker.openPicker()
        }

        function close(): void {
            root.picker.closePicker(true)
        }
    }
}
