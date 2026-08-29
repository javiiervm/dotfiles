#!/usr/bin/env bash

# ============================================================
# Laptop lid / external monitor handler
# Hyprland 0.56+ / Lua configuration
#
# Behaviour:
#
# Lid closed + HDMI:
#   1. Disable eDP-1
#   2. Move HDMI-A-1 to 0x0
#   3. Refresh Quickshell LAST
#
# Lid opened:
#   1. Re-enable eDP-1 safely
#   2. Restore the normal two-monitor layout
#   3. Refresh Quickshell LAST
#
# Fully event-driven:
#   - no polling
#   - no daemon
#   - no persistent background process
# ============================================================

set -u


# ============================================================
# CONFIGURATION
# ============================================================

INTERNAL="eDP-1"
EXTERNAL="HDMI-A-1"

QUICKSHELL_REFRESH="$HOME/.config/quickshell/scripts/launch.sh"


# ============================================================
# HELPERS
# ============================================================

monitor_connected() {
    local monitor="$1"

    hyprctl -j monitors all 2>/dev/null |
        jq -e --arg name "$monitor" \
            '.[] | select(.name == $name)' \
            >/dev/null
}


hypr_eval() {
    hyprctl eval "$1"
}


refresh_quickshell() {
    # This is deliberately the LAST operation after the monitor
    # layout has reached its final state.
    #
    # launch.sh is the same refresh mechanism used by SUPER+R.
    if [ -x "$QUICKSHELL_REFRESH" ]; then
        "$QUICKSHELL_REFRESH"
    fi
}


# ============================================================
# ACTION
# ============================================================

ACTION="${1:-}"

case "$ACTION" in

    # ========================================================
    # LID CLOSED
    # ========================================================

    close)

        # ----------------------------------------------------
        # Only enter clamshell mode if HDMI-A-1 is connected.
        #
        # Without an external monitor we deliberately do
        # nothing, preserving the normal systemd lid/suspend
        # behaviour.
        # ----------------------------------------------------

        if ! monitor_connected "$EXTERNAL"; then
            exit 0
        fi


        # ----------------------------------------------------
        # 1. Remove eDP-1 FIRST.
        #
        # HDMI is currently auto-left while eDP is at 0x0.
        # Disabling eDP before moving HDMI prevents temporary
        # monitor overlap.
        # ----------------------------------------------------

        hypr_eval \
            'hl.monitor({
                output = "eDP-1",
                disabled = true
            })'


        # ----------------------------------------------------
        # 2. HDMI is now the only active output.
        #    Make it the desktop origin.
        # ----------------------------------------------------

        hypr_eval \
            'hl.monitor({
                output = "HDMI-A-1",
                disabled = false,
                mode = "preferred",
                position = "0x0",
                scale = 1
            })'


        # ----------------------------------------------------
        # 3. LAST OPERATION:
        #    Restart Quickshell after Wayland/Hyprland already
        #    expose the definitive one-monitor topology.
        # ----------------------------------------------------

        refresh_quickshell

        ;;


    # ========================================================
    # LID OPENED
    # ========================================================

    open)

        if monitor_connected "$EXTERNAL"; then

            # ------------------------------------------------
            # 1. Re-enable eDP-1 temporarily to the right.
            #
            # HDMI is currently at 0x0, so enabling eDP
            # directly at 0x0 would cause overlap.
            # ------------------------------------------------

            hypr_eval \
                'hl.monitor({
                    output = "eDP-1",
                    disabled = false,
                    mode = "2560x1600@60",
                    position = "auto-right",
                    scale = 1.33
                })'


            # ------------------------------------------------
            # 2. Return HDMI to its normal place on the left.
            # ------------------------------------------------

            hypr_eval \
                'hl.monitor({
                    output = "HDMI-A-1",
                    disabled = false,
                    mode = "preferred",
                    position = "auto-left",
                    scale = 1
                })'


            # ------------------------------------------------
            # 3. Put eDP-1 back at the definitive origin.
            #
            # Final normal layout:
            #
            #   HDMI-A-1       eDP-1
            #   auto-left      0x0
            #   scale 1        scale 1.33
            # ------------------------------------------------

            hypr_eval \
                'hl.monitor({
                    output = "eDP-1",
                    disabled = false,
                    mode = "2560x1600@60",
                    position = "0x0",
                    scale = 1.33
                })'

        else

            # ------------------------------------------------
            # HDMI was disconnected while the lid was closed.
            #
            # Restore eDP-1 as the standalone display.
            # ------------------------------------------------

            hypr_eval \
                'hl.monitor({
                    output = "eDP-1",
                    disabled = false,
                    mode = "2560x1600@60",
                    position = "0x0",
                    scale = 1.33
                })'

        fi


        # ----------------------------------------------------
        # 4. LAST OPERATION:
        #    Restart Quickshell only after the monitor topology
        #    is fully restored.
        # ----------------------------------------------------

        refresh_quickshell

        ;;


    *)
        echo "Usage: $0 {close|open}" >&2
        exit 2
        ;;

esac