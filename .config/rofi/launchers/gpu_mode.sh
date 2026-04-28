#!/bin/bash

# Define options with NerdFont icons
INTEGRATED="󰈐 Integrated Mode (Power Save)"
HYBRID="󰢮 Hybrid Mode (Enable HDMI/dGPU)"

# Theme path (Cambia 'style-1.rasi' por el número de estilo que prefieras o que ya uses)
THEME="$HOME/.config/rofi/launchers/type-2/style-1.rasi"

# Show menu using Rofi with the loaded theme
choice=$(echo -e "$INTEGRATED\n$HYBRID" | rofi -dmenu -i -p "GPU:" -theme "$THEME")

case "$choice" in
    "$INTEGRATED")
        pkexec envycontrol -s integrated
        notify-send "GPU Profile Changed" "Switched to Integrated. Please reboot or relog." --icon=power-profile-daemon
        ;;
    "$HYBRID")
        pkexec envycontrol -s hybrid
        notify-send "GPU Profile Changed" "Switched to Hybrid. HDMI is now available. Please reboot or relog." --icon=power-profile-daemon
        ;;
esac
