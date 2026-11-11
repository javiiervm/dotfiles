#!/usr/bin/env bash

# ============================================================
# macOS-style maximize / restore
#
# SUPER + D
#
# Normal Hyprland mode:
#   - Uses native Hyprland maximize toggle.
#
# macOS mode:
#   - Uses manually tunable margins.
#   - Compensates for the Hyprbars titlebar ABOVE the client.
#   - Press SUPER + D again to restore the previous geometry.
# ============================================================

set -u


# ============================================================
# CONFIGURATION
# ============================================================

MARGIN_LEFT=14
MARGIN_RIGHT=14

# This is the desired margin between the SCREEN TOP and the
# TOP EDGE OF THE TITLEBAR (not the application's content).
# Quickshell reserves 44 logical pixels for the laptop top bar.
MARGIN_TOP=48

MARGIN_BOTTOM=86

# Matches bar_height in toggle_macos.sh. Used only as a fallback
# if Hyprland cannot report the actual plugin configuration.
HYPRBARS_FALLBACK_HEIGHT=34


# ============================================================
# INTERNAL PATHS
# ============================================================

MACOS_STATE_FILE="/tmp/hypr_macos_mode"
MAX_STATE_DIR="/tmp/hypr_macos_maximize"


# ============================================================
# Helpers
# ============================================================

dispatch() {
    hyprctl dispatch "$1" >/dev/null 2>&1
}


macos_mode_active() {
    [ -f "$MACOS_STATE_FILE" ] || return 1

    local current_instance="${HYPRLAND_INSTANCE_SIGNATURE:-}"
    local saved_instance

    [ -n "$current_instance" ] || return 1

    saved_instance=$(head -n 1 "$MACOS_STATE_FILE" 2>/dev/null || true)

    [ -n "$saved_instance" ] || return 1
    [ "$saved_instance" = "$current_instance" ]
}


# Hyprbars paints its bar ABOVE the client window geometry.
# Therefore setting the client top to 48 would place the actual
# decoration at about 48 - 34 = 14, overlapping Quickshell.
#
# Only while Hyprbars is loaded, add its real height to the
# client's top margin. This leaves the visible bar at 48 and
# keeps the original bottom margin unchanged.
hyprbars_titlebar_height() {
    if ! hyprctl plugin list 2>/dev/null | grep -qi 'Plugin hyprbars'; then
        printf '0\n'
        return
    fi

    local height
    height=$(
        hyprctl -j getoption plugin:hyprbars:bar_height 2>/dev/null |
            jq -r '.int // empty' 2>/dev/null
    )

    case "$height" in
        ''|*[!0-9]*) height="$HYPRBARS_FALLBACK_HEIGHT" ;;
    esac

    printf '%s\n' "$height"
}


# ============================================================
# Get active window
# ============================================================

win=$(hyprctl activewindow -j 2>/dev/null)

addr=$(jq -r '.address // empty' <<< "$win")

if [ -z "$addr" ]; then
    exit 0
fi


# ============================================================
# Normal Hyprland mode
# ============================================================

if ! macos_mode_active; then

    dispatch \
        "hl.dsp.window.fullscreen({
            mode = 'maximized',
            action = 'toggle',
            window = 'address:$addr'
        })"

    exit 0
fi


# ============================================================
# macOS mode
# ============================================================

mkdir -p "$MAX_STATE_DIR"

STATE_KEY="$MAX_STATE_DIR/${addr#0x}.json"


# ============================================================
# Restore previous geometry
# ============================================================

if [ -f "$STATE_KEY" ]; then

    prev=$(cat "$STATE_KEY")

    x=$(jq -r '.x' <<< "$prev")
    y=$(jq -r '.y' <<< "$prev")

    w=$(jq -r '.w' <<< "$prev")
    h=$(jq -r '.h' <<< "$prev")

    dispatch \
        "hl.dsp.window.resize({
            x = $w,
            y = $h,
            relative = false,
            window = 'address:$addr'
        })"

    dispatch \
        "hl.dsp.window.move({
            x = $x,
            y = $y,
            relative = false,
            window = 'address:$addr'
        })"

    rm -f "$STATE_KEY"

    exit 0
fi


# ============================================================
# Save current geometry
# ============================================================

cur_x=$(jq -r '.at[0]' <<< "$win")
cur_y=$(jq -r '.at[1]' <<< "$win")

cur_w=$(jq -r '.size[0]' <<< "$win")
cur_h=$(jq -r '.size[1]' <<< "$win")

printf \
    '{"x":%d,"y":%d,"w":%d,"h":%d}\n' \
    "$cur_x" \
    "$cur_y" \
    "$cur_w" \
    "$cur_h" \
    > "$STATE_KEY"


# ============================================================
# Detect monitor containing the active window
# ============================================================

monitor_id=$(jq -r '.monitor' <<< "$win")

monitor=$(hyprctl monitors -j 2>/dev/null |
    jq -c --argjson id "$monitor_id" \
        '.[] | select(.id == $id)')

if [ -z "$monitor" ]; then
    exit 1
fi

MONITOR_X=$(jq -r '.x' <<< "$monitor")
MONITOR_Y=$(jq -r '.y' <<< "$monitor")

MONITOR_WIDTH=$(jq -r '.width' <<< "$monitor")
MONITOR_HEIGHT=$(jq -r '.height' <<< "$monitor")

MONITOR_SCALE=$(jq -r '.scale' <<< "$monitor")


# ============================================================
# Convert monitor dimensions to Hyprland logical coordinates
# ============================================================

LOGICAL_WIDTH=$(awk \
    "BEGIN { printf \"%d\", $MONITOR_WIDTH / $MONITOR_SCALE }")

LOGICAL_HEIGHT=$(awk \
    "BEGIN { printf \"%d\", $MONITOR_HEIGHT / $MONITOR_SCALE }")


# ============================================================
# Calculate target geometry from margins
# ============================================================

# This extra is zero without Hyprbars, so the old behavior
# is preserved if the plugin is unavailable or unloaded.
TITLEBAR_HEIGHT=$(hyprbars_titlebar_height)

# The client must start LOWER to leave room for its decoration.
EFFECTIVE_MARGIN_TOP=$((MARGIN_TOP + TITLEBAR_HEIGHT))

TARGET_X=$((MONITOR_X + MARGIN_LEFT))
TARGET_Y=$((MONITOR_Y + EFFECTIVE_MARGIN_TOP))

TARGET_WIDTH=$((LOGICAL_WIDTH - MARGIN_LEFT - MARGIN_RIGHT))
TARGET_HEIGHT=$((LOGICAL_HEIGHT - EFFECTIVE_MARGIN_TOP - MARGIN_BOTTOM))

# Prevent invalid geometry.
if [ "$TARGET_WIDTH" -lt 1 ] || [ "$TARGET_HEIGHT" -lt 1 ]; then
    rm -f "$STATE_KEY"
    exit 1
fi


# ============================================================
# Apply maximized geometry
# ============================================================

dispatch \
    "hl.dsp.window.resize({
        x = $TARGET_WIDTH,
        y = $TARGET_HEIGHT,
        relative = false,
        window = 'address:$addr'
    })"

dispatch \
    "hl.dsp.window.move({
        x = $TARGET_X,
        y = $TARGET_Y,
        relative = false,
        window = 'address:$addr'
    })"
