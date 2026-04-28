#!/usr/bin/env bash

MODE=$1
ARG2=$2
RECENTS_FILE="$HOME/.cache/qs_recents"
touch "$RECENTS_FILE"

if [ "$MODE" = "--apps" ]; then
    > /tmp/qs_native.txt
    echo "Wallpaper|Change wallpaper and sync colors|preferences-desktop-wallpaper|qs_wall|cmd" >> /tmp/qs_native.txt
    echo "Calculator|Evaluate mathematical expressions|accessories-calculator|qs_calc|cmd" >> /tmp/qs_native.txt
    echo "System|Power off, reboot, suspend...|preferences-system-power|qs_sys|cmd" >> /tmp/qs_native.txt
    echo "Wi-Fi|Manage wireless networks|network-wireless|qs_wifi|cmd" >> /tmp/qs_native.txt
    echo "Bluetooth|Manage bluetooth devices|bluetooth|qs_bt|cmd" >> /tmp/qs_native.txt

    > /tmp/qs_apps.txt
    directories=("/usr/share/applications" "$HOME/.local/share/applications" "$HOME/.local/share/applications/rofi-commands")
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
        cat /tmp/qs_native.txt
        if [ -s "$RECENTS_FILE" ]; then
            tac "$RECENTS_FILE" | awk '!seen[$0]++' | head -n 10 | while read -r r_name; do grep "^$r_name|" /tmp/qs_apps.txt | head -n 1; done
        fi
        sort -f /tmp/qs_apps.txt
    ) | awk -F'|' '!seen[$1]++'

elif [ "$MODE" = "--files" ]; then
    TARGET_DIR="${ARG2:-$HOME}"
    [ ! -d "$TARGET_DIR" ] && TARGET_DIR="$HOME"
    if [ "$TARGET_DIR" != "$HOME" ] && [ "$TARGET_DIR" != "/" ]; then
        echo "󰁔 Go Back|Parent directory|go-up|qs_dir:$(dirname "$TARGET_DIR")|dir"
    fi
    ls -1p "$TARGET_DIR" | while read -r file; do
        clean="${file%/}"
        path="$TARGET_DIR/$clean"
        if [[ "$file" == */ ]]; then echo "$clean|Folder|system-file-manager|qs_dir:$path|dir"
        else echo "$clean|File|text-x-generic|xdg-open \"$path\"|file"; fi
    done

elif [ "$MODE" = "--run" ]; then
    ls -1 /usr/bin | head -n 400 | while read -r cmd; do echo "$cmd|Run command|utilities-terminal|$cmd|run"; done

elif [ "$MODE" = "--wallpaper" ]; then
    WALL_DIR="$HOME/.config/rofi/wallpapers"
    ls -1 "$WALL_DIR" | while read -r wall; do
        echo "${wall%.*}|Apply wallpaper|$WALL_DIR/$wall|awww img \"$WALL_DIR/$wall\" --transition-type center --transition-step 60 --transition-fps 120 --transition-duration 2 && wal -i \"$WALL_DIR/$wall\" -n -q && cp \"$WALL_DIR/$wall\" ~/.cache/hyprlock/current_wallpaper.png && notify-send 'Theme synced' -i \"$WALL_DIR/$wall\"|cmd"
    done

elif [ "$MODE" = "--system" ]; then
    echo "Lock|Lock the current session|system-lock-screen|hyprlock|cmd"
    echo "Suspend|Suspend the system|system-suspend|systemctl suspend|cmd"
    echo "Logout|Exit current session|system-log-out|hyprctl dispatch exit|cmd"
    echo "Reboot|Restart the system|system-reboot|systemctl reboot|cmd"
    echo "Shutdown|Power off the system|system-shutdown|systemctl poweroff|cmd"

# =================================================================
# NUEVOS SUBMENÚS AVANZADOS DE RED Y BLUETOOTH
# =================================================================
elif [ "$MODE" = "--wifi" ]; then
    wifi_state=$(nmcli radio wifi)
    if [ "$wifi_state" = "enabled" ]; then
        echo "󰖪  Disable Wi-Fi|Turn off Wi-Fi adapter|network-wireless-disconnected|qs_keep:nmcli radio wifi off|cmd"
        echo "󰑐  Scan Networks|Search for available Wi-Fi|view-refresh|qs_keep:nmcli device wifi rescan|cmd"
        echo "󰖩  Manual Connection|Connect to hidden network|network-wireless|qs_wifi_manual|cmd"
        
        known_ssids=$(nmcli -g NAME,TYPE connection | awk -F: '$2=="802-11-wireless" {print $1}')
        
        # Elemento Dummy (Separador)
        echo "--- Saved Networks ---||||dummy"
        nmcli -t -f SIGNAL,SSID,SECURITY device wifi list | grep -v '^\s*$' | awk -F: -v ks="$known_ssids" '!seen[$2]++ {
            if ($2 == "") next;
            icon = ($3 == "") ? "network-wireless" : "network-wireless-encrypted"; sec = ($3 == "") ? "Open" : "Secured";
            if (index(ks, $2) > 0) print $2"|Signal: "$1"% ("sec")|"icon"|qs_keep:nmcli connection up id \""$2"\"|cmd"
        }'
        
        echo "--- Other Networks ---||||dummy"
        nmcli -t -f SIGNAL,SSID,SECURITY device wifi list | grep -v '^\s*$' | awk -F: -v ks="$known_ssids" '!seen[$2]++ {
            if ($2 == "") next;
            icon = ($3 == "") ? "network-wireless" : "network-wireless-encrypted"; sec = ($3 == "") ? "Open" : "Secured";
            if (index(ks, $2) == 0) {
                if ($3 == "") print $2"|Signal: "$1"% ("sec")|"icon"|qs_keep:nmcli device wifi connect \""$2"\"|cmd"
                else print $2"|Signal: "$1"% ("sec")|"icon"|qs_wifi_pass:"$2"|cmd"
            }
        }'
    else
        echo "󰖩 Enable Wi-Fi|Turn on Wi-Fi adapter|network-wireless|qs_keep:nmcli radio wifi on|cmd"
    fi

elif [ "$MODE" = "--bt" ]; then
    if bluetoothctl show | grep -q "Powered: yes"; then
        echo "󰂲 Power: Off|Turn off Bluetooth|bluetooth-disabled|qs_keep:bluetoothctl power off|cmd"
        if bluetoothctl show | grep -q "Discovering: yes"; then
            echo "󰂰 Stop Scan|Stop searching for devices|media-playback-stop|qs_keep:bluetoothctl scan off|cmd"
        else
            echo "󰂰 Scan Devices|Search for Bluetooth devices|view-refresh|qs_keep:bluetoothctl --timeout 5 scan on|cmd"
        fi
        
        bluetoothctl show | grep -q "Pairable: yes" && p_cmd="off" p_icon="on" || p_cmd="on" p_icon="off"
        echo "󰂵 Pairable: $p_icon|Toggle pairable state|preferences-system-bluetooth|qs_keep:bluetoothctl pairable $p_cmd|cmd"
        
        bluetoothctl show | grep -q "Discoverable: yes" && d_cmd="off" d_icon="on" || d_cmd="on" d_icon="off"
        echo "󰂶 Discoverable: $d_icon|Toggle discoverable state|preferences-system-bluetooth|qs_keep:bluetoothctl discoverable $d_cmd|cmd"
        
        echo "--- Available Devices ---||||dummy"
        bluetoothctl devices | while read -r line; do
            mac=$(echo "$line" | cut -d ' ' -f 2)
            name=$(echo "$line" | cut -d ' ' -f 3-)
            echo "$name|Manage $mac|bluetooth|qs_bt_device:$mac|cmd"
        done
    else
        echo "󰂯 Power: On|Turn on Bluetooth|bluetooth-active|qs_keep:bluetoothctl power on|cmd"
    fi

elif [ "$MODE" = "--bt_device" ]; then
    MAC=$2
    info=$(bluetoothctl info "$MAC")
    [[ "$info" =~ "Connected: yes" ]] && c_cmd="disconnect" c_stat="yes" || c_cmd="connect" c_stat="no"
    echo "󱘖 Connected: $c_stat|Toggle connection|network-transmit-receive|qs_keep:bluetoothctl $c_cmd $MAC|cmd"
    
    [[ "$info" =~ "Paired: yes" ]] && p_cmd="remove" p_stat="yes" || p_cmd="pair" p_stat="no"
    echo "󰂵 Paired: $p_stat|Toggle pairing|emblem-shared|qs_keep:bluetoothctl $p_cmd $MAC|cmd"
    
    [[ "$info" =~ "Trusted: yes" ]] && t_cmd="untrust" t_stat="yes" || t_cmd="trust" t_stat="no"
    echo "󰒘 Trusted: $t_stat|Toggle trust|security-high|qs_keep:bluetoothctl $t_cmd $MAC|cmd"
fi