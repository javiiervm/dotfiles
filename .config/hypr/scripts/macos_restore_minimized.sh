#!/bin/bash
#
# Restaura una ventana previamente minimizada por macos_minimize.sh: emerge
# desde el centro inferior de la pantalla hasta su posición/tamaño original,
# en una sola animación (crece y se mueve a la vez).
#
# Uso: macos_restore_minimized.sh <address>   (con o sin prefijo 0x)
#
# Requiere `jq`.

STATE_DIR="$HOME/.local/state/hypr/minimized"

# ==========================================
# CONFIGURACIÓN (debe coincidir con macos_minimize.sh)
# ==========================================
MINI_W=8
MINI_H=8
RESTORE_TILED_DELAY=0.55   # cubrir la duración real de la animación antes de re-tilear
                            # (ver nota de timing en macos_minimize.sh)
# ==========================================

addr="$1"
[ -z "$addr" ] && exit 0
addr_clean="${addr#0x}"
STATE_FILE="$STATE_DIR/${addr_clean}.json"
[ -f "$STATE_FILE" ] || exit 0

state=$(cat "$STATE_FILE")
workspace=$(echo "$state" | jq -r '.workspace')
floating=$(echo "$state" | jq -r '.floating')
x=$(echo "$state" | jq -r '.x')
y=$(echo "$state" | jq -r '.y')
w=$(echo "$state" | jq -r '.w')
h=$(echo "$state" | jq -r '.h')

mon=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true)')
mon_x=$(echo "$mon" | jq -r '.x')
mon_y=$(echo "$mon" | jq -r '.y')
mon_w=$(echo "$mon" | jq -r '(.width / .scale) | floor')
mon_h=$(echo "$mon" | jq -r '(.height / .scale) | floor')
mini_x=$(( mon_x + mon_w/2 - MINI_W/2 ))
mini_y=$(( mon_y + mon_h - MINI_H ))

# Traerla de vuelta al workspace donde vivía
hyprctl dispatch movetoworkspacesilent "$workspace,address:0x$addr_clean"

# Colocarla instantáneamente en su posición "encogida" del dock (sin animar,
# para que la animación de salida empiece justo ahí, sin salto visual)
hyprctl --batch "dispatch resizewindowpixel exact $MINI_W $MINI_H,address:0x$addr_clean ; dispatch movewindowpixel exact $mini_x $mini_y,address:0x$addr_clean"

# Pequeña pausa para asegurar que el compositor registró la posición antes de animar
sleep 0.02

# --- Crecer y moverse a la vez, en una sola animación, hasta la geometría original ---
hyprctl --batch "dispatch resizewindowpixel exact $w $h,address:0x$addr_clean ; dispatch movewindowpixel exact $x $y,address:0x$addr_clean"

# Restaurar estado tiled si no era flotante originalmente
if [ "$floating" = "false" ]; then
    ( sleep "$RESTORE_TILED_DELAY"; hyprctl dispatch settiled "address:0x$addr_clean" ) &
fi

hyprctl dispatch focuswindow "address:0x$addr_clean"
hyprctl dispatch alterzorder "top,address:0x$addr_clean"

rm -f "$STATE_FILE"