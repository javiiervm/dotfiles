#!/bin/bash
CURSOR_THEME="Bibata-Modern-Classic"
CURSOR_SIZE=24

gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR_THEME"
gsettings set org.gnome.desktop.interface cursor-size "$CURSOR_SIZE"

mkdir -p ~/.icons/default
echo -e "[Icon Theme]\nInherits=$CURSOR_THEME" > ~/.icons/default/index.theme
