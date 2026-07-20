#!/bin/bash

MODE=$1

if [ "$MODE" = "--apps" ]; then
    # Inyectamos comandos virtuales para abrir los submenús
    echo "Wi-Fi Settings|Manage wireless networks|network-wireless|qs_wifi|cmd"
    echo "Bluetooth Settings|Manage bluetooth devices|preferences-system-bluetooth|qs_bt|cmd"
    echo "System Options|Power off, reboot, suspend...|preferences-system-power|qs_sys|cmd"
    
    # Listado de aplicaciones (Lógica original restaurada)
    directories=("$HOME/.local/share/applications" "/usr/share/applications" "$HOME/.local/share/applications/rofi-commands")
    for dir in "${directories[@]}"; do
        [ ! -d "$dir" ] && continue
        find "$dir" -maxdepth 1 -name "*.desktop" 2>/dev/null | while read -r file; do
            # Extracción más limpia, ignorando mayúsculas/minúsculas en los booleanos
            nodisplay=$(grep -m1 -i "^NoDisplay=" "$file" | cut -d= -f2- | tr -d '\r' | tr -d ' ')
            [ "$nodisplay" = "true" ] && continue
            
            # Filtrar aplicaciones que explícitamente no quieren mostrarse en Hyprland/wlroots
            notshowin=$(grep -m1 "^NotShowIn=" "$file" | cut -d= -f2- | tr -d '\r')
            if [[ "$notshowin" == *"Hyprland"* || "$notshowin" == *"wlroots"* ]]; then continue; fi

            # Filtrar aplicaciones exclusivas de otros entornos (GNOME, KDE, etc.)
            onlyshowin=$(grep -m1 "^OnlyShowIn=" "$file" | cut -d= -f2- | tr -d '\r')
            if [ -n "$onlyshowin" ] && [[ "$onlyshowin" != *"Hyprland"* && "$onlyshowin" != *"wlroots"* ]]; then continue; fi
            
            # Lista negra manual: Bloquea ejecutables o utilidades de sistema que estorban
            filename=$(basename "$file")
            case "$filename" in
                *avahi*|*lstopo*|*btrfs-assistant*|*kvantum*|*gtk3-widget-factory*|*micro.desktop*)
                    continue ;;
            esac

            name=$(grep -m1 "^Name=" "$file" | cut -d= -f2-)
            [ -z "$name" ] && continue
            
            comment=$(grep -m1 "^Comment=" "$file" | cut -d= -f2- | tr -d '\r')
            icon=$(grep -m1 "^Icon=" "$file" | cut -d= -f2- | tr -d '\r')
            exec=$(grep -m1 "^Exec=" "$file" | cut -d= -f2- | sed 's/ %[a-zA-Z]//g' | tr -d '\r')
            
            # Fallback a nivel de backend
            [ -z "$icon" ] && icon="application-x-executable"
            
            if [ -n "$name" ] && [ -n "$exec" ]; then
                echo "$name|$comment|$icon|$exec|app"
            fi
        done
    done | awk -F'|' '!seen[$1]++'

elif [ "$MODE" = "--wifi" ]; then
    if nmcli radio wifi | grep -q "enabled"; then
        echo "enabled||||state"
        
        nmcli -t -f active,ssid,signal,security dev wifi | grep "^yes" | while IFS=: read -r active ssid signal sec; do
            [ -z "$ssid" ] && continue
            echo "$ssid|Signal: $signal% ($sec)|network-wireless-encrypted||wifi_current"
        done
        
        nmcli -t -f name,type con show | grep "802-11-wireless" | cut -d: -f1 | while read -r ssid; do
            if ! nmcli -t -f active,ssid dev wifi | grep "^yes:$ssid" > /dev/null; then
                echo "$ssid|Saved Network|network-wireless|qs_keep:nmcli connection up \"$ssid\"|wifi_saved"
            fi
        done
        
        nmcli -t -f active,ssid,signal,security dev wifi | grep "^no" | while IFS=: read -r active ssid signal sec; do
            [ -z "$ssid" ] && continue
            if ! nmcli -t -f name con show | grep -q "^$ssid$"; then
                if [ -z "$sec" ]; then
                    echo "$ssid|Signal: $signal% (Open)|network-wireless|qs_keep:nmcli device wifi connect \"$ssid\"|wifi_new"
                else
                    echo "$ssid|Signal: $signal% (Secured)|network-wireless-encrypted|qs_wifi_pass:$ssid|wifi_new"
                fi
            fi
        done | sort -u -t'|' -k1,1
    else
        echo "disabled||||state"
    fi

elif [ "$MODE" = "--bt" ]; then
    if bluetoothctl show | grep -q "Powered: yes"; then
        echo "enabled||||state"

        if ! bluetoothctl show | grep -q "Discovering: yes"; then
            bluetoothctl --timeout 4 scan on >/dev/null 2>&1
        fi

        > /tmp/qs_bt_out.txt

        while read -r line; do
            mac=$(echo "$line" | cut -d ' ' -f 2)
            name=$(echo "$line" | cut -d ' ' -f 3-)

            (
                if bluetoothctl info "$mac" | grep -q "Connected: yes"; then
                    echo "$name|$mac|bluetooth-active|qs_keep:bluetoothctl disconnect $mac|bt_current" >> /tmp/qs_bt_out.txt
                else
                    echo "$name|$mac|bluetooth|qs_keep:bluetoothctl connect $mac|bt_saved" >> /tmp/qs_bt_out.txt
                fi
            ) &
        done < <(bluetoothctl devices)

        wait

        [ -s /tmp/qs_bt_out.txt ] && cat /tmp/qs_bt_out.txt
    else
        echo "disabled||||state"
    fi

elif [ "$MODE" = "--wallpaper" ]; then
    WALL_DIR="$2"
    [ ! -d "$WALL_DIR" ] && exit 1
    ls -1 "$WALL_DIR" | while read -r wall; do
        echo "${wall%.}|Apply wallpaper|$WALL_DIR/$wall|echo '$WALL_DIR/$wall' > /tmp/current_wallpaper; awww img \"$WALL_DIR/$wall\" --transition-type center --transition-step 60 --transition-fps 120 --transition-duration 2 && wal -i \"$WALL_DIR/$wall\" -n -q && cp \"$WALL_DIR/$wall\" ~/.cache/hyprlock/current_wallpaper.png && notify-send 'Theme synced' -i \"$WALL_DIR/$wall\"|cmd"
    done

# =================================================================
# NUEVO: MENÚ DE SISTEMA
# =================================================================
elif [ "$MODE" = "--system" ]; then
    echo "Lock|Lock the current session|system-lock-screen|hyprlock|sys"
    echo "Suspend|Suspend the system|system-suspend|systemctl suspend|sys"
    echo "Logout|Exit current session|system-log-out|hyprctl dispatch exit|sys"
    echo "Reboot|Restart the system|system-reboot|systemctl reboot|sys"
    echo "Shutdown|Power off the system|system-shutdown|systemctl poweroff|sys"

# =================================================================
# NUEVO: BÚSQUEDA DE ARCHIVOS (Profundidad controlada para 0 lag)
# =================================================================
elif [ "$MODE" = "--search-files" ]; then
    QUERY="$2"
    # Busca en tu $HOME, baja máximo 4 carpetas de profundidad para no congelarse
    # y devuelve los primeros 15 resultados
    find "$HOME" -maxdepth 4 -type f -iname "*$QUERY*" 2>/dev/null | head -n 15 | while read -r path; do
        name=$(basename "$path")
        # Cambiamos /home/javier por ~ para que quede más estético en la UI
        clean_path="${path/#$HOME/\~}"
        echo "$name|$clean_path|text-x-generic|xdg-open '$path'|file"
    done
    
    # Si no encuentra nada, envía un dummy para avisar al usuario
    if [ $(find "$HOME" -maxdepth 4 -type f -iname "*$QUERY*" 2>/dev/null | head -n 1 | wc -l) -eq 0 ]; then
         echo "No files found matching '$QUERY'||||empty"
    fi
fi