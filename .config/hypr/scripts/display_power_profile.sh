#!/usr/bin/env bash

# ============================================================
# Internal display refresh rate controller
#
# Allows two modes:
#
# 1. Dynamic:
#      balanced / performance -> 240 Hz
#      power-saver            -> 60 Hz
#
# 2. Fixed:
#      Always use FIXED_RATE regardless of power profile.
#
# Hyprland 0.55+ Lua configuration.
# ============================================================

set -u


# ============================================================
# USER CONFIGURATION
# ============================================================

# true:
#   Refresh rate changes automatically according to power profile.
#
# false:
#   Power profile is ignored and FIXED_RATE is always used.
CHANGE_RATE_BY_PROFILE=false

# Refresh rate used when CHANGE_RATE_BY_PROFILE=false.
FIXED_RATE=60

# Refresh rates used when CHANGE_RATE_BY_PROFILE=true.
POWER_SAVER_RATE=60
BALANCED_RATE=240


# ============================================================
# MONITOR CONFIGURATION
# ============================================================

INTERNAL="eDP-1"
RESOLUTION="2560x1600"
SCALE="1.33"


# ============================================================
# CURRENT POWER PROFILE
# ============================================================

PROFILE="${1:-}"

if [ -z "$PROFILE" ]; then
    PROFILE="$(powerprofilesctl get 2>/dev/null || echo balanced)"
fi


# ============================================================
# TARGET REFRESH RATE
# ============================================================

if [ "$CHANGE_RATE_BY_PROFILE" = true ]; then

    case "$PROFILE" in
        power-saver)
            TARGET_RATE="$POWER_SAVER_RATE"
            ;;
        *)
            TARGET_RATE="$BALANCED_RATE"
            ;;
    esac

else

    TARGET_RATE="$FIXED_RATE"

fi


# ============================================================
# CHECK ACTIVE MONITOR
# ============================================================

CURRENT_RATE="$(
    hyprctl -j monitors 2>/dev/null |
        jq -r --arg monitor "$INTERNAL" \
            '.[] | select(.name == $monitor) | .refreshRate' |
        head -n 1
)"

# eDP-1 is disabled, for example in clamshell mode.
[ -n "$CURRENT_RATE" ] || exit 0


# ============================================================
# AVOID UNNECESSARY RECONFIGURATION
# ============================================================

CURRENT_RATE_ROUNDED="$(
    awk -v rate="$CURRENT_RATE" \
        'BEGIN { printf "%.0f", rate }'
)"

if [ "$CURRENT_RATE_ROUNDED" = "$TARGET_RATE" ]; then
    exit 0
fi


# ============================================================
# APPLY USING HYPRLAND LUA API
# ============================================================

hyprctl eval "
hl.monitor({
    output = \"$INTERNAL\",
    mode = \"${RESOLUTION}@${TARGET_RATE}\",
    position = \"0x0\",
    scale = $SCALE
})
"