#!/bin/bash
#
# Requiere `jq` para parsear la salida de hyprctl (sudo pacman -S jq si no lo tienes)

STATE_FILE="/tmp/hypr_macos_mode"
BACKUP_FILE="/tmp/hypr_macos_backup.json"
RULES_FILE="$HOME/.config/hypr/macos_rules.conf"
DAEMON_SCRIPT="$HOME/.config/hypr/scripts/macos_geometry_daemon.sh"
DAEMON_PID_FILE="/tmp/hypr_macos_geometry_daemon.pid"

if [ -f "$STATE_FILE" ]; then
    # --- DESACTIVAR MODO MACOS ---
    rm "$STATE_FILE"

    # Parar el daemon que recuerda tamaños de ventana
    if [ -f "$DAEMON_PID_FILE" ]; then
        kill "$(cat "$DAEMON_PID_FILE")" 2>/dev/null
        rm -f "$DAEMON_PID_FILE"
    fi

    # Vaciar las reglas para que no se apliquen a ventanas nuevas
    echo "" > "$RULES_FILE"

    # Restaurar gaps por defecto (dentro del archivo, no solo en runtime,
    # para que sobreviva al siguiente "hyprctl reload")
    hyprctl keyword general:gaps_out "2, 12, 12, 12"

    hyprctl reload

    # Restaurar el estado (tiled/posición/tamaño) de las ventanas que
    # habíamos puesto en modo flotante
    if [ -f "$BACKUP_FILE" ]; then
        jq -c '.[]' "$BACKUP_FILE" | while read -r win; do
            addr=$(echo "$win" | jq -r '.address')
            was_floating=$(echo "$win" | jq -r '.floating')

            if [ "$was_floating" = "false" ]; then
                hyprctl dispatch settiled "address:$addr"
            fi
        done
        rm -f "$BACKUP_FILE"
    fi

    #notify-send "Hyprland" "Modo Tiling Restaurado"
else
    # --- ACTIVAR MODO MACOS ---
    touch "$STATE_FILE"

    # Guardar el estado actual de las ventanas abiertas para poder
    # restaurarlo al desactivar el modo
    hyprctl clients -j > "$BACKUP_FILE"

    # Arrancar el daemon que recuerda tamaños/posiciones por app
    nohup "$DAEMON_SCRIPT" >/tmp/hypr_macos_geometry_daemon.log 2>&1 &
    echo $! > "$DAEMON_PID_FILE"

    # Escribir la regla (para ventanas nuevas) y el gap del dock
    # EN EL MISMO ARCHIVO que se sourcea, así el gap sobrevive al reload
    cat <<EOF > "$RULES_FILE"
windowrule {
    name = macos-mode-global
    match:class = .*
    float = true
    center = true
    size = 1280 800
}

general {
    gaps_out = 2, 12, 80, 12
}
EOF

    hyprctl reload

    # Aplicar el modo flotante también a las ventanas YA ABIERTAS,
    # porque las windowrules solo afectan a ventanas nuevas
    hyprctl clients -j | jq -c '.[]' | while read -r win; do
        addr=$(echo "$win" | jq -r '.address')

        hyprctl dispatch setfloating "address:$addr"
        hyprctl dispatch resizewindowpixel "exact 1280 800,address:$addr"
        hyprctl dispatch centerwindow "address:$addr"
    done

    #notify-send "Hyprland" "Modo macOS Activado"
fi