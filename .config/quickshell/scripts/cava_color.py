#!/usr/bin/env python3
import colorsys
import hashlib
import io
import json
import os
import sys
import urllib.parse
import urllib.request
from pathlib import Path
from PIL import Image

CACHE_PATH = Path.home() / ".cache" / "quickshell" / "artwork_palette_cache.json"
MAX_CACHE_ENTRIES = 256
MAX_REMOTE_BYTES = 10 * 1024 * 1024


def get_contrast_color(img_path):
    # Comportamiento original: se conserva para WallpaperCarousel/provider.sh.
    try:
        with Image.open(img_path) as raw:
            img = raw.convert("RGB").resize((1, 1), Image.Resampling.LANCZOS)
            r, g, b = img.getpixel((0, 0))
        h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
        s = min(1.0, s * 1.3)
        new_l = 0.15 if l > 0.4 else 0.85
        nr, ng, nb = colorsys.hls_to_rgb(h, new_l, s)
        return f"#{int(nr*255):02x}{int(ng*255):02x}{int(nb*255):02x}"
    except Exception:
        return "#ffffff"


def _local_path(source):
    if source.startswith("file://"):
        return urllib.parse.unquote(urllib.parse.urlparse(source).path)
    if "://" not in source:
        return os.path.expanduser(source)
    return None


def _open_image(source):
    local = _local_path(source)
    if local:
        return Image.open(local)

    parsed = urllib.parse.urlparse(source)
    if parsed.scheme not in ("http", "https"):
        raise ValueError("Unsupported artwork source")

    req = urllib.request.Request(
        source,
        headers={
            "User-Agent": "Mozilla/5.0 QuickshellArtworkPalette/1.0",
            "Accept": "image/*",
        },
    )
    with urllib.request.urlopen(req, timeout=5) as response:
        data = response.read(MAX_REMOTE_BYTES + 1)

    if len(data) > MAX_REMOTE_BYTES:
        raise ValueError("Artwork too large")

    return Image.open(io.BytesIO(data))


def _cache_key(source):
    local = _local_path(source)
    if local:
        try:
            st = os.stat(local)
            raw = f"{os.path.realpath(local)}:{st.st_mtime_ns}:{st.st_size}"
        except OSError:
            raw = os.path.realpath(local)
    else:
        raw = source
    return hashlib.sha256(raw.encode("utf-8", "replace")).hexdigest()


def _load_cache():
    try:
        data = json.loads(CACHE_PATH.read_text())
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _save_cache(cache):
    try:
        CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
        if len(cache) > MAX_CACHE_ENTRIES:
            cache = dict(list(cache.items())[-MAX_CACHE_ENTRIES:])
        tmp = CACHE_PATH.with_suffix(".tmp")
        tmp.write_text(json.dumps(cache, separators=(",", ":")))
        tmp.replace(CACHE_PATH)
    except Exception:
        pass


def _hex_from_hls(h, l, s):
    r, g, b = colorsys.hls_to_rgb(h % 1.0, l, s)
    return f"#{round(r*255):02x}{round(g*255):02x}{round(b*255):02x}"


def _distance(a, b):
    return sum((x - y) ** 2 for x, y in zip(a, b)) ** 0.5


def get_artwork_palette(source):
    key = _cache_key(source)
    cache = _load_cache()
    cached = cache.get(key)
    if isinstance(cached, list) and len(cached) == 3:
        return tuple(cached)

    with _open_image(source) as raw:
        img = raw.convert("RGB")
        img.thumbnail((96, 96), Image.Resampling.LANCZOS)
        q = img.quantize(colors=12, method=Image.Quantize.MEDIANCUT)
        pal = q.getpalette()
        counts = q.getcolors(maxcolors=256) or []

    total = max(1, sum(count for count, _ in counts))
    candidates = []

    for count, idx in sorted(counts, reverse=True):
        rgb = tuple(pal[idx * 3:idx * 3 + 3])
        if len(rgb) != 3:
            continue
        r, g, b = (v / 255 for v in rgb)
        h, l, s = colorsys.rgb_to_hls(r, g, b)
        if l < 0.055 or l > 0.95:
            continue
        score = (count / total) * (0.70 + 0.55 * s)
        candidates.append((score, rgb, h, l, s))

    if not candidates:
        candidates = [(1.0, (190, 190, 190), 0.0, 0.745, 0.0)]

    candidates.sort(reverse=True, key=lambda x: x[0])
    chosen = [candidates[0]]

    for candidate in candidates[1:]:
        if all(_distance(candidate[1], current[1]) >= 52 for current in chosen):
            chosen.append(candidate)
        if len(chosen) == 3:
            break

    base_h = chosen[0][2]
    base_s = max(0.24, min(0.92, chosen[0][4] * 1.16))
    levels = (0.60, 0.69, 0.78)
    result = []

    for i, lightness in enumerate(levels):
        if i < len(chosen):
            h = chosen[i][2]
            s = max(0.24, min(0.92, chosen[i][4] * 1.16))
        else:
            h = base_h
            s = max(0.26, base_s * (1.0 - i * 0.12))
        result.append(_hex_from_hls(h, lightness, s))

    cache[key] = result
    _save_cache(cache)
    return tuple(result)


def main():
    if len(sys.argv) < 2:
        return 1

    if sys.argv[1] == "--palette":
        if len(sys.argv) < 3:
            print("#d8d8d8;#eeeeee;#ffffff")
            return 1
        try:
            print(";".join(get_artwork_palette(sys.argv[2])))
        except Exception:
            print("#d8d8d8;#eeeeee;#ffffff")
        return 0

    print(get_contrast_color(sys.argv[1]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
