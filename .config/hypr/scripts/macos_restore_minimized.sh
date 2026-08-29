#!/usr/bin/env bash

# ============================================================
# Instant restore
#
# Restores a window previously hidden by macos_minimize.sh.
#
# The window is restored without animation, then its normal
# animation behaviour is re-enabled.
# ============================================================

set -u


# ============================================================
# PATHS
# ============================================================

STATE_DIR="$HOME/.local/state/hypr/minimized"


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
# Address
# ============================================================

addr="${1:-}"

[ -z "$addr" ] && exit 0


addr_clean="${addr#0x}"
addr="0x$addr_clean"


STATE_FILE="$STATE_DIR/${addr_clean}.json"


# ============================================================
# Validate
# ============================================================

[ -f "$STATE_FILE" ] || exit 0


if ! window_exists "$addr"; then
    rm -f "$STATE_FILE"
    exit 0
fi


# ============================================================
# Read saved state
# ============================================================

state=$(cat "$STATE_FILE")


workspace=$(jq -r '.workspace' <<< "$state")
floating=$(jq -r '.floating' <<< "$state")

x=$(jq -r '.x' <<< "$state")
y=$(jq -r '.y' <<< "$state")

w=$(jq -r '.w' <<< "$state")
h=$(jq -r '.h' <<< "$state")


# ============================================================
# Keep animations disabled while restoring
# ============================================================

dispatch \
    "hl.dsp.window.set_prop({
        prop = 'no_anim',
        value = '1',
        window = 'address:$addr'
    })"


# ============================================================
# Return instantly to original workspace
# ============================================================

dispatch \
    "hl.dsp.window.move({
        workspace = '$workspace',
        follow = true,
        window = 'address:$addr'
    })"


# ============================================================
# Restore original state
# ============================================================

if [ "$floating" = "true" ]; then

    dispatch \
        "hl.dsp.window.float({
            action = 'on',
            window = 'address:$addr'
        })"


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

else

    dispatch \
        "hl.dsp.window.float({
            action = 'off',
            window = 'address:$addr'
        })"

fi


# ============================================================
# Focus / raise
# ============================================================

dispatch \
    "hl.dsp.focus({
        window = 'address:$addr'
    })"


dispatch \
    "hl.dsp.window.raise({
        window = 'address:$addr'
    })"


# ============================================================
# Restore normal animation behaviour
#
# "unset" removes our temporary no_anim override, so the window
# goes back to following your normal Hyprland animation config.
# ============================================================

dispatch \
    "hl.dsp.window.set_prop({
        prop = 'no_anim',
        value = 'unset',
        window = 'address:$addr'
    })"


# ============================================================
# Cleanup
# ============================================================

rm -f "$STATE_FILE"


exit 0