#!/bin/bash

# Dónde están guardados los temas
THEMES_DIR="$HOME/.config/waybar/themes"

# Dónde está el script que aplica el tema (¡esta es la conexión clave!)
APPLY_SCRIPT="$HOME/.config/waybar/scripts/apply_theme.sh"

# Listar los temas
THEMES=$(ls -1d "$THEMES_DIR"/*/ | xargs -n 1 basename)

# Lanzar Rofi
CHOSEN=$(echo "$THEMES" | rofi -dmenu -i -p "󰸉 Selecciona un Tema:" -lines 5)

# Aplicar el tema si se seleccionó uno
if [ -n "$CHOSEN" ]; then
    bash "$APPLY_SCRIPT" "$CHOSEN"
fi
