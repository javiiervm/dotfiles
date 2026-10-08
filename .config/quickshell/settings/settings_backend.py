#!/usr/bin/env python3
"""One-shot settings bridge for the existing Hyprland Lua + Quickshell QML files.

Reads the original config at launch and edits only a narrow, allowlisted set of
properties when the user presses Apply. No daemon, loop, polling or dependencies
outside the Python standard library.
"""

from __future__ import annotations

import json
import math
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile

HOME = Path.home()
HYPR = HOME / ".config/hypr/hyprland.lua"
GLASS = HOME / ".config/quickshell/Glass.qml"
THEME = HOME / ".config/quickshell/Theme.qml"

# (file, enclosing Lua blocks or QML property type, property name, type, min, max)
FIELDS = {
    "hypr_blur_enabled": ("hypr", ("decoration", "blur"), "enabled", "bool", None, None),
    "hypr_blur_size": ("hypr", ("decoration", "blur"), "size", "int", 1, 12),
    "hypr_blur_passes": ("hypr", ("decoration", "blur"), "passes", "int", 1, 5),
    "hypr_active_opacity": ("hypr", ("decoration",), "active_opacity", "float", 0.35, 1.0),
    "hypr_inactive_opacity": ("hypr", ("decoration",), "inactive_opacity", "float", 0.35, 1.0),
    "hypr_rounding": ("hypr", ("decoration",), "rounding", "int", 0, 30),
    "hypr_gaps_in": ("hypr", ("general",), "gaps_in", "int", 0, 30),
    "hypr_border_size": ("hypr", ("general",), "border_size", "int", 0, 8),
    "hypr_animations": ("hypr", ("animations",), "enabled", "bool", None, None),
    "glass_tint": ("glass", "color", "tint", "color", None, None),
    "glass_opacity": ("glass", "real", "opacity", "float", 0.05, 1.0),
    "glass_blur": ("glass", "bool", "blurEnabled", "bool", None, None),
    "glass_border": ("glass", "real", "borderOpacity", "float", 0, 1.0),
    "glass_radius": ("glass", "int", "radius", "int", 0, 32),
    "theme_accent": ("theme", "color", "blue", "color", None, None),
    "theme_background": ("theme", "color", "bg0", "color", None, None),
}
PATHS = {"hypr": HYPR, "glass": GLASS, "theme": THEME}


def lua_block(text: str, names: tuple[str, ...]) -> tuple[int, int]:
    """Find a named Lua table including nested blocks, ignoring quoted braces."""
    lo, hi = 0, len(text)
    for name in names:
        match = re.search(r"(?m)^[ \t]*" + re.escape(name) + r"[ \t]*=[ \t]*\{", text[lo:hi])
        if not match:
            raise ValueError(f"Lua block not found: {'.'.join(names)} ({name})")
        begin = lo + match.end() - 1
        depth = 0
        quote = None
        cursor = begin
        while cursor < hi:
            ch = text[cursor]
            if quote:
                if ch == "\\":
                    cursor += 2
                    continue
                if ch == quote:
                    quote = None
            elif text.startswith("--", cursor):
                nl = text.find("\n", cursor)
                cursor = hi if nl < 0 else nl + 1
                continue
            elif ch in "\"'":
                quote = ch
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    lo, hi = begin + 1, cursor
                    break
            cursor += 1
        else:
            raise ValueError(f"Unterminated Lua block: {name}")
    return lo, hi


def value_match(text: str, key: str, lo: int, hi: int):
    # Anchored property lines only; doesn't match comments or unrelated blocks.
    rx = re.compile(r"(?m)^([ \t]*" + re.escape(key) + r"[ \t]*=[ \t]*)([^,\n]+)(,[^\n]*)?$")
    match = rx.search(text, lo, hi)
    if not match:
        raise ValueError(f"Lua property not found: {key}")
    return match


def qml_match(text: str, typ: str, key: str):
    rx = re.compile(
        r"(?m)^([ \t]*readonly[ \t]+property[ \t]+" + re.escape(typ)
        + r"[ \t]+" + re.escape(key) + r"[ \t]*:[ \t]*)([^\n]+)$"
    )
    match = rx.search(text)
    if not match:
        raise ValueError(f"QML property not found: {key}")
    return match


def get_raw(text: str, spec: tuple) -> str:
    group, nesting, prop, _, _, _ = spec
    match = value_match(text, prop, *lua_block(text, nesting)) if group == "hypr" else qml_match(text, nesting, prop)
    return match.group(2).strip()


def decode(raw: str, kind: str):
    if kind == "bool":
        if raw not in ("true", "false"):
            raise ValueError(f"Unexpected boolean value: {raw}")
        return raw == "true"
    if kind == "color":
        value = raw.strip("\"'").lower()
        if not re.fullmatch(r"#[0-9a-f]{6}", value):
            raise ValueError(f"Expected a #RRGGBB color, got: {raw}")
        return value
    number = float(raw)
    if not math.isfinite(number):
        raise ValueError(f"Non-finite value: {raw}")
    return int(number) if kind == "int" else number


def encode(value, kind: str, minimum, maximum) -> tuple[object, str]:
    if kind == "bool":
        if type(value) is not bool:
            raise ValueError("Use an on/off value")
        return value, "true" if value else "false"
    if kind == "color":
        if not isinstance(value, str) or not re.fullmatch(r"#[0-9a-fA-F]{6}", value):
            raise ValueError("Use a color like #61afef (6 hexadecimal digits)")
        value = value.lower()
        return value, f'"{value}"'
    if isinstance(value, bool):
        raise ValueError("Enter a numeric value")
    try:
        number = float(value)
    except (TypeError, ValueError) as exc:
        raise ValueError("Enter a valid number") from exc
    if not math.isfinite(number) or not minimum <= number <= maximum:
        raise ValueError(f"Value must be between {minimum} and {maximum}")
    if kind == "int":
        if not number.is_integer():
            raise ValueError("Enter a whole number")
        val = int(number)
        return val, str(val)
    val = round(number, 3)
    return val, str(val)


def read_files() -> dict[str, str]:
    return {group: path.read_text(encoding="utf-8") for group, path in PATHS.items()}


def read_values(files: dict[str, str]) -> dict:
    values = {}
    for key, spec in FIELDS.items():
        values[key] = decode(get_raw(files[spec[0]], spec), spec[3])
    return values


def replace_value(text: str, spec: tuple, encoded: str) -> str:
    group, nesting, prop, _, _, _ = spec
    match = value_match(text, prop, *lua_block(text, nesting)) if group == "hypr" else qml_match(text, nesting, prop)
    return text[:match.start(2)] + encoded + text[match.end(2):]


def atomic_write(path: Path, content: str):
    # Save the original once, outside the Quickshell config watcher paths.
    backup_dir = HOME / ".local/state/dotfiles-settings/backups"
    backup_dir.mkdir(parents=True, exist_ok=True)
    backup = backup_dir / ("hyprland.lua" if path == HYPR else path.name)
    if not backup.exists():
        shutil.copy2(path, backup)
    # Keep symbolic links intact (dotfiles are sometimes symlinked into HOME).
    real_path = path.resolve()
    mode = stat.S_IMODE(real_path.stat().st_mode)
    fd, name = tempfile.mkstemp(prefix=".settings-", dir=real_path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(name, mode)
        os.replace(name, real_path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def apply(payload: dict):
    if not isinstance(payload, dict) or set(payload) != set(FIELDS):
        raise ValueError("Incomplete or unexpected settings payload")
    original = read_files()
    # Verify and validate ALL settings before writing even one file.
    original_values = read_values(original)
    encoded_values = {}
    validated_values = {}
    for key, spec in FIELDS.items():
        try:
            validated_values[key], encoded_values[key] = encode(payload[key], spec[3], spec[4], spec[5])
        except ValueError as exc:
            raise ValueError(f"{key}: {exc}") from exc

    modified = dict(original)
    for key, spec in FIELDS.items():
        if validated_values[key] == original_values[key]:
            continue
        group = spec[0]
        modified[group] = replace_value(modified[group], spec, encoded_values[key])
    changed = [group for group in PATHS if modified[group] != original[group]]
    for group in changed:
        atomic_write(PATHS[group], modified[group])

    # Quickshell reloads its affected QML config files itself. The separate
    # settings process does not run a watcher or keep a helper alive.
    warning = ""
    if "hypr" in changed:
        try:
            proc = subprocess.run(["hyprctl", "reload"], capture_output=True, text=True, timeout=10, check=False)
            if proc.returncode:
                warning = "Hyprland was saved, but reload failed: " + (proc.stderr.strip() or proc.stdout.strip())[:170]
        except (OSError, subprocess.TimeoutExpired) as exc:
            warning = "Hyprland was saved, but reload could not run: " + str(exc)

    return {"ok": True, "changed": changed, "warning": warning}




def qml_literal_property(text: str, kind: str, name: str):
    """Read one simple scalar from the original QML singleton (not evaluate JS)."""
    found = qml_match(text, kind, name)
    expression = found.group(2).strip().split("//", 1)[0].strip()
    if kind in ("color", "string"):
        match = re.fullmatch(r"['\"]([^'\"]+)['\"]", expression)
        if not match:
            raise ValueError(f"Unsupported QML literal for {name}: {expression}")
        value = match.group(1)
        if kind == "color" and not re.fullmatch(r"#[0-9a-fA-F]{6}", value):
            raise ValueError(f"Invalid theme color: {name}")
        return value
    if kind == "bool":
        if expression not in ("true", "false"):
            raise ValueError(f"Invalid theme boolean: {name}")
        return expression == "true"
    number = float(expression)
    if not math.isfinite(number):
        raise ValueError(f"Invalid theme number: {name}")
    return int(number) if kind == "int" else number


def read_appearance(files: dict[str, str]) -> dict:
    """Quickshell theme snapshot for a separate, on-demand UI. No polling."""
    theme_types = {
        "white": "color", "bg0": "color", "blue": "color", "red": "color",
        "yellow": "color", "grey1": "color", "fontMain": "string", "fontIcons": "string",
    }
    glass_types = {
        "tint": "color", "opacity": "real", "blurEnabled": "bool",
        "borderOpacity": "real", "borderWidth": "real", "highlightOpacity": "real",
        "radius": "int", "radiusSmall": "int", "radiusLarge": "int",
    }
    return {
        "theme": {name: qml_literal_property(files["theme"], typ, name)
                  for name, typ in theme_types.items()},
        "glass": {name: qml_literal_property(files["glass"], typ, name)
                  for name, typ in glass_types.items()},
    }


def main():
    try:
        if len(sys.argv) == 2 and sys.argv[1] == "read":
            files = read_files()
            result = {"ok": True, "values": read_values(files), "appearance": read_appearance(files)}
        elif len(sys.argv) == 3 and sys.argv[1] == "apply":
            result = apply(json.loads(sys.argv[2]))
        else:
            raise ValueError("Usage: settings_backend.py read | apply '<json>'")
        print(json.dumps(result, separators=(",", ":")))
        return 0
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, separators=(",", ":")))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
