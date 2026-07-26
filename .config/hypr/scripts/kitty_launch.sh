#!/bin/bash
# Lanza kitty con un tamaño de fuente distinto según el monitor enfocado

LAPTOP_MONITOR="eDP-1"
EXTERNAL_MONITOR="HDMI-A-1"

LAPTOP_FONT_SIZE=13
EXTERNAL_FONT_SIZE=10.5

focused_monitor=$(hyprctl monitors -j | jq -r '.[] | select(.focused==true) | .name')

if [ "$focused_monitor" = "$EXTERNAL_MONITOR" ]; then
    # Solo en el monitor externo forzamos un tamaño distinto
    kitty -o font_size="$EXTERNAL_FONT_SIZE" &
else
    # En el resto de monitores, usa el font_size normal de kitty.conf (sin override)
    kitty &
fi