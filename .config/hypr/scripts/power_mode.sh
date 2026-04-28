#!/bin/bash

# Variable para recordar el estado
LAST_STATE=""

handle_power() {
    # 1. Comprueba el estado actual del hardware
    if grep -q 1 /sys/class/power_supply/AC*/online 2>/dev/null || grep -q 1 /sys/class/power_supply/ADP*/online 2>/dev/null; then
        CURRENT_STATE="plugged"
    else
        CURRENT_STATE="unplugged"
    fi

    # 2. Solo ejecuta las acciones SI EL ESTADO HA CAMBIADO
    if [ "$CURRENT_STATE" != "$LAST_STATE" ]; then
        if [ "$CURRENT_STATE" == "plugged" ]; then
            # 🔌 ENCHUFADO A LA CORRIENTE
            powerprofilesctl set balanced
            
            # Opcional: Subir hercios
            #hyprctl keyword monitor eDP-1,2560x1600@240,auto,1.33
        else
            # 🔋 USANDO BATERÍA
            powerprofilesctl set power-saver
            
            # Opcional: Bajar hercios
            #hyprctl keyword monitor eDP-1,2560x1600@60,auto,1.33
        fi
        
        # 3. Actualizar la memoria
        LAST_STATE="$CURRENT_STATE"
    fi
}

handle_power

udevadm monitor --subsystem-match=power_supply | while read -r line; do
    handle_power
done
