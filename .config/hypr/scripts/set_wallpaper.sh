#!/usr/bin/env bash

WALLPAPER="$1"

[ -f "$WALLPAPER" ] || {
    echo "Wallpaper not found: $WALLPAPER" >&2
    exit 1
}

LOG="/tmp/set_wallpaper.log"

{
    echo
    echo "=============================="
    echo "$(date)"
    echo "Wallpaper: $WALLPAPER"

    # Guardar wallpaper actual
    printf '%s\n' "$WALLPAPER" > /tmp/current_wallpaper

    # Cambiar visualmente el fondo
    awww img "$WALLPAPER" \
        --transition-type center \
        --transition-step 60 \
        --transition-fps 120 \
        --transition-duration 2

    echo "awww: $?"

    # Generar nueva paleta pywal
    wal -i "$WALLPAPER" -n -q

    echo "wal: $?"

    # Aplicar inmediatamente los nuevos colores a Hyprland
    "$HOME/.config/hypr/scripts/apply_wal_border.sh"

    echo "border script: $?"

    # Mostrar qué colores tiene realmente Hyprland después del cambio
    /usr/bin/hyprctl getoption general:col.active_border

    # Sincronizar Hyprlock
    mkdir -p "$HOME/.cache/hyprlock"
    cp "$WALLPAPER" "$HOME/.cache/hyprlock/current_wallpaper.png"

    # Ruta usada por Quickshell
    printf '%s\n' "$WALLPAPER" > "$HOME/.cache/qs_wall_path"

    #notify-send \
    #    "Theme synced" \
    #    -i "$WALLPAPER"

} >> "$LOG" 2>&1