pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    /*
     * ============================================================
     * GLOBAL GLASS MODE
     * ============================================================
     *
     * classic
     *     Quickshell usa el blur normal de Hyprland.
     *
     * liquid
     *     Las superficies migradas usan HyprGlass Liquid Glass.
     *
     * El estado persistente se guarda fuera del repo:
     *
     * $XDG_STATE_HOME/quickshell/glass-mode
     *
     * normalmente:
     *
     * ~/.local/state/quickshell/glass-mode
     *
     * La antigua ubicación:
     *
     * ~/.config/quickshell/state/glass-mode
     *
     * se conserva únicamente como fuente de migración.
     */


    // ============================================================
    // PATHS
    // ============================================================

    readonly property string stateHome:
        Quickshell.env("XDG_STATE_HOME")
        || (Quickshell.env("HOME") + "/.local/state")

    readonly property string stateFile:
        stateHome + "/quickshell/glass-mode"

    readonly property string legacyStateFile:
        Quickshell.env("HOME")
        + "/.config/quickshell/state/glass-mode"


    // ============================================================
    // STATE
    // ============================================================

    property string mode: "liquid"

    /*
     * Último modo confirmado en disco.
     *
     * Nos permite restaurar correctamente el estado visual si alguna
     * escritura falla.
     */
    property string committedMode: "liquid"

    property bool loaded: false
    property bool writeSucceeded: false


    // ============================================================
    // CONVENIENCE PROPERTIES
    // ============================================================

    readonly property bool liquid:
        mode === "liquid"

    readonly property bool classic:
        mode === "classic"


    /*
     * En modo Liquid Glass queremos que GlassSurface siga aportando
     * una capa QML ligera de color/transparencia, pero que el material
     * óptico real lo genere HyprGlass.
     *
     * Este valor queda centralizado aquí para que todas las superficies
     * migradas utilicen exactamente el mismo comportamiento.
     */
    readonly property real liquidQmlOpacity: 0.23


    // ============================================================
    // INITIAL STATE READER
    // ============================================================

    Process {
        id: stateReader

        running: true

        command: [
            "bash",
            "-c",

            "state_dir=\"${XDG_STATE_HOME:-$HOME/.local/state}/quickshell\"; "
            + "state_file=\"$state_dir/glass-mode\"; "
            + "legacy=\"$HOME/.config/quickshell/state/glass-mode\"; "

            + "mkdir -p \"$state_dir\"; "

            + "if [ -r \"$state_file\" ]; then "

            + "    cat \"$state_file\"; "

            + "elif [ -r \"$legacy\" ]; then "

            + "    mode=$(head -n 1 \"$legacy\"); "
            + "    [ \"$mode\" = classic ] || mode=liquid; "
            + "    printf '%s\\n' \"$mode\" > \"$state_file\"; "
            + "    printf '%s\\n' \"$mode\"; "

            + "else "

            + "    printf '%s\\n' liquid > \"$state_file\"; "
            + "    printf '%s\\n' liquid; "

            + "fi"
        ]

        stdout: SplitParser {
            onRead: function(data) {
                var value = data.trim()

                root.mode =
                    value === "classic"
                    ? "classic"
                    : "liquid"

                root.committedMode =
                    root.mode

                root.loaded = true
            }
        }
    }


    // ============================================================
    // STATE WRITER
    // ============================================================

    Process {
        id: stateWriter

        stdout: SplitParser {
            onRead: function(data) {
                var value = data.trim()

                if (
                    value === "classic"
                    || value === "liquid"
                ) {
                    root.mode = value
                    root.committedMode = value
                    root.writeSucceeded = true
                }
            }
        }

        onRunningChanged: {
            if (running || !root.loaded)
                return

            if (root.writeSucceeded) {
                /*
                 * Hyprland vuelve a leer la configuración del modo
                 * seleccionado.
                 */
                if (!hyprReload.running)
                    hyprReload.running = true
            } else {
                /*
                 * Si la escritura falla, no dejamos la UI mostrando
                 * un modo que Hyprland nunca llegó a aplicar.
                 */
                root.mode = root.committedMode
            }
        }
    }


    // ============================================================
    // HYPRLAND RELOAD
    // ============================================================

    Process {
        id: hyprReload

        command: [
            "hyprctl",
            "reload"
        ]
    }


    // ============================================================
    // PUBLIC API
    // ============================================================

    function setMode(newMode) {
        if (!root.loaded)
            return

        if (stateWriter.running)
            return

        if (
            newMode !== "classic"
            && newMode !== "liquid"
        )
            return

        if (root.mode === newMode)
            return


        // --------------------------------------------------------
        // Immediate QML update
        // --------------------------------------------------------

        root.mode = newMode

        root.writeSucceeded = false


        // --------------------------------------------------------
        // Persistent state
        // --------------------------------------------------------

        stateWriter.command = [
            "bash",
            "-c",

            "state_dir=\"${XDG_STATE_HOME:-$HOME/.local/state}/quickshell\"; "
            + "mkdir -p \"$state_dir\" && "
            + "printf '%s\\n' '"
            + newMode
            + "' > \"$state_dir/glass-mode\" && "
            + "printf '%s\\n' '"
            + newMode
            + "'"
        ]

        stateWriter.running = true
    }


    function toggle() {
        root.setMode(
            root.liquid
            ? "classic"
            : "liquid"
        )
    }
}
