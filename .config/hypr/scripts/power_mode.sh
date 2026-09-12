#!/usr/bin/env bash

# ============================================================
# Automatic laptop power profile
#
# AC:
#   balanced
#   240 Hz
#
# Battery:
#   power-saver
#   60 Hz
#
# Manual changes made through Quickshell are respected while
# the power source remains unchanged.
#
# Fully event-driven:
#   - udev -> AC / battery changes
#   - D-Bus -> power profile changes
#   - no polling
# ============================================================

set -u

DISPLAY_SYNC="$HOME/.config/hypr/scripts/display_power_profile.sh"

LAST_STATE=""


# ============================================================
# HELPERS
# ============================================================

get_power_state() {
    for f in \
        /sys/class/power_supply/AC*/online \
        /sys/class/power_supply/ADP*/online
    do
        [ -r "$f" ] || continue

        read -r value < "$f"

        if [ "$value" = "1" ]; then
            echo "plugged"
            return
        fi
    done

    echo "unplugged"
}


sync_display() {
    local profile

    profile="$(powerprofilesctl get 2>/dev/null || echo balanced)"

    if [ -x "$DISPLAY_SYNC" ]; then
        "$DISPLAY_SYNC" "$profile"
    fi
}


handle_power() {
    local current_state
    local target_profile
    local current_profile

    current_state="$(get_power_state)"

    # The battery may emit many udev events while discharging.
    # Only change the automatic policy when AC state itself changes.
    if [ "$current_state" = "$LAST_STATE" ]; then
        return
    fi

    if [ "$current_state" = "plugged" ]; then
        target_profile="balanced"
    else
        target_profile="power-saver"
    fi

    current_profile="$(
        powerprofilesctl get 2>/dev/null ||
        echo balanced
    )"

    if [ "$current_profile" != "$target_profile" ]; then
        powerprofilesctl set "$target_profile"
    fi

    if [ -x "$DISPLAY_SYNC" ]; then
        "$DISPLAY_SYNC" "$target_profile"
    fi

    LAST_STATE="$current_state"
}


# ============================================================
# INITIAL STATE
# ============================================================

handle_power


# ============================================================
# EVENT CHANNEL
# ============================================================

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
FIFO="$RUNTIME_DIR/hypr_power_mode_fifo"

rm -f "$FIFO"
mkfifo "$FIFO"

exec 3<>"$FIFO"


# ============================================================
# POWER-SUPPLY EVENTS
# ============================================================

(
    udevadm monitor \
        --subsystem-match=power_supply \
        2>/dev/null |
        grep --line-buffered "change" |
        while read -r _; do
            echo "POWER" >&3
        done
) &


# ============================================================
# POWER-PROFILE EVENTS
#
# This also catches the manual Power Saver toggle from
# Quickshell, because that button changes powerprofilesctl.
# ============================================================

(
    dbus-monitor \
        --system \
        "type='signal',interface='org.freedesktop.DBus.Properties',path='/net/hadess/PowerProfiles'" \
        2>/dev/null |
        grep --line-buffered "PropertiesChanged" |
        while read -r _; do
            echo "PROFILE" >&3
        done
) &


# ============================================================
# CLEANUP
# ============================================================

cleanup() {
    kill $(jobs -p) 2>/dev/null || true
    exec 3>&-
    rm -f "$FIFO"
}

trap cleanup EXIT INT TERM


# ============================================================
# EVENT LOOP
# ============================================================

while read -r event <&3; do
    case "$event" in

        POWER)
            handle_power
            ;;

        PROFILE)
            sync_display
            ;;

    esac
done
