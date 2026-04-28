#!/usr/bin/env bash

# Ruta a tu tema
theme="$HOME/.config/rofi/launchers/type-2/style-2.rasi"

# Elementos del menú
# Aquí quitamos el "$(hostname)" y ponemos directamente el icono
prompt="⏻"
mesg="Uptime : $(uptime -p | sed -e 's/up //g')"
list_col='1'
list_row='6'

# Opciones con los iconos Unicode que estás usando
option_1=" Lock"
option_2="󰍃 Logout"
option_3="󰤄 Suspend"
option_4="󰒲 Hibernate"
option_5="󰜉 Reboot"
option_6=" Shutdown"

# Comando Rofi
rofi_cmd() {
    # Hemos añadido 'scrollbar: false;' a la vista de lista
    # y '{str: "";}' al textbox-prompt para eliminar el icono roto
	rofi -theme-str "listview {columns: $list_col; lines: $list_row; scrollbar: false;}" \
		-theme-str 'textbox-prompt-colon {str: "";}' \
		-dmenu \
		-i \
		-p "$prompt" \
		-mesg "$mesg" \
		-markup-rows \
		-theme "$theme"
}

# Desplegar menú
chosen="$(echo -e "$option_1\n$option_2\n$option_3\n$option_4\n$option_5\n$option_6" | rofi_cmd)"

# Acciones
case ${chosen} in
    "$option_1")
        hyprlock
        ;;
    "$option_2")
        hyprctl dispatch exit
        ;;
    "$option_3")
        hyprlock & sleep 1 && systemctl suspend
        ;;
    "$option_4")
        hyprlock & sleep 1 && systemctl hibernate
        ;;
    "$option_5")
        systemctl reboot
        ;;
    "$option_6")
        systemctl poweroff
        ;;
esac
