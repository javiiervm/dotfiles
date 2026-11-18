#!/usr/bin/env python3
"""Generate one coordinated, locally contrasted CAVA color per bar.

The hue comes from the existing pywal palette/wallpaper; only the lightness
changes across the screen. Each bar is tuned against the corresponding
horizontal area of the wallpaper's bottom third. No continuous image analysis:
this script runs only on startup and wallpaper / pywal changes.

Usage: python3 cava_wallpaper_color.py [number_of_bars]
Output: #RRGGBB;#RRGGBB;... (one line, one color per bar)
"""

import colorsys
import json
import sys
from pathlib import Path

from PIL import Image, ImageStat

WAL_CACHE = Path.home() / ".cache/wal/colors.json"
WALLPAPER_POINTER = Path.home() / ".cache/qs_wall_path"
FALLBACK_POINTER = Path("/tmp/current_wallpaper")
DEFAULT_BAR_COUNT = 40
TARGET_CONTRAST = 3.1
BAR_OPACITY = 0.96  # Keep in sync with CavaOverlay.qml.
FALLBACK_BACKGROUND = (0.10, 0.16, 0.23)


def is_hex(value):
    if not isinstance(value, str) or len(value) != 7 or not value.startswith("#"):
        return False
    try:
        int(value[1:], 16)
        return True
    except ValueError:
        return False


def from_hex(value):
    return tuple(int(value[i:i + 2], 16) / 255.0 for i in (1, 3, 5))


def luminance(rgb):
    def linear(v):
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4

    r, g, b = (linear(v) for v in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast_ratio(foreground, background):
    # Compare what is actually rendered, accounting for bar opacity.
    visible = tuple(
        BAR_OPACITY * fg + (1.0 - BAR_OPACITY) * bg
        for fg, bg in zip(foreground, background)
    )
    a, b = luminance(visible), luminance(background)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)


def read_palette():
    try:
        value = json.loads(WAL_CACHE.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def read_wallpaper_path(palette):
    for path_file in (WALLPAPER_POINTER, FALLBACK_POINTER):
        try:
            candidate = path_file.read_text(encoding="utf-8").strip()
            if candidate and Path(candidate).expanduser().is_file():
                return candidate
        except OSError:
            pass
    return palette.get("wallpaper", "")


def background_columns(path, bars, fallback):
    try:
        with Image.open(Path(path).expanduser()) as raw:
            width, height = raw.size
            # Use the zone behind the tallest bars, with horizontal detail.
            bottom = raw.crop((0, int(height * 2 / 3), width, height))
            bottom = bottom.convert("RGB").resize((bars, 24), Image.Resampling.LANCZOS)
            result = []
            for x in range(bars):
                band = bottom.crop((x, 0, x + 1, 24))
                result.append(tuple(v / 255.0 for v in ImageStat.Stat(band).mean[:3]))
            return result
    except (OSError, ValueError):
        return [fallback] * bars


def pick_hue(palette, backgrounds):
    average = tuple(sum(c[i] for c in backgrounds) / len(backgrounds) for i in range(3))
    image_h, _, image_s = colorsys.rgb_to_hls(*average)

    candidates = []
    colors = palette.get("colors", {})
    if isinstance(colors, dict):
        for index in (*range(1, 8), *range(9, 16)):
            value = colors.get(f"color{index}")
            if is_hex(value):
                h, _, s = colorsys.rgb_to_hls(*from_hex(value))
                candidates.append((h, s))

    if image_s >= 0.12:
        if candidates:
            def hue_distance(h):
                d = abs(h - image_h)
                return min(d, 1.0 - d)

            nearest_h, nearest_s = min(candidates, key=lambda c: hue_distance(c[0]))
            if hue_distance(nearest_h) < 0.11:
                return nearest_h, max(0.40, min(0.72, nearest_s))
        return image_h, max(0.40, min(0.72, image_s))

    if candidates:
        hue, saturation = max(candidates, key=lambda c: c[1])
        return hue, max(0.40, min(0.72, saturation))
    return 0.57, 0.52


def adjusted_color(hue, saturation, background, prefer_light):
    def color_at(lightness):
        return colorsys.hls_to_rgb(hue, lightness, saturation)

    # For an uncluttered look, favor the same bright/dark direction over
    # the whole screen; reverse only where that would be insufficient.
    light = prefer_light
    if contrast_ratio(color_at(1.0 if light else 0.0), background) < TARGET_CONTRAST:
        light = not light

    if light:
        # Find the least bright shade achieving the desired contrast.
        lo, hi = 0.0, 1.0
        for _ in range(18):
            mid = (lo + hi) / 2
            if contrast_ratio(color_at(mid), background) >= TARGET_CONTRAST:
                hi = mid
            else:
                lo = mid
        chosen = color_at(hi)
    else:
        # Find the least dark shade achieving the desired contrast.
        lo, hi = 0.0, 1.0
        for _ in range(18):
            mid = (lo + hi) / 2
            if contrast_ratio(color_at(mid), background) >= TARGET_CONTRAST:
                lo = mid
            else:
                hi = mid
        chosen = color_at(lo)

    return "#" + "".join(f"{round(v * 255):02x}" for v in chosen)


def main():
    try:
        bars = int(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_BAR_COUNT
        if not 1 <= bars <= 256:
            raise ValueError("Invalid bar count")
    except ValueError:
        print("Invalid number of CAVA bars", file=sys.stderr)
        return 2

    palette = read_palette()
    special = palette.get("special", {})
    hex_bg = special.get("background") if isinstance(special, dict) else None
    fallback = from_hex(hex_bg) if is_hex(hex_bg) else FALLBACK_BACKGROUND
    columns = background_columns(read_wallpaper_path(palette), bars, fallback)
    hue, saturation = pick_hue(palette, columns)

    overall_luminance = sum(luminance(c) for c in columns) / bars
    prefer_light = overall_luminance < 0.18
    print(";".join(adjusted_color(hue, saturation, bg, prefer_light) for bg in columns))
    return 0


if __name__ == "__main__":
    sys.exit(main())
