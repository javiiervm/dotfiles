#!/usr/bin/env bash

MODE=$1
ARG2=$2
RECENTS_FILE="$HOME/.cache/qs_recents"
touch "$RECENTS_FILE"

# =================================================================
# MODO 0: APLICACIONES
# =================================================================
if [ "$MODE" = "--apps" ]; then
    > /tmp/qs_apps.txt
    
    # Inyectamos el botón de Wi-Fi nativo
    echo "Wi-Fi|Manage wireless networks|network-wireless|qs_wifi|cmd" >> /tmp/qs_apps.txt
    
    directories=("$HOME/.local/share/applications" "/usr/share/applications" "$HOME/.local/share/applications/rofi-commands")
    for dir in "${directories[@]}"; do
        [ ! -d "$dir" ] && continue
        find "$dir" -maxdepth 1 -name "*.desktop" 2>/dev/null | while read -r file; do
            name=$(grep -m1 "^Name=" "$file" | cut -d= -f2-)
            [ -z "$name" ] && continue
            nodisplay=$(grep -m1 "^NoDisplay=" "$file" | cut -d= -f2-)
            [ "$nodisplay" = "true" ] && continue
            
            comment=$(grep -m1 "^Comment=" "$file" | cut -d= -f2-)
            icon=$(grep -m1 "^Icon=" "$file" | cut -d= -f2-)
            exec=$(grep -m1 "^Exec=" "$file" | cut -d= -f2-)
            [ -z "$icon" ] && icon="application-x-executable"
            
            echo "$name|$comment|$icon|$exec|app" >> /tmp/qs_apps.txt
        done
    done

    (
        if [ -s "$RECENTS_FILE" ]; then
            tac "$RECENTS_FILE" | awk '!seen[$0]++' | head -n 10 | while read -r r_name; do 
                grep "^$r_name|" /tmp/qs_apps.txt | head -n 1
            done
        fi
        sort -f /tmp/qs_apps.txt
    ) | awk -F'|' '!seen[$1]++'

# =================================================================
# MODO 5: WI-FI
# =================================================================
elif [ "$MODE" = "--wifi" ]; then
    wifi_state=$(nmcli radio wifi)
    # Enviamos el estado primero
    echo "$wifi_state||||state"
    
    if [ "$wifi_state" = "enabled" ]; then
        known_ssids=$(nmcli -g NAME,TYPE connection | awk -F: '$2=="802-11-wireless" {print $1}')
        active_ssid=$(nmcli -t -f ACTIVE,SSID dev wifi | awk -F: '$1=="yes" {print $2}')
        
        nmcli -t -f SIGNAL,SSID,SECURITY,ACTIVE device wifi list | grep -v '^\s*$' | awk -F: -v ks="$known_ssids" -v act="$active_ssid" '!seen[$2]++ {
            if ($2 == "") next;
            icon = ($3 == "") ? "network-wireless" : "network-wireless-encrypted";
            sec = ($3 == "") ? "Open" : "Secured";
            
            if ($4 == "yes") {
                print $2"|Signal: "$1"% ("sec")|"icon"|qs_keep:nmcli connection up id \""$2"\"|wifi_current"
            } else if (index(ks, $2) > 0) {
                print $2"|Signal: "$1"% ("sec")|"icon"|qs_keep:nmcli connection up id \""$2"\"|wifi_saved"
            } else {
                if ($3 == "") print $2"|Signal: "$1"% ("sec")|"icon"|qs_keep:nmcli device wifi connect \""$2"\"|wifi_new"
                else print $2"|Signal: "$1"% ("sec")|"icon"|qs_wifi_pass:"$2"|wifi_new"
            }
        }'
    fi
fi