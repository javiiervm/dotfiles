#!/usr/bin/env bash

# Paths
theme="$HOME/.config/rofi/launchers/type-2/style-2.rasi"
dir="$(xdg-user-dir PICTURES)/Screenshots"

# Ensure directory exists
[[ ! -d "$dir" ]] && mkdir -p "$dir"

# Internal function for notifications
notify_view() {
  notify-send "Screenshot Captured" "Saved in $dir" -i "image-x-generic"
}

# Logic to skip menu if arguments are passed
case $1 in
"--desktop")
  sleep 0.2 && hyprshot -m output -o "$dir"
  notify_view
  exit 0
  ;;
"--area")
  hyprshot -m region -o "$dir"
  notify_view
  exit 0
  ;;
esac

# Default: Show Rofi Menu if no arguments
option_1="󰹑  Capture Desktop"
option_2="󰒅  Capture Area"
option_3="󰖭  Capture Window"

chosen="$(echo -e "$option_1\n$option_2\n$option_3" | rofi -dmenu -i -theme "$theme" -p "Screenshot")"

case ${chosen} in
"$option_1") sleep 0.2 && hyprshot -m output -o "$dir" ;;
"$option_2") hyprshot -m region -o "$dir" ;;
"$option_3") sleep 0.2 && hyprshot -m window -o "$dir" ;;
esac
