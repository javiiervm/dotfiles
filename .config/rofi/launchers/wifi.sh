#!/usr/bin/env bash

# Path to your Rofi theme
theme="$HOME/.config/rofi/launchers/type-2/style-2.rasi"

# 1. SCANNING PHASE
# Notify the user that the scan has started
notify-send "Scanning..." "Looking for available Wi-Fi networks"
nmcli device wifi rescan
sleep 2

# 2. DATA EXTRACTION
# We create a list with a very clear separator " | ".
# We will use this separator later to strip the icons safely.
wifi_list_raw=$(nmcli -t -f "SECURITY,SSID" device wifi list | grep -v '^\s*$' | awk -F: '{
    if ($2 == "") next; # Skip hidden or empty SSIDs
    icon = ($1 == "" || $1 == "--") ? " " : " ";
    print icon " | " $2;
}' | awk '!seen[$0]++')

# 3. CLASSIFICATION (Saved vs Other)
# Get the names of networks that already have a persistent profile in NetworkManager
known_ssids=$(nmcli -g NAME,TYPE connection | awk -F: '$2=="802-11-wireless" {print $1}')

saved_networks=""
other_networks=""

while IFS= read -r line; do
    [ -z "$line" ] && continue
    
    # Extract the clean SSID by removing everything before and including the " | "
    # This is the most robust way to handle any icon or special characters.
    current_ssid=$(echo "$line" | sed 's/^.* | //')
    
    if echo "$known_ssids" | grep -qxF "$current_ssid"; then
        saved_networks+="$line\n"
    else
        other_networks+="$line\n"
    fi
done <<< "$wifi_list_raw"

# 4. MENU CONSTRUCTION
wifi_state=$(nmcli -fields WIFI g | grep -q "enabled" && echo "󰖪  Disable Wi-Fi" || echo "󰖩  Enable Wi-Fi")
manual_opt="󰖩  Manual Connection (Failsafe)"

# Re-establishing headers: Failsafe and Toggle always go first
final_list="$manual_opt\n$wifi_state\n"

if [ -n "$saved_networks" ]; then
    final_list+="--- Saved Networks ---\n${saved_networks}"
fi

if [ -n "$other_networks" ]; then
    final_list+="--- Other Networks ---\n${other_networks}"
fi

# 5. USER INTERFACE (Rofi)
chosen_network=$(echo -e "$final_list" | sed '/^$/d' | rofi -dmenu -i -p "Wi-Fi: " -theme "$theme")

# Exit if user cancels or clicks a separator
[ -z "$chosen_network" ] || [[ "$chosen_network" =~ "---" ]] && exit

# 6. EXECUTION LOGIC
if [ "$chosen_network" = "$manual_opt" ]; then
    # FAILSAFE MANUAL MODE
    # Directly uses the strings entered by the user
    manual_ssid=$(rofi -dmenu -p "Enter SSID: " -theme "$theme")
    [ -z "$manual_ssid" ] && exit
    
    manual_pass=$(rofi -dmenu -p "Enter Password: " -password -theme "$theme")
    [ -z "$manual_pass" ] && exit
    
    notify-send "Connecting..." "Attempting failsafe connection to $manual_ssid"
    output=$(nmcli device wifi connect "$manual_ssid" password "$manual_pass" 2>&1)
    
    if [ $? -eq 0 ]; then
        # Ask to save the network after a successful connection
        save_choice=$(echo -e "Yes\nNo" | rofi -dmenu -i -p "Save this network permanently?" -theme "$theme")
        if [ "$save_choice" = "No" ]; then
            nmcli connection delete "$manual_ssid"
            notify-send "Success" "Connected to $manual_ssid (Profile discarded)"
        else
            notify-send "Success" "Connected and profile saved"
        fi
    else
        notify-send -u critical "Manual Connection Failed" "$output"
    fi

elif [ "$chosen_network" = "󰖩  Enable Wi-Fi" ]; then
    nmcli radio wifi on
elif [ "$chosen_network" = "󰖪  Disable Wi-Fi" ]; then
    nmcli radio wifi off
else
    # REGULAR CONNECTION MODE
    # CLEANING LOGIC: Delete everything from the start of the line until the " | " separator.
    # This ensures that icons NEVER reach the nmcli command.
    chosen_id=$(echo "$chosen_network" | sed 's/^.* | //')

    # Try to bring up the connection if it exists, or connect as new if it doesn't
    if nmcli connection show "$chosen_id" > /dev/null 2>&1; then
        output=$(nmcli connection up id "$chosen_id" 2>&1)
    else
        if [[ "$chosen_network" =~ "" ]]; then
            pass_entry=$(rofi -dmenu -p "Password for $chosen_id: " -password -theme "$theme")
            [ -z "$pass_entry" ] && exit
            output=$(nmcli device wifi connect "$chosen_id" password "$pass_entry" 2>&1)
        else
            output=$(nmcli device wifi connect "$chosen_id" 2>&1)
        fi
    fi

    # Final result notification
    if [ $? -eq 0 ]; then
        notify-send "Connected" "Successfully connected to $chosen_id"
    else
        notify-send -u critical "Wi-Fi Error" "Target SSID: '$chosen_id'\n\n$output"
    fi
fi
