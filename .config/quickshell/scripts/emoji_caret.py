#!/usr/bin/env python3
"""
One-shot anchor probe for the Quickshell emoji picker.

Priority:
  1. Real text insertion caret via AT-SPI, when the focused app exposes it.
  2. Bottom-right area of the currently focused Hyprland window.
  3. Failure (QML uses its own screen-corner fallback).

It never queries the mouse pointer and prints exactly one JSON object.
"""

from __future__ import annotations

import json
import subprocess
from collections import deque


def emit(payload: dict) -> None:
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), flush=True)


def active_window_anchor() -> dict | None:
    try:
        proc = subprocess.run(
            ["hyprctl", "-j", "activewindow"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=0.8,
        )
        data = json.loads(proc.stdout or "{}")
    except Exception:
        return None

    at = data.get("at")
    size = data.get("size")

    if (
        not isinstance(at, list)
        or len(at) < 2
        or not isinstance(size, list)
        or len(size) < 2
    ):
        return None

    try:
        x = float(at[0])
        y = float(at[1])
        width = float(size[0])
        height = float(size[1])
    except (TypeError, ValueError):
        return None

    if width <= 0 or height <= 0:
        return None

    # Return the complete active-window rectangle. QML will place the picker
    # inside this rectangle, preventing a tiled neighbour from sitting between
    # the original text field and the picker.
    return {
        "ok": True,
        "kind": "window",
        "x": round(x),
        "y": round(y),
        "width": round(width),
        "height": round(height),
        "class": data.get("class", ""),
        "title": data.get("title", ""),
    }


def try_caret_anchor() -> dict | None:
    try:
        import gi

        gi.require_version("Atspi", "2.0")
        from gi.repository import Atspi
    except Exception:
        return None

    def safe(call, default=None):
        try:
            return call()
        except Exception:
            return default

    def has_state(obj, state) -> bool:
        states = safe(lambda: obj.get_state_set())
        return bool(states and safe(lambda: states.contains(state), False))

    def valid_rect(rect) -> bool:
        return (
            rect is not None
            and isinstance(rect.x, int)
            and isinstance(rect.y, int)
            and isinstance(rect.width, int)
            and isinstance(rect.height, int)
            and rect.x >= 0
            and rect.y >= 0
        )

    desktop = safe(lambda: Atspi.get_desktop(0))
    if desktop is None:
        return None

    queue = deque([desktop])
    text_candidate = None
    visited = 0

    # The focused object is normally found quickly; the cap prevents a broken
    # accessibility tree from turning the shortcut into a long operation.
    while queue and visited < 12000:
        obj = queue.popleft()
        visited += 1

        if has_state(obj, Atspi.StateType.FOCUSED):
            text_iface = safe(lambda: obj.get_text_iface())

            if text_iface is not None:
                if has_state(obj, Atspi.StateType.EDITABLE):
                    text_candidate = (obj, text_iface)
                    break

                if text_candidate is None:
                    text_candidate = (obj, text_iface)

        count = int(safe(lambda: obj.get_child_count(), 0) or 0)

        for index in range(max(0, count)):
            child = safe(lambda i=index: obj.get_child_at_index(i))
            if child is not None:
                queue.append(child)

    if text_candidate is None:
        return None

    obj, text_iface = text_candidate
    offset = safe(lambda: text_iface.get_caret_offset(), -1)
    count = safe(lambda: text_iface.get_character_count(), -1)

    try:
        offset = int(offset)
        count = int(count)
    except (TypeError, ValueError):
        return None

    rect = None
    caret_x = None

    if count > 0 and 0 <= offset < count:
        rect = safe(
            lambda: text_iface.get_character_extents(
                offset, Atspi.CoordType.SCREEN
            )
        )
        if valid_rect(rect) and rect.height > 0:
            caret_x = rect.x

    elif count > 0 and offset >= count:
        previous = count - 1
        rect = safe(
            lambda: text_iface.get_character_extents(
                previous, Atspi.CoordType.SCREEN
            )
        )
        if valid_rect(rect) and rect.height > 0:
            caret_x = rect.x + max(1, rect.width)

    if rect is not None and caret_x is not None:
        return {
            "ok": True,
            "kind": "caret",
            "x": int(caret_x),
            "y": int(rect.y),
            "height": max(1, int(rect.height)),
        }

    # Empty editable widgets often have no character extents. Approximate the
    # caret from the focused control itself.
    component = safe(lambda: obj.get_component_iface())

    if component is not None:
        bounds = safe(lambda: component.get_extents(Atspi.CoordType.SCREEN))

        if valid_rect(bounds) and bounds.width > 0 and bounds.height > 0:
            line_height = max(14, min(28, int(bounds.height) - 8))
            return {
                "ok": True,
                "kind": "caret-approx",
                "x": int(bounds.x + 6),
                "y": int(bounds.y + max(3, (bounds.height - line_height) // 2)),
                "height": line_height,
            }

    return None


def main() -> None:
    caret = try_caret_anchor()
    if caret is not None:
        emit(caret)
        return

    window = active_window_anchor()
    if window is not None:
        emit(window)
        return

    emit({"ok": False, "reason": "no-caret-or-active-window"})


if __name__ == "__main__":
    main()
