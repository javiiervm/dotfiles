#!/usr/bin/env bash

# Paths
WALL_DIR="$HOME/.config/rofi/wallpapers"
BASE_THEME="$HOME/.config/rofi/launchers/type-2/style-2.rasi"
PICKER_THEME="$HOME/.config/rofi/wall-picker.rasi"

# 1. Ensure awww-daemon is running
if ! pgrep -x "awww-daemon" > /dev/null; then
    awww-daemon &
    sleep 0.5
fi

list_walls() {
    cd "$WALL_DIR" || exit
    for wall in *; do
        if [ -f "$wall" ]; then
            echo -en "$wall\0icon\x1f$WALL_DIR/$wall\n"
        fi
    done
}

# 2. Run Rofi
selected=$(list_walls | rofi -dmenu -i \
    -theme "$BASE_THEME" \
    -theme "$PICKER_THEME" \
    -p "Wallpaper")

# 3. Change wallpaper and generate colors
if [ -n "$selected" ]; then
    # Change the background with awww
    awww img "$WALL_DIR/$selected" \
        --transition-type center \
        --transition-step 60 \
        --transition-fps 120 \
        --transition-duration 2
    
    # --- AUTOMATIC COLOR GENERATION ---
    # -i: Input image
    # -n: Skip setting the wallpaper (since awww already did it)
    # -q: Quiet mode
    wal -i "$WALL_DIR/$selected" -n -q

    # --- SINCRONIZACIÓN CON HYPRLOCK ---
    mkdir -p "$HOME/.cache/hyprlock"
    rm -f "$HOME/.cache/hyprlock/current_wallpaper.png"
    cp "$WALL_DIR/$selected" "$HOME/.cache/hyprlock/current_wallpaper.png"
        
    notify-send "System Updated" "Theme synced with: $selected" -i "$WALL_DIR/$selected"
fi
