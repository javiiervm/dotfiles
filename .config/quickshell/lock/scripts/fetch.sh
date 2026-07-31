#!/usr/bin/env bash
# fetch.sh — imprime datos del sistema en JSON de una línea para que
# Quickshell los consuma con Process + JSON.parse().
#
# Salida esperada:
# {"wm":"Hyprland","user":"sahil","uptime":"11 minutes","battery":45,"charging":false}

wm="Hyprland"
user="$USER"

# Uptime legible (usa `uptime -p` si existe, si no fallback simple)
if command -v uptime >/dev/null 2>&1; then
    up=$(uptime -p 2>/dev/null | sed 's/^up //')
else
    up="unknown"
fi

# Batería: busca la primera BAT* disponible
batt=0
charging=false
bat_path=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -n1)
if [ -n "$bat_path" ]; then
    batt=$(cat "$bat_path/capacity" 2>/dev/null || echo 0)
    status=$(cat "$bat_path/status" 2>/dev/null || echo "Unknown")
    if [ "$status" = "Charging" ]; then
        charging=true
    fi
fi

printf '{"wm":"%s","user":"%s","uptime":"%s","battery":%s,"charging":%s}\n' \
    "$wm" "$user" "$up" "$batt" "$charging"
