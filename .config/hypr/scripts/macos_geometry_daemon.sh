#!/bin/bash
#
# Daemon auxiliar del modo macOS (100% Event-Driven / Sin Polling)

STATE_FILE="/tmp/hypr_macos_mode"
GEOMETRY_FILE="$HOME/.local/state/hypr/macos_window_geometry.json"

mkdir -p "$(dirname "$GEOMETRY_FILE")"
[ -f "$GEOMETRY_FILE" ] || echo '{}' > "$GEOMETRY_FILE"

save_geometry() {
    hyprctl clients -j 2>/dev/null | jq -c '
        [ .[] | select(.floating == true and .class != "") |
          { class: .class, x: .at[0], y: .at[1], w: .size[0], h: .size[1] } ]
    ' 2>/dev/null | jq -s --slurpfile old "$GEOMETRY_FILE" '
        (.[0] // []) as $current
        | reduce $current[] as $w ($old[0];
            .[$w.class] = {x: $w.x, y: $w.y, w: $w.w, h: $w.h}
          )
    ' > "$GEOMETRY_FILE.tmp" 2>/dev/null && mv "$GEOMETRY_FILE.tmp" "$GEOMETRY_FILE"
}

apply_geometry() {
    local addr="$1"
    local class
    class=$(hyprctl clients -j | jq -r --arg a "0x$addr" '.[] | select(.address == $a) | .class')
    [ -z "$class" ] || [ "$class" = "null" ] && return

    local geo
    geo=$(jq -c --arg c "$class" '.[$c] // empty' "$GEOMETRY_FILE")
    [ -z "$geo" ] && return

    local x y w h
    x=$(echo "$geo" | jq -r '.x')
    y=$(echo "$geo" | jq -r '.y')
    w=$(echo "$geo" | jq -r '.w')
    h=$(echo "$geo" | jq -r '.h')

    hyprctl dispatch resizewindowpixel "exact $w $h,address:0x$addr" >/dev/null
    hyprctl dispatch movewindowpixel "exact $x $y,address:0x$addr" >/dev/null
}

# --- Escuchador de eventos del Socket de Hyprland ---
socat -U - UNIX-CONNECT:"$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" 2>/dev/null |
while read -r line; do
    [ -f "$STATE_FILE" ] || continue
    case "$line" in
        openwindow\>*)
            addr=$(echo "${line#openwindow>>}" | cut -d',' -f1)
            sleep 0.05
            apply_geometry "$addr"
            ;;
        changefloatingmode\>*|movewindow\>*|resizewindow\>*)
            # Solo guarda cuando realmente mueves o cambias dimensiones
            save_geometry
            ;;
    esac
done