#!/bin/bash

# Función para la pestaña de Performance
get_performance() {
    cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
    # Aprovechando tu RTX 5070
    gpu=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits)
    ram=$(free -m | awk '/Mem:/ { printf("%3.1f%%", $3/$2*100) }')
    
    echo -e "  CPU: $cpu%\n󰢮  GPU: $gpu%\n  RAM: $ram"
}

# Función para Media (MPRIS)
get_media() {
    title=$(playerctl metadata title)
    artist=$(playerctl metadata artist)
    echo -e "󰎆  $title\n󰠃  $artist"
}

# Ejecución de Rofi con un tema personalizado
# El tema debe estar configurado para aparecer en el centro
MENU=$(echo -e "1. Dashboard\n2. Media\n3. Performance" | rofi -dmenu -p "Caelestia Rofi" -theme dashboard.rasi)

case "$MENU" in
    *Dashboard) # Aquí irían tus Quick Toggles actuales
        ;;
    *Media)
        get_media | rofi -dmenu -theme media_tab.rasi
        ;;
    *Performance)
        get_performance | rofi -dmenu -theme perf_tab.rasi
        ;;
esac
