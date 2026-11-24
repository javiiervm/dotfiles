#!/usr/bin/env bash

set -euo pipefail

# --- CONFIGURATION ---

MARGIN_LEFT=14
MARGIN_RIGHT=14
MARGIN_TOP=48
MARGIN_BOTTOM=86
WINDOW_GAP=12
HYPRBARS_FALLBACK_HEIGHT=34

MACOS_STATE_FILE="/tmp/hypr_macos_mode"
MAX_STATE_DIR="/tmp/hypr_macos_maximize"

ACTION="${1:-}"
DIRECTION="${2:-}"

# --- HELPERS ---

dispatch() {
    hyprctl dispatch "$1" >/dev/null
}

macos_mode_active() {
    [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] &&
    [ -f "$MACOS_STATE_FILE" ] &&
    [ "$(head -n 1 "$MACOS_STATE_FILE")" = \
        "$HYPRLAND_INSTANCE_SIGNATURE" ]
}

titlebar_height() {
    if ! hyprctl plugin list 2>/dev/null |
        grep -qi 'Plugin hyprbars'; then
        echo 0
        return
    fi

    local height

    height=$(hyprctl -j getoption \
        plugin:hyprbars:bar_height 2>/dev/null |
        jq -r '.int // empty' || true)

    echo "${height:-$HYPRBARS_FALLBACK_HEIGHT}"
}

clear_maximize_state() {
    rm -f "$MAX_STATE_DIR/${1#0x}.json"
}

apply_geometry() {
    local addr="$1"
    local x="$2"
    local y="$3"
    local w="$4"
    local h="$5"

    [ "$w" -gt 0 ] && [ "$h" -gt 0 ] || return 1

    dispatch "hl.dsp.window.resize({
        window = 'address:$addr',
        x = $w,
        y = $h,
        relative = false
    })"

    dispatch "hl.dsp.window.move({
        window = 'address:$addr',
        x = $x,
        y = $y,
        relative = false
    })"

    clear_maximize_state "$addr"
}

# --- CHECK MODE ---

macos_mode_active || exit 0

WIN=$(hyprctl activewindow -j)

ADDR=$(jq -r '.address // empty' <<< "$WIN")

[ -n "$ADDR" ] || exit 0

FLOATING=$(jq -r '.floating' <<< "$WIN")
FULLSCREEN=$(jq -r '.fullscreen // 0' <<< "$WIN")

[ "$FLOATING" = "true" ] || exit 0
[ "$FULLSCREEN" = "0" ] || exit 0

# --- CURRENT WINDOW GEOMETRY ---

CUR_X=$(jq -r '.at[0]' <<< "$WIN")
CUR_Y=$(jq -r '.at[1]' <<< "$WIN")
CUR_W=$(jq -r '.size[0]' <<< "$WIN")
CUR_H=$(jq -r '.size[1]' <<< "$WIN")

# --- MONITOR GEOMETRY ---

MONITOR_ID=$(jq -r '.monitor' <<< "$WIN")

MONITOR=$(hyprctl monitors -j |
    jq -c --argjson id "$MONITOR_ID" \
    '.[] | select(.id == $id)')

[ -n "$MONITOR" ] || exit 0

MON_X=$(jq -r '.x' <<< "$MONITOR")
MON_Y=$(jq -r '.y' <<< "$MONITOR")

MON_W=$(jq -r '(.width / .scale) | floor' <<< "$MONITOR")
MON_H=$(jq -r '(.height / .scale) | floor' <<< "$MONITOR")

TITLEBAR=$(titlebar_height)

# --- AVAILABLE WORK AREA ---

AREA_X=$((MON_X + MARGIN_LEFT))
AREA_Y=$((MON_Y + MARGIN_TOP))

AREA_W=$((MON_W - MARGIN_LEFT - MARGIN_RIGHT))
AREA_H=$((MON_H - MARGIN_TOP - MARGIN_BOTTOM))

HALF_W=$(((AREA_W - WINDOW_GAP) / 2))
HALF_H=$(((AREA_H - WINDOW_GAP) / 2))

# --- WINDOW SNAPPING ---

snap_window() {
    local x="$AREA_X"
    local y=$((AREA_Y + TITLEBAR))
    local w="$AREA_W"
    local h=$((AREA_H - TITLEBAR))

    case "$DIRECTION" in
        left)
            w="$HALF_W"
            ;;
        right)
            x=$((AREA_X + HALF_W + WINDOW_GAP))
            w=$((AREA_W - HALF_W - WINDOW_GAP))
            ;;
        up)
            h=$((HALF_H - TITLEBAR))
            ;;
        down)
            y=$((AREA_Y + HALF_H + WINDOW_GAP + TITLEBAR))
            h=$((AREA_H - HALF_H - WINDOW_GAP - TITLEBAR))
            ;;
        *)
            return 1
            ;;
    esac

    apply_geometry "$ADDR" "$x" "$y" "$w" "$h"
}

# --- CENTER WINDOW ---

center_window() {
    local x=$((AREA_X + (AREA_W - CUR_W) / 2))
    local y=$((AREA_Y + (AREA_H - CUR_H + TITLEBAR) / 2))

    apply_geometry \
        "$ADDR" "$x" "$y" "$CUR_W" "$CUR_H"
}

# --- DIRECTIONAL WINDOW SWAP ---

swap_window() {
    local target

    target=$(hyprctl clients -j | jq -c \
        --argjson active "$WIN" \
        --arg dir "$DIRECTION" '

        def cx: .at[0] + .size[0] / 2;
        def cy: .at[1] + .size[1] / 2;

        [
            .[]
            | select(
                .address != $active.address
                and .workspace.id == $active.workspace.id
                and .monitor == $active.monitor
                and .floating == true
                and .mapped == true
                and (.hidden != true)
                and (.fullscreen == 0)
            )
            | . + {
                dx: (cx - ($active | cx)),
                dy: (cy - ($active | cy))
            }
            | select(
                ($dir == "left"  and .dx < 0) or
                ($dir == "right" and .dx > 0) or
                ($dir == "up"    and .dy < 0) or
                ($dir == "down"  and .dy > 0)
            )
        ]
        | sort_by(
            if $dir == "left" or $dir == "right"
            then (.dx * .dx + 4 * .dy * .dy)
            else (4 * .dx * .dx + .dy * .dy)
            end
        )
        | first // empty
    ')

    [ -n "$target" ] || return 0

    local addr x y w h

    addr=$(jq -r '.address' <<< "$target")
    x=$(jq -r '.at[0]' <<< "$target")
    y=$(jq -r '.at[1]' <<< "$target")
    w=$(jq -r '.size[0]' <<< "$target")
    h=$(jq -r '.size[1]' <<< "$target")

    apply_geometry "$addr" \
        "$CUR_X" "$CUR_Y" "$CUR_W" "$CUR_H"

    apply_geometry "$ADDR" "$x" "$y" "$w" "$h"
}

# --- ENTRY POINT ---

case "$ACTION" in
    snap)
        snap_window
        ;;
    center)
        center_window
        ;;
    swap)
        swap_window
        ;;
    *)
        exit 1
        ;;
esac
