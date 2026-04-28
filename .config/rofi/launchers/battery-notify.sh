#!/usr/bin/env bash

# Configuración de niveles
LOW_LEVELS=(20 15 10)
HIGH_LEVELS=(85 90 95 100)

# Archivos temporales y variables de estado
LAST_NOTIF="/tmp/last_battery_notif"
LAST_STATUS_FILE="/tmp/last_battery_status"

# Inicializar el archivo de estado si no existe
[ ! -f "$LAST_STATUS_FILE" ] && cat /sys/class/power_supply/BAT0/status > "$LAST_STATUS_FILE"

check_battery() {
    capacity=$(cat /sys/class/power_supply/BAT0/capacity)
    status=$(cat /sys/class/power_supply/BAT0/status)
    prev_status=$(cat "$LAST_STATUS_FILE")

    # --- 1. DETECCIÓN DE ENCHUFE/DESENCHUFE ---
    if [[ "$status" != "$prev_status" ]]; then
        # Si pasamos de cualquier cosa a "Charging", es que hemos enchufado
        if [[ "$status" == "Charging" ]]; then
            notify-send -u low "Power Connected" "Your OMEN is now charging ($capacity%)" -i battery-charging-symbolic
        
        # Si pasamos de "Charging" o "Full" a "Discharging", es que hemos desenchufado
        elif [[ "$status" == "Discharging" ]]; then
            notify-send -u low "Power Disconnected" "Running on battery power ($capacity%)" -i battery-discharging-symbolic
        fi
        # Guardamos el nuevo estado para la siguiente comprobación
        echo "$status" > "$LAST_STATUS_FILE"
    fi

    # --- 2. LÓGICA DE NIVELES CRÍTICOS (Ya la tenías) ---
    if [[ "$status" == "Discharging" ]]; then
        for level in "${LOW_LEVELS[@]}"; do
            if [[ "$capacity" -le "$level" ]]; then
                if [[ ! -f "$LAST_NOTIF" ]] || [[ $(cat "$LAST_NOTIF") != "low_$level" ]]; then
                    notify-send -u critical "Battery Low" "Level: $capacity%. Please plug in." -i battery-caution
                    echo "low_$level" > "$LAST_NOTIF"
                fi
                return
            fi
        done
    fi

    if [[ "$status" == "Charging" ]]; then
        for level in "${HIGH_LEVELS[@]}"; do
            if [[ "$capacity" -ge "$level" ]]; then
                if [[ ! -f "$LAST_NOTIF" ]] || [[ $(cat "$LAST_NOTIF") != "high_$level" ]]; then
                    notify-send "Charge Limit Reached" "Level: $capacity%. Battery healthy." -i battery-good
                    echo "high_$level" > "$LAST_NOTIF"
                fi
                return
            fi
        done
    fi

    echo "idle" > "$LAST_NOTIF"
}

# Bucle de ejecución (lo bajamos a 5-10 segundos para que el aviso de enchufe sea instantáneo)
while true; do
    check_battery
    sleep 5
done
