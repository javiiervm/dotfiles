#!/usr/bin/env bash

# ============================================================
# Instant minimize
#
# SUPER + H
#
# Saves the current window state and immediately hides it in:
#
#     special:minimized
#
# Animations are temporarily disabled only for this window.
# ============================================================

set -u


# ============================================================
# PATHS
# ============================================================

STATE_DIR="$HOME/.local/state/hypr/minimized"

mkdir -p "$STATE_DIR"


# ============================================================
# HELPERS
# ============================================================

dispatch() {
    hyprctl dispatch "$1" >/dev/null 2>&1
}


window_exists() {
    local addr="$1"

    hyprctl clients -j 2>/dev/null |
        jq -e \
            --arg addr "$addr" \
            '.[] | select(.address == $addr)' \
            >/dev/null 2>&1
}


# ============================================================
# Get target window
# ============================================================

addr="${1:-}"

if [ -z "$addr" ]; then
    addr=$(
        hyprctl activewindow -j 2>/dev/null |
            jq -r '.address // empty'
    )
fi


[ -z "$addr" ] && exit 0


addr_clean="${addr#0x}"
addr="0x$addr_clean"


window_exists "$addr" || exit 0


# ============================================================
# State file
# ============================================================

STATE_FILE="$STATE_DIR/${addr_clean}.json"


# Already minimized
[ -f "$STATE_FILE" ] && exit 0


# ============================================================
# Read window state
# ============================================================

win=$(
    hyprctl clients -j 2>/dev/null |
        jq -c \
            --arg addr "$addr" \
            '.[] | select(.address == $addr)'
)


[ -z "$win" ] && exit 0


floating=$(jq -r '.floating' <<< "$win")

workspace=$(jq -r '.workspace.name' <<< "$win")

x=$(jq -r '.at[0]' <<< "$win")
y=$(jq -r '.at[1]' <<< "$win")

w=$(jq -r '.size[0]' <<< "$win")
h=$(jq -r '.size[1]' <<< "$win")

title=$(jq -r '.title' <<< "$win")
class=$(jq -r '.class' <<< "$win")

monitor=$(jq -r '.monitor' <<< "$win")


# ============================================================
# Save original state
# ============================================================

jq -n \
    --arg workspace "$workspace" \
    --argjson floating "$floating" \
    --argjson monitor "$monitor" \
    --argjson x "$x" \
    --argjson y "$y" \
    --argjson w "$w" \
    --argjson h "$h" \
    --arg title "$title" \
    --arg class "$class" \
    '{
        workspace: $workspace,
        floating: $floating,
        monitor: $monitor,
        x: $x,
        y: $y,
        w: $w,
        h: $h,
        title: $title,
        class: $class
    }' \
    > "$STATE_FILE"


# ============================================================
# Disable animations for THIS window only
# ============================================================

dispatch \
    "hl.dsp.window.set_prop({
        prop = 'no_anim',
        value = '1',
        window = 'address:$addr'
    })"


# ============================================================
# Hide instantly
# ============================================================

dispatch \
    "hl.dsp.window.move({
        workspace = 'special:minimized',
        follow = false,
        window = 'address:$addr'
    })"


exit 0