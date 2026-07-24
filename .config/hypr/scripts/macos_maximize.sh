#!/bin/bash
#
# Maximiza / restaura la ventana activa.
# - Fuera del modo macOS: comportamiento nativo de Hyprland (fullscreen, 1).
# - En modo macOS: aplica los márgenes y dimensiones manuales configurados.
#
# Requiere `jq`.

# ==========================================
# CONFIGURACIÓN DE GEOMETRÍA MANUAL
# ==========================================
MARGIN_LEFT=14     # Coordenada X (Margen izquierdo)
MARGIN_TOP=48      # Coordenada Y (Margen superior)
WIDTH=1895         # Ancho total visual (en píxeles)
HEIGHT=1079        # Alto total visual (en píxeles)

# Ancho de borde en hyprland.conf (border_size = 2)
BORDER_SIZE=2
# ==========================================

STATE_FILE="/tmp/hypr_macos_mode"
MAX_STATE_DIR="/tmp/hypr_macos_maximize"

# Cálculo de las dimensiones internas excluyendo bordes
TARGET_X=$MARGIN_LEFT
TARGET_Y=$MARGIN_TOP
TARGET_W=$((WIDTH - BORDER_SIZE * 2))
TARGET_H=$((HEIGHT - BORDER_SIZE * 2))

if [ ! -f "$STATE_FILE" ]; then
    # --- Modo tiling normal: comportamiento nativo ---
    hyprctl dispatch fullscreen 1
    exit 0
fi

mkdir -p "$MAX_STATE_DIR"

addr=$(hyprctl activewindow -j | jq -r '.address')
if [ -z "$addr" ] || [ "$addr" = "null" ]; then
    exit 0
fi

STATE_KEY="$MAX_STATE_DIR/${addr#0x}.json"

if [ -f "$STATE_KEY" ]; then
    # --- RESTAURAR al tamaño/posición previos ---
    prev=$(cat "$STATE_KEY")
    x=$(echo "$prev" | jq -r '.x')
    y=$(echo "$prev" | jq -r '.y')
    w=$(echo "$prev" | jq -r '.w')
    h=$(echo "$prev" | jq -r '.h')

    hyprctl dispatch resizewindowpixel "exact $w $h,address:$addr"
    hyprctl dispatch movewindowpixel "exact $x $y,address:$addr"
    rm -f "$STATE_KEY"
else
    # --- MAXIMIZAR ---
    win=$(hyprctl activewindow -j)
    cur_x=$(echo "$win" | jq -r '.at[0]')
    cur_y=$(echo "$win" | jq -r '.at[1]')
    cur_w=$(echo "$win" | jq -r '.size[0]')
    cur_h=$(echo "$win" | jq -r '.size[1]')
    echo "{\"x\":$cur_x,\"y\":$cur_y,\"w\":$cur_w,\"h\":$cur_h}" > "$STATE_KEY"

    # Redimensionar y mover
    hyprctl dispatch resizewindowpixel "exact $TARGET_W $TARGET_H,address:$addr"
    hyprctl dispatch movewindowpixel "exact $TARGET_X $TARGET_Y,address:$addr"
fi