#!/bin/bash
# Obtiene el listado de ventanas activas ordenado por último foco en JSON instantáneo.
# El icono se resuelve buscando el .desktop real de cada app (igual que provider.sh),
# en vez de adivinar el nombre del icono a partir del "class" de la ventana.

DIRS=(
    "$HOME/.local/share/applications"
    "/usr/share/applications"
    "$HOME/.local/share/applications/rofi-commands"
    "/var/lib/flatpak/exports/share/applications"
    "$HOME/.local/share/flatpak/exports/share/applications"
)

# Cache simple para no repetir la búsqueda si hay varias ventanas de la misma app
declare -A ICON_CACHE

resolve_icon() {
    local class="$1"

    if [ -n "${ICON_CACHE[$class]}" ]; then
        echo "${ICON_CACHE[$class]}"
        return
    fi

    local class_lower
    class_lower=$(echo "$class" | tr '[:upper:]' '[:lower:]')
    local file=""

    # 1) Coincidencia por StartupWMClass (el método más fiable, mismo que usan
    #    los pagers/launchers para casar ventana <-> .desktop)
    file=$(grep -ril "^StartupWMClass=$class$" "${DIRS[@]}" 2>/dev/null | head -n1)

    # 2) Coincidencia exacta por nombre de archivo (Class.desktop / class.desktop)
    if [ -z "$file" ]; then
        for d in "${DIRS[@]}"; do
            [ -f "$d/$class.desktop" ] && file="$d/$class.desktop" && break
            [ -f "$d/$class_lower.desktop" ] && file="$d/$class_lower.desktop" && break
        done
    fi

    # 3) Coincidencia parcial: algún .desktop cuyo nombre de archivo contenga la clase
    if [ -z "$file" ]; then
        file=$(find "${DIRS[@]}" -maxdepth 1 -iname "*${class_lower}*.desktop" 2>/dev/null | head -n1)
    fi

    local icon=""
    if [ -n "$file" ]; then
        icon=$(grep -m1 "^Icon=" "$file" | cut -d= -f2- | tr -d '\r')
    fi

    # Fallback: el comportamiento anterior (class en minúsculas), por si no
    # encontramos ningún .desktop que case con esta ventana
    [ -z "$icon" ] && icon="$class_lower"

    ICON_CACHE[$class]="$icon"
    echo "$icon"
}

hyprctl clients -j | jq -c '
    [ .[] | select(.mapped == true and .hidden == false and .class != "") ]
    | sort_by(.focusHistoryID)
    | [ .[] | { address: .address, class: .class, title: .title } ]
' | jq -c '.[]' | while read -r win; do
    class=$(echo "$win" | jq -r '.class')
    icon=$(resolve_icon "$class")
    echo "$win" | jq -c --arg icon "$icon" '. + {icon: $icon}'
done | jq -s -c '.'