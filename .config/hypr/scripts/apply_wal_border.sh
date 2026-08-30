#!/usr/bin/env bash

WAL_JSON="$HOME/.cache/wal/colors.json"

[ -f "$WAL_JSON" ] || exit 1

readarray -t WAL_VALUES < <(
    python3 - "$WAL_JSON" <<'PY'
import json
import sys

with open(sys.argv[1], "r") as f:
    data = json.load(f)

colors = data["colors"]
special = data["special"]

print(colors["color1"].lstrip("#"))
print(colors["color2"].lstrip("#"))
print(special["background"].lstrip("#"))
PY
)

color1_hex="${WAL_VALUES[0]}"
color2_hex="${WAL_VALUES[1]}"
background_hex="${WAL_VALUES[2]}"

/usr/bin/hyprctl eval "
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
"