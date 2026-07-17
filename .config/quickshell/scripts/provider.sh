#!/usr/bin/env bash

MODE=$1
ARG2=$2
RECENTS_FILE="$HOME/.cache/qs_recents"
touch "$RECENTS_FILE"

# =================================================================
# MODO 0: APLICACIONES (Limpio y exclusivo para apps reales)
# =================================================================
if [ "$MODE" = "--apps" ]; then
    > /tmp/qs_apps.txt
    
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
        # 1. Mostrar primero las recientes (si existen)
        if [ -s "$RECENTS_FILE" ]; then
            tac "$RECENTS_FILE" | awk '!seen[$0]++' | head -n 10 | while read -r r_name; do 
                grep "^$r_name|" /tmp/qs_apps.txt | head -n 1
            done
        fi
        
        # 2. Mostrar el resto ordenado alfabéticamente
        sort -f /tmp/qs_apps.txt
    ) | awk -F'|' '!seen[$1]++'

fi