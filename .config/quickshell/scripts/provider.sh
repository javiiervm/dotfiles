#!/bin/bash

MODE=$1

if [ "$MODE" = "--apps" ]; then
    # Inyectamos comandos virtuales para abrir los menús de red
    echo "Wi-Fi Settings|Manage wireless networks|network-wireless|qs_wifi|cmd"
    echo "Bluetooth Settings|Manage bluetooth devices|bluetooth|qs_bt|cmd"
    
    # Listado de aplicaciones (Lógica original restaurada)
    directories=("$HOME/.local/share/applications" "/usr/share/applications" "$HOME/.local/share/applications/rofi-commands")
    for dir in "${directories[@]}"; do
        [ ! -d "$dir" ] && continue
        find "$dir" -maxdepth 1 -name "*.desktop" 2>/dev/null | while read -r file; do
            name=$(grep -m1 "^Name=" "$file" | cut -d= -f2-)
            [ -z "$name" ] && continue
            
            # Filtro para ignorar apps ocultas
            nodisplay=$(grep -m1 "^NoDisplay=" "$file" | cut -d= -f2- | tr -d '\r')
            [ "$nodisplay" = "true" ] || [ "$nodisplay" = "True" ] && continue
            
            comment=$(grep -m1 "^Comment=" "$file" | cut -d= -f2- | tr -d '\r')
            icon=$(grep -m1 "^Icon=" "$file" | cut -d= -f2- | tr -d '\r')
            exec=$(grep -m1 "^Exec=" "$file" | cut -d= -f2- | sed 's/ %[a-zA-Z]//g' | tr -d '\r')
            
            # Icono por defecto si no tiene
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

        # Si no hay un escaneo ya en curso, lanzamos uno breve para que
        # también aparezcan dispositivos nuevos (no solo los ya emparejados)
        if ! bluetoothctl show | grep -q "Discovering: yes"; then
            bluetoothctl --timeout 4 scan on >/dev/null 2>&1
        fi

        # Archivo temporal para recolectar resultados sin lag
        > /tmp/qs_bt_out.txt

        # IMPORTANTE: usamos process substitution (< <(...)) en vez de un pipe
        # ("comando | while ...") porque un pipe ejecuta el "while" en una
        # subshell aparte; los "&" lanzados ahí dentro no quedan registrados
        # en el shell principal, así que el "wait" de más abajo no esperaba
        # realmente a que terminasen y el archivo se leía siempre vacío.
        while read -r line; do
            mac=$(echo "$line" | cut -d ' ' -f 2)
            name=$(echo "$line" | cut -d ' ' -f 3-)

            # Subshell paralela (&) para preguntar a todos simultáneamente sin congelar la interfaz
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
fi