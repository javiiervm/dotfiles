#!/usr/bin/env bash

# ============================================================
# macOS-style maximize / restore
#
# SUPER + D
#
# Normal mode:
#   Toggle Hyprland maximized state.
#
# macOS mode:
#   Also use Hyprland's native maximized state.
#
# Hyprland itself remembers/restores the previous floating
# geometry when toggling maximization, so there is no need
# for hardcoded monitor dimensions.
# ============================================================

set -u


STATE_FILE="/tmp/hypr_macos_mode"


# ============================================================
# Get active window
# ============================================================

win=$(hyprctl activewindow -j 2>/dev/null)

addr=$(jq -r '.address // empty' <<< "$win")


if [ -z "$addr" ]; then
    exit 0
fi


# ============================================================
# Toggle maximized state
#
# This is intentionally NOT real fullscreen.
#
# "maximized" keeps Hyprland's normal reserved areas and is
# much closer to the green maximize behaviour expected from
# the macOS-style window mode.
# ============================================================

hyprctl dispatch \
    "hl.dsp.window.fullscreen({
        mode = 'maximized',
        action = 'toggle',
        window = 'address:$addr'
    })" \
    >/dev/null 2>&1