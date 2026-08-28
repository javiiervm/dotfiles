#!/bin/bash
#
# Minimiza la ventana activa (o la que se pase como $1): se encoge y se
# desplaza SIMULTÁNEAMENTE hacia el centro inferior de la pantalla
# (una sola animación, sin fases intermedias), y se esconde en el
# workspace especial "minimized".
#
# Para restaurarla: seleccionarla con Alt+Tab (ver macos_restore_minimized.sh)
#
# Uso: macos_minimize.sh [address]
#
# Requiere `jq`.

STATE_DIR="$HOME/.local/state/hypr/minimized"
mkdir -p "$STATE_DIR"

# ==========================================
# CONFIGURACIÓN (debe coincidir con macos_restore_minimized.sh)
# ==========================================
MINI_W=8            # Ancho final: casi un punto, para que "desaparezca" de
MINI_H=8            # verdad en vez de quedarse como una ventanita visible
ANIM_DELAY=0.55     # Debe cubrir la duración real de tu curva `animation = windows`.
                     # OJO: el SPEED de Hyprland son décimas de segundo, así que
                     # `animation = windows, 1, 4.79, easeOutQuint` dura ~0.48s,
                     # no menos. Se deja un pequeño margen extra (0.55s).
# ==========================================

addr="$1"
if [ -z "$addr" ]; then
    addr=$(hyprctl activewindow -j | jq -r '.address')
fi
[ -z "$addr" ] || [ "$addr" = "null" ] && exit 0

addr_clean="${addr#0x}"
STATE_FILE="$STATE_DIR/${addr_clean}.json"

# Si ya está minimizada, no hacer nada (evita relanzar el efecto dos veces)
[ -f "$STATE_FILE" ] && exit 0

win=$(hyprctl clients -j | jq -r --arg a "0x$addr_clean" '.[] | select(.address == $a)')
[ -z "$win" ] && exit 0

# Monitor donde vive la ventana (usamos el enfocado, que normalmente coincide)
mon=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true)')
mon_x=$(echo "$mon" | jq -r '.x')
mon_y=$(echo "$mon" | jq -r '.y')
mon_w=$(echo "$mon" | jq -r '(.width / .scale) | floor')
mon_h=$(echo "$mon" | jq -r '(.height / .scale) | floor')

target_x=$(( mon_x + mon_w/2 - MINI_W/2 ))
target_y=$(( mon_y + mon_h - MINI_H ))

# --- Guardar geometría/estado original para poder restaurarla luego ---
was_floating=$(echo "$win" | jq -r '.floating')
workspace=$(echo "$win" | jq -r '.workspace.name')
x=$(echo "$win" | jq -r '.at[0]')
y=$(echo "$win" | jq -r '.at[1]')
w=$(echo "$win" | jq -r '.size[0]')
h=$(echo "$win" | jq -r '.size[1]')
title=$(echo "$win" | jq -r '.title')
class=$(echo "$win" | jq -r '.class')

jq -n \
    --arg ws "$workspace" --argjson floating "$was_floating" \
    --argjson x "$x" --argjson y "$y" --argjson w "$w" --argjson h "$h" \
    --arg title "$title" --arg class "$class" \
    '{workspace:$ws, floating:$floating, x:$x, y:$y, w:$w, h:$h, title:$title, class:$class}' \
    > "$STATE_FILE"

# Si no estaba flotante, la hacemos flotante temporalmente para poder
# animarla libremente (igual que hace toggle_macos.sh al activar el modo macOS)
[ "$was_floating" = "false" ] && hyprctl dispatch setfloating "address:0x$addr_clean"

# --- Encoger y mover a la vez, en una sola animación ---
hyprctl --batch "dispatch resizewindowpixel exact $MINI_W $MINI_H,address:0x$addr_clean ; dispatch movewindowpixel exact $target_x $target_y,address:0x$addr_clean"

# Esperar a que termine la animación antes de esconderla, si no se
# "teletransporta" antes de verse encogida del todo
sleep "$ANIM_DELAY"

# Esconder en un workspace especial. Sigue "mapped" para hyprctl clients -j,
# por eso alttab_fetch.sh la puede seguir listando.
hyprctl dispatch movetoworkspacesilent special:minimized,address:0x$addr_clean

#notify-send "Hyprland" "Ventana minimizada"