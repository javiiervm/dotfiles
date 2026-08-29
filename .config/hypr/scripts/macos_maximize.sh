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
#   - Press SUPER + D again to restore the previous geometry.
# ============================================================

set -u


# ============================================================
# CONFIGURATION
# ============================================================

MARGIN_LEFT=14
MARGIN_RIGHT=14
MARGIN_TOP=48
MARGIN_BOTTOM=86


# ============================================================
# INTERNAL PATHS
# ============================================================

MACOS_STATE_FILE="/tmp/hypr_macos_mode"
MAX_STATE_DIR="/tmp/hypr_macos_maximize"


# ============================================================
# Helper
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

TARGET_X=$((MONITOR_X + MARGIN_LEFT))
TARGET_Y=$((MONITOR_Y + MARGIN_TOP))

TARGET_WIDTH=$((LOGICAL_WIDTH - MARGIN_LEFT - MARGIN_RIGHT))
TARGET_HEIGHT=$((LOGICAL_HEIGHT - MARGIN_TOP - MARGIN_BOTTOM))


# Prevent invalid geometry
if [ "$TARGET_WIDTH" -lt 1 ] || [ "$TARGET_HEIGHT" -lt 1 ]; then
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