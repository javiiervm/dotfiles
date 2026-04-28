#!/bin/bash

THEMES_DIR="$HOME/.config/waybar/themes"
THEME_NAME="$1"
SELECTED_DIR="$THEMES_DIR/$THEME_NAME"

if [ ! -d "$SELECTED_DIR" ]; then
    echo "Error: El tema '$THEME_NAME' no existe."
    exit 1
fi

# 1. Crear enlaces simbólicos para la estructura (config y style)
ln -sf "$SELECTED_DIR/config.jsonc" "$HOME/.config/waybar/config"
ln -sf "$SELECTED_DIR/style.css" "$HOME/.config/waybar/style.css"

# 2. Buscar y aplicar el fondo de pantalla
WALLPAPER=$(find "$SELECTED_DIR" -maxdepth 1 -type f -name "wall.*" | head -n 1)

if [ -n "$WALLPAPER" ]; then
    # Asegurar que awww-daemon está corriendo
    if ! pgrep -x "awww-daemon" > /dev/null; then
        awww-daemon &
        sleep 0.5
    fi

    # Cambiar el fondo con awww
    awww img "$WALLPAPER" \
        --transition-type wipe \
        --transition-angle 30 \
        --transition-step 90 \
        --transition-fps 120 \
        --transition-duration 2

    # --- GENERAR COLORES DINÁMICOS ANTES DE LANZAR WAYBAR ---
    wal -i "$WALLPAPER" -n -q

    # Sincronización con Hyprlock
    mkdir -p "$HOME/.cache/hyprlock"
    rm -f "$HOME/.cache/hyprlock/current_wallpaper.png"
    cp "$WALLPAPER" "$HOME/.cache/hyprlock/current_wallpaper.png"
fi

# 3. Reiniciar Waybar y servicios AHORA que los colores ya están generados
bash "$HOME/.config/waybar/scripts/launch.sh"
