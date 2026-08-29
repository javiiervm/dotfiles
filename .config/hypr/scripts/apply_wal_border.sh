#!/usr/bin/env bash

WAL_COLORS="$HOME/.cache/wal/colors.sh"

[ -f "$WAL_COLORS" ] || exit 0

# pywal may reference optional shell variables internally,
# therefore we deliberately don't use `set -u` here.
# shellcheck disable=SC1090
source "$WAL_COLORS"

color1_hex="${color1#\#}"
color2_hex="${color2#\#}"
background_hex="${background#\#}"

hyprctl eval "
hl.config({
    general = {
        col = {
            active_border = {
                colors = {
                    \"rgb(${color1_hex})\",
                    \"rgb(${color2_hex})\"
                },
                angle = 45
            },
            inactive_border = \"rgb(${background_hex})\"
        }
    }
})
" >/dev/null