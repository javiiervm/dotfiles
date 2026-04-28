#!/usr/bin/env bash
# ==============================================================================
# Caelestia Menu: Seamless Transition & Invisible Triggers
# ==============================================================================

# --- Paths and Configuration ---
CMD_DIR="$HOME/.local/share/applications/rofi-commands"
WALL_DIR="$HOME/.config/rofi/wallpapers"
BASE_THEME="$HOME/.config/rofi/launchers/type-2/style-2.rasi"
SCRIPT_PATH="$(realpath "$0")"

# Create command directory if it doesn't exist
mkdir -p "$CMD_DIR"

# --- 1. Wallpaper Logic (Caelestia Style) ---
launch_wallpaper_picker() {
    # Ensure the wallpaper daemon is running
    pgrep -x "awww-daemon" > /dev/null || (awww-daemon & sleep 0.5)

    list_walls() {
        cd "$WALL_DIR" || exit
        for wall in *; do
            if [[ -f "$wall" ]]; then
                name="${wall%.*}"
                echo -en "$name\0icon\x1f$WALL_DIR/$wall\n"
            fi
        done
    }

    selected_clean=$(list_walls | rofi -dmenu -i \
        -theme "$BASE_THEME" \
        -p "> wallpaper" \
        -theme-str '
            window { width: 1000px; location: south; anchor: south; y-offset: -20px; border-radius: 20px; }
            mainbox { children: [ "listview", "inputbar" ]; spacing: 20px; padding: 20px; background-color: transparent; }
            listview { columns: 5; lines: 1; spacing: 15px; fixed-height: false; dynamic: true; scrollbar: false; layout: vertical; }
            element { orientation: vertical; padding: 10px; border-radius: 15px; background-color: transparent; }
            element selected { background-color: #ffffff20; }
            element-icon { size: 160px; horizontal-align: 0.5; background-color: transparent; }
            element-text { horizontal-align: 0.5; vertical-align: 0.5; margin: 10px 0px 0px 0px; background-color: transparent; text-color: inherit; }
            inputbar { padding: 15px 20px; border-radius: 15px; children: [ "prompt", "entry" ]; }
            prompt { background-color: transparent; text-color: inherit; margin: 0px 10px 0px 0px; }
            entry { background-color: transparent; text-color: inherit; placeholder: "Search wallpapers..."; }
        ')

    if [ -n "$selected_clean" ]; then
        # Find the actual file with its extension
        selected=$(find "$WALL_DIR" -maxdepth 1 -type f -name "${selected_clean}.*" -exec basename {} \; -quit)
        
        if [ -n "$selected" ]; then
            # Apply wallpaper, sync colors with pywal, and update hyprlock cache
            awww img "$WALL_DIR/$selected" --transition-type center --transition-step 60 --transition-fps 120 --transition-duration 2
            wal -i "$WALL_DIR/$selected" -n -q
            mkdir -p "$HOME/.cache/hyprlock"
            cp "$WALL_DIR/$selected" "$HOME/.cache/hyprlock/current_wallpaper.png"
            notify-send "System Updated" "Theme synced with: $selected" -i "$WALL_DIR/$selected"
        fi
    fi
}

# --- 2. Calculator Logic (Using rofi-calc plugin) ---
launch_calculator() {
    rofi -show calc -modi calc -no-history -no-show-match -no-sort \
        -display-calc "> calculator" \
        -hint-result "fx    " \
        -calc-command "echo -n '{result}' | wl-copy && notify-send 'Calculator' 'Result copied to clipboard: {result}' -i accessories-calculator" \
        -theme "$BASE_THEME" \
        -theme-str '
            window { width: 600px; location: south; anchor: south; y-offset: -20px; border-radius: 20px; }
            mainbox { children: [ "inputbar", "message" ]; spacing: 15px; padding: 20px; background-color: transparent; }
            inputbar { padding: 15px 20px; border-radius: 12px; children: [ "prompt", "entry" ]; }
            prompt { text-color: inherit; margin: 0px 10px 0px 0px; }
            entry { text-color: inherit; placeholder: "Type an expression..."; }
            message { border-radius: 12px; background-color: #ffffff12; padding: 15px 20px; border: 0px; }
            textbox { text-color: #dddddd; background-color: transparent; vertical-align: 0.5; }
            listview { enabled: false; }
        '
}

# --- 3. System Management (GPU + Power Profiles) ---
launch_system_menu() {
    gpu_int="󰈐 GPU: Integrated Mode"
    gpu_hyb="󰢮 GPU: Hybrid Mode (HDMI)"
    perf_save="󰾆 Profile: Power Saver"
    perf_bal="󰓅 Profile: Balanced"
    perf_high="󱪓 Profile: Performance"
    
    options="$gpu_int\n$gpu_hyb\n---\n$perf_save\n$perf_bal\n$perf_high"

    choice=$(echo -e "$options" | rofi -dmenu -i -p "> system" -theme "$BASE_THEME" -theme-str '
        window { width: 550px; location: south; anchor: south; y-offset: -20px; border-radius: 20px; }
        mainbox { children: [ "listview", "inputbar" ]; spacing: 15px; padding: 20px; }
        listview { columns: 1; lines: 6; fixed-height: false; }
        prompt { margin: 0px 10px 0px 0px; }
    ')

    case "$choice" in
        *"Integrated"*) pkexec envycontrol -s integrated && notify-send "GPU Profile" "Switched to Integrated" -i power-profile-daemon ;;
        *"Hybrid"*)     pkexec envycontrol -s hybrid && notify-send "GPU Profile" "Switched to Hybrid" -i power-profile-daemon ;;
        *"Power Saver"*) powerprofilesctl set power-saver && notify-send "Performance Profile" "Switched to Power Saver" -i power-profile-daemon ;;
        *"Balanced"*)   powerprofilesctl set balanced && notify-send "Performance Profile" "Switched to Balanced" -i power-profile-daemon ;;
        *"Performance"*) powerprofilesctl set performance && notify-send "Performance Profile" "Switched to Performance" -i power-profile-daemon ;;
    esac
}

# --- 4. Wi-Fi Logic (nmcli with Categorized Networks) ---
launch_wifi_menu() {
    notify-send "Scanning..." "Looking for available Wi-Fi networks"
    nmcli device wifi rescan && sleep 1
    
    known_ssids=$(nmcli -g NAME,TYPE connection | awk -F: '$2=="802-11-wireless" {print $1}')
    wifi_list_raw=$(nmcli -t -f "SECURITY,SSID" device wifi list | grep -v '^\s*$' | awk -F: '{
        if ($2 == "") next; 
        icon = ($1 == "" || $1 == "--") ? " " : " ";
        print icon " | " $2;
    }' | awk '!seen[$0]++')

    saved_networks=""
    other_networks=""
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        current_ssid=$(echo "$line" | sed 's/^.* | //')
        if echo "$known_ssids" | grep -qxF "$current_ssid"; then saved_networks+="$line\n"; else other_networks+="$line\n"; fi
    done <<< "$wifi_list_raw"

    wifi_state=$(nmcli -fields WIFI g | grep -q "enabled" && echo "󰖪  Disable Wi-Fi" || echo "󰖩  Enable Wi-Fi")
    manual_opt="󰖩  Manual Connection (Failsafe)"
    final_list="$manual_opt\n$wifi_state\n"
    [ -n "$saved_networks" ] && final_list+="--- Saved Networks ---\n${saved_networks}"
    [ -n "$other_networks" ] && final_list+="--- Other Networks ---\n${other_networks}"

    chosen=$(echo -e "$final_list" | sed '/^$/d' | rofi -dmenu -i -p "> Wi-Fi" -theme "$BASE_THEME" -theme-str '
        window { width: 750px; location: south; anchor: south; y-offset: -20px; border-radius: 20px; }
        mainbox { children: [ "listview", "inputbar" ]; spacing: 15px; padding: 20px; }
        listview { columns: 2; lines: 8; fixed-height: false; dynamic: true; }
        prompt { margin: 0px 10px 0px 0px; }
    ')

    if [ -z "$chosen" ] || [[ "$chosen" == "---"* ]]; then exit 0
    elif [ "$chosen" = "$manual_opt" ]; then
        ssid=$(rofi -dmenu -p "> SSID" -theme "$BASE_THEME" -theme-str 'window { width: 400px; location: south; anchor: south; y-offset: -20px; border-radius: 20px; } mainbox { children: [ "inputbar" ]; }')
        [ -z "$ssid" ] && exit 0
        pass=$(rofi -dmenu -p "> Password" -password -theme "$BASE_THEME" -theme-str 'window { width: 400px; location: south; anchor: south; y-offset: -20px; border-radius: 20px; } mainbox { children: [ "inputbar" ]; }')
        nmcli device wifi connect "$ssid" password "$pass"
    elif [ "$chosen" = "󰖩  Enable Wi-Fi" ]; then nmcli radio wifi on
    elif [ "$chosen" = "󰖪  Disable Wi-Fi" ]; then nmcli radio wifi off
    else
        ssid=$(echo "$chosen" | sed 's/^.* | //')
        if nmcli connection show "$ssid" > /dev/null 2>&1; then nmcli connection up id "$ssid"
        else
            pass=$(rofi -dmenu -p "> Password" -password -theme "$BASE_THEME" -theme-str 'window { width: 400px; location: south; anchor: south; y-offset: -20px; border-radius: 20px; } mainbox { children: [ "inputbar" ]; }')
            [ -n "$pass" ] && nmcli device wifi connect "$ssid" password "$pass"
        fi
    fi
}

# --- 5. Advanced Bluetooth Logic ---
launch_bluetooth_device_menu() {
    mac=$(echo "$1" | cut -d ' ' -f 2)
    device_name=$(echo "$1" | cut -d ' ' -f 3-)

    info=$(bluetoothctl info "$mac")
    [[ "$info" =~ "Connected: yes" ]] && connected="󱘖 Connected: yes" || connected="󱘖 Connected: no"
    [[ "$info" =~ "Paired: yes" ]] && paired="󰂵 Paired: yes" || paired="󰂵 Paired: no"
    [[ "$info" =~ "Trusted: yes" ]] && trusted="󰒘 Trusted: yes" || trusted="󰒘 Trusted: no"
    
    options="$connected\n$paired\n$trusted\n---\nBack"

    chosen=$(echo -e "$options" | rofi -dmenu -i -p "> $device_name" -theme "$BASE_THEME" -theme-str '
        window { width: 500px; location: south; anchor: south; y-offset: -20px; border-radius: 20px; }
        mainbox { children: [ "listview", "inputbar" ]; spacing: 15px; padding: 20px; }
        listview { columns: 1; lines: 5; }
        prompt { margin: 0px 10px 0px 0px; }
    ')

    case "$chosen" in
        *"Connected: yes") bluetoothctl disconnect "$mac" && launch_bluetooth_device_menu "$1" ;;
        *"Connected: no")  bluetoothctl connect "$mac" && launch_bluetooth_device_menu "$1" ;;
        *"Paired: yes")    bluetoothctl remove "$mac" && launch_bluetooth_menu ;;
        *"Paired: no")     bluetoothctl pair "$mac" && launch_bluetooth_device_menu "$1" ;;
        *"Trusted: yes")   bluetoothctl untrust "$mac" && launch_bluetooth_device_menu "$1" ;;
        *"Trusted: no")    bluetoothctl trust "$mac" && launch_bluetooth_device_menu "$1" ;;
        "Back")            launch_bluetooth_menu ;;
    esac
}

launch_bluetooth_menu() {
    if bluetoothctl show | grep -q "Powered: yes"; then
        power="󰂯 Power: on"
        bluetoothctl show | grep -q "Discovering: yes" && scan="󰂰 Scan: on" || scan="󰂰 Scan: off"
        bluetoothctl show | grep -q "Pairable: yes" && pairable="󰂵 Pairable: on" || pairable="󰂵 Pairable: off"
        bluetoothctl show | grep -q "Discoverable: yes" && discoverable="󰂶 Discoverable: on" || discoverable="󰂶 Discoverable: off"
        devices=$(bluetoothctl devices | cut -d ' ' -f 3-)
        options="$devices\n---\n$power\n$scan\n$pairable\n$discoverable"
    else
        power="󰂲 Power: off"
        options="$power"
    fi

    chosen=$(echo -e "$options" | rofi -dmenu -i -p "> Bluetooth" -theme "$BASE_THEME" -theme-str '
        window { width: 600px; location: south; anchor: south; y-offset: -20px; border-radius: 20px; }
        mainbox { children: [ "listview", "inputbar" ]; spacing: 15px; padding: 20px; }
        listview { columns: 1; lines: 8; fixed-height: false; }
        prompt { margin: 0px 10px 0px 0px; }
    ')

    case "$chosen" in
        ""| "---") exit 0 ;;
        "󰂯 Power: on")  bluetoothctl power off && launch_bluetooth_menu ;;
        "󰂲 Power: off") bluetoothctl power on && launch_bluetooth_menu ;;
        "󰂰 Scan: on")   bluetoothctl scan off && launch_bluetooth_menu ;;
        "󰂰 Scan: off")  (bluetoothctl --timeout 5 scan on &) && notify-send "Bluetooth" "Scanning..." && launch_bluetooth_menu ;;
        "󰂵 Pairable: on")    bluetoothctl pairable off && launch_bluetooth_menu ;;
        "󰂵 Pairable: off")   bluetoothctl pairable on && launch_bluetooth_menu ;;
        "󰂶 Discoverable: on")  bluetoothctl discoverable off && launch_bluetooth_menu ;;
        "󰂶 Discoverable: off") bluetoothctl discoverable on && launch_bluetooth_menu ;;
        *) 
            device_full=$(bluetoothctl devices | grep "$chosen")
            [[ -n "$device_full" ]] && launch_bluetooth_device_menu "$device_full"
            ;;
    esac
}

# --- 6. Action Bridge ---
case "$1" in
    --wallpaper) launch_wallpaper_picker ; exit 0 ;;
    --calc)      launch_calculator ; exit 0 ;;
    --system)    launch_system_menu ; exit 0 ;;
    --wifi)      launch_wifi_menu ; exit 0 ;;
    --bt)        launch_bluetooth_menu ; exit 0 ;;
    --lock)      hyprlock ; exit 0 ;;
    --sleep)     systemctl suspend ; exit 0 ;;
    --reboot)    systemctl reboot ; exit 0 ;;
    --shutdown)  systemctl poweroff ; exit 0 ;;
    --logout)    hyprctl dispatch exit ; exit 0 ;;
esac

# --- 7. Command Generation (Keywords for ">command" search) ---
create_cmd() {
    cat <<EOF > "$CMD_DIR/z_cmd_$1.desktop"
[Desktop Entry]
Name=$2
Comment=$3
Keywords=>$1;>$2;
Icon=$4
Exec=$SCRIPT_PATH $5
Terminal=false
Type=Application
Categories=System;
EOF
}

# Clean old commands before regenerating (prevents orphans)
rm -f "$CMD_DIR/z_cmd_"*.desktop

# Generate commands ALPHABETICALLY
create_cmd "bt" "Bluetooth" "Manage bluetooth devices" "bluetooth" "--bt"
create_cmd "calc" "Calculator" "Evaluate mathematical expressions" "accessories-calculator" "--calc"
create_cmd "lock" "Lock" "Lock the current session" "system-lock-screen" "--lock"
create_cmd "logout" "Logout" "Exit the current session" "system-log-out" "--logout"
create_cmd "reboot" "Reboot" "Restart the system" "system-reboot" "--reboot"
create_cmd "shutdown" "Shutdown" "Power off the system" "system-shutdown" "--shutdown"
create_cmd "sleep" "Sleep" "Suspend then hibernate" "system-suspend" "--sleep"
create_cmd "sys" "System" "Manage GPU and Power Profiles" "preferences-system-power" "--system"
create_cmd "wall" "Wallpaper" "Change wallpaper and sync colors" "preferences-desktop-wallpaper" "--wallpaper"
create_cmd "wifi" "Wi-Fi" "Manage wireless networks" "network-wireless" "--wifi"

# --- 8. Fallback Logic (DuckDuckGo Search) ---
FALLBACK_SCRIPT="$CMD_DIR/fallback_search.sh"
cat << 'EOF' > "$FALLBACK_SCRIPT"
#!/usr/bin/env bash
[[ "$1" == ">"* ]] && exit 0
coproc ( firefox "https://duckduckgo.com/?q=$1" > /dev/null 2>&1 )
EOF
chmod +x "$FALLBACK_SCRIPT"

# --- 9. Web Search Tab Logic (Google Search) ---
WEB_SCRIPT="$CMD_DIR/web_search.sh"
cat << 'EOF' > "$WEB_SCRIPT"
#!/usr/bin/env bash
if [ -n "$1" ]; then
    coproc ( firefox "https://www.google.com/search?q=$1" > /dev/null 2>&1 )
    exit 0
fi
EOF
chmod +x "$WEB_SCRIPT"

# --- 10. Main Rofi Launch ---
update-desktop-database "$CMD_DIR"
rm -f "$HOME/.cache/rofi-"*.druncache 2>/dev/null
export XDG_DATA_DIRS="$CMD_DIR:$HOME/.local/share/applications:/usr/local/share:/usr/share:/var/lib/flatpak/exports/share"

rofi -show drun \
    -modi "drun,filebrowser,run, Web Search:$WEB_SCRIPT" \
    -sort true \
    -sorting-method fzf \
    -drun-match-fields name,generic,exec,categories,keywords \
    -display-drun "󰀻 Apps" \
    -display-filebrowser " Files" \
    -display-run " Terminal" \
    -theme "$BASE_THEME" \
    -drun-display-format "<b>{name}</b>"$'\n'"<span size='x-small' alpha='75%'>{comment}</span>" \
    -theme-str '
        window { location: south; anchor: south; width: 720px; y-offset: -20px; children: [ "mainbox" ]; }
        mainbox { children: [ "mode-switcher", "listview", "inputbar" ]; background-color: transparent; spacing: 15px; }
        mode-switcher { spacing: 10px; background-color: transparent; margin: 0px 0px 5px 0px; }
        button { padding: 10px 10px; border-radius: 12px; background-color: #ffffff10; text-color: #a0a0a0; cursor: pointer; }
        button selected { background-color: #ffffff30; text-color: #ffffff; }
        listview { columns: 1; lines: 7; fixed-height: false; dynamic: true; scrollbar: false; }
        element-text { vertical-align: 0.5; markup: true; }
        inputbar { children: [ "entry" ]; }
        entry { placeholder: " Search..."; }
    '
