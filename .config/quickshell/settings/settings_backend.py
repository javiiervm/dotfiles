#!/usr/bin/env python3
"""Transactional, one-shot editor for a small allowlist of dotfiles settings.

Usage:
  python3 settings_backend.py read
  python3 settings_backend.py apply '{"values":{...},"revisions":{"hypr":"...", ...}}'

No resident process. All writes are explicit. Only exact known scalar properties
are edited; any ambiguity, concurrent edit, or failed verification aborts.
"""
from __future__ import annotations

import fcntl
import hashlib
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
from datetime import datetime, timezone

HOME = Path.home()
HYPR = HOME / ".config/hypr/hyprland.lua"
GLASS = HOME / ".config/quickshell/Glass.qml"
THEME = HOME / ".config/quickshell/Theme.qml"
PATHS = {"hypr": HYPR, "glass": GLASS, "theme": THEME}
STATE_DIR = HOME / ".local/state/dotfiles-settings"
BACKUP_DIR = STATE_DIR / "backups"
MAX_BACKUPS = 10
# Old backend names used UTC timestamps plus random suffixes.
OLD_BACKUP_NAME = re.compile(r"\d{8}T\d{6}Z-[A-Za-z0-9_-]+\Z")
NEW_BACKUP_NAME = re.compile(r"\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.\d{6}(?:_\d{2,})?\Z")
BACKUP_FILENAMES = {"hypr": "hyprland.lua", "glass": "Glass.qml", "theme": "Theme.qml"}
# A fresh backup is not eligible for pruning until its operation has either
# succeeded or fully recovered. Unfinished recovery must keep its backup.
COMPLETED_MARKER = ".completed"


# (file, Lua table path or QML property type, property, kind, min, max)
FIELDS = {
    "hypr_blur_enabled": ("hypr", ("decoration", "blur"), "enabled", "bool", None, None),
    "hypr_blur_size": ("hypr", ("decoration", "blur"), "size", "int", 1, 12),
    "hypr_blur_passes": ("hypr", ("decoration", "blur"), "passes", "int", 1, 5),
    "hypr_active_opacity": ("hypr", ("decoration",), "active_opacity", "float", 0.35, 1),
    "hypr_inactive_opacity": ("hypr", ("decoration",), "inactive_opacity", "float", 0.35, 1),
    "hypr_rounding": ("hypr", ("decoration",), "rounding", "int", 0, 30),
    "hypr_gaps_in": ("hypr", ("general",), "gaps_in", "int", 0, 30),
    "hypr_border_size": ("hypr", ("general",), "border_size", "int", 0, 8),
    "hypr_animations": ("hypr", ("animations",), "enabled", "bool", None, None),
    "glass_tint": ("glass", "color", "tint", "color", None, None),
    "glass_opacity": ("glass", "real", "opacity", "float", 0.05, 1),
    "glass_blur": ("glass", "bool", "blurEnabled", "bool", None, None),
    "glass_border": ("glass", "real", "borderOpacity", "float", 0, 1),
    "glass_radius": ("glass", "int", "radius", "int", 0, 32),
    "theme_accent": ("theme", "color", "blue", "color", None, None),
    "theme_background": ("theme", "color", "bg0", "color", None, None),
}


def digest(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def read_originals() -> tuple[dict[str, bytes], dict[str, str]]:
    contents = {}
    for group, path in PATHS.items():
        target = path.resolve(strict=True)
        if not target.is_file() or not stat.S_ISREG(target.stat().st_mode):
            raise ValueError(f"Not a regular configuration file: {path}")
        # read_bytes avoids silently converting CRLF or rewriting unrelated lines
        contents[group] = target.read_bytes()
    return contents, {key: value.decode("utf-8") for key, value in contents.items()}


def table_range(text: str, names: tuple[str, ...]) -> tuple[int, int]:
    """Find unique Lua tables along a path; tolerate comments and quoted braces."""
    lo, hi = 0, len(text)
    for name in names:
        expression = re.compile(r"(?m)^[ \t]*" + re.escape(name) + r"[ \t]*=[ \t]*\{")
        matches = list(expression.finditer(text, lo, hi))
        if len(matches) != 1:
            raise ValueError(f"Expected one Lua table '{'.'.join(names)}' ({name}); found {len(matches)}")
        start = matches[0].end() - 1
        depth = 0
        quoted = None
        index = start
        while index < hi:
            char = text[index]
            if quoted:
                if char == "\\":
                    index += 2
                    continue
                if char == quoted:
                    quoted = None
            elif text.startswith("--", index):
                newline = text.find("\n", index)
                index = hi if newline < 0 else newline + 1
                continue
            elif char in ('"', "'"):
                quoted = char
            elif char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    lo, hi = start + 1, index
                    break
            index += 1
        else:
            raise ValueError(f"Unclosed Lua table: {name}")
    return lo, hi


def match_literal(text: str, spec: tuple):
    group, nesting, name, *_ = spec
    if group == "hypr":
        lo, hi = table_range(text, nesting)
        rx = re.compile(r"(?m)^([ \t]*" + re.escape(name) + r"[ \t]*=[ \t]*)([^,\n]+?)([ \t]*,[^\n]*)$")
        found = list(rx.finditer(text, lo, hi))
    else:
        rx = re.compile(r"(?m)^([ \t]*readonly[ \t]+property[ \t]+"
                        + re.escape(nesting) + r"[ \t]+" + re.escape(name)
                        + r"[ \t]*:[ \t]*)([^\n]*?)([ \t]*)$")
        found = list(rx.finditer(text))
    if len(found) != 1:
        raise ValueError(f"Expected one scalar property '{name}' in {group}; found {len(found)}")
    return found[0]


def decode_scalar(raw: str, kind: str):
    raw = raw.strip()
    if kind == "bool":
        if raw not in ("true", "false"):
            raise ValueError(f"Expected true/false, got {raw!r}")
        return raw == "true"
    if kind == "color":
        literal = re.fullmatch(r"['\"](#[0-9A-Fa-f]{6})['\"]", raw)
        if not literal:
            raise ValueError(f"Expected a literal #RRGGBB, got {raw!r}")
        return literal.group(1).lower()
    try:
        value = float(raw)
    except ValueError as exc:
        raise ValueError(f"Expected literal number, got {raw!r}") from exc
    if not math.isfinite(value):
        raise ValueError("Non-finite number")
    if kind == "int":
        if not value.is_integer():
            raise ValueError("Expected whole number in source")
        return int(value)
    return value


def read_values(texts: dict[str, str]) -> dict:
    values = {}
    for key, spec in FIELDS.items():
        raw = match_literal(texts[spec[0]], spec).group(2)
        try:
            values[key] = decode_scalar(raw, spec[3])
        except ValueError as exc:
            raise ValueError(f"{key}: {exc}") from exc
        if spec[4] is not None and not spec[4] <= values[key] <= spec[5]:
            raise ValueError(f"{key}: current value outside supported range")
    return values


def encode_scalar(value, spec: tuple) -> tuple[object, str]:
    _, _, _, kind, minimum, maximum = spec
    if kind == "bool":
        if type(value) is not bool:
            raise ValueError("Expected a boolean")
        return value, "true" if value else "false"
    if kind == "color":
        if not isinstance(value, str) or not re.fullmatch(r"#[0-9A-Fa-f]{6}", value):
            raise ValueError("Enter a color in #RRGGBB format")
        value = value.lower()
        return value, f'"{value}"'
    if isinstance(value, bool) or not isinstance(value, (str, int, float)):
        raise ValueError("Expected a numeric value")
    try:
        number = float(value)
    except (ValueError, OverflowError) as exc:
        raise ValueError("Enter a valid number") from exc
    if not math.isfinite(number) or not minimum <= number <= maximum:
        raise ValueError(f"Expected a value between {minimum} and {maximum}")
    if kind == "int":
        if not number.is_integer():
            raise ValueError("Enter an integer")
        return int(number), str(int(number))
    number = round(number, 3)
    return number, f"{number:.3f}".rstrip("0").rstrip(".")


def substitute(text: str, spec: tuple, value: str) -> str:
    matched = match_literal(text, spec)
    return text[:matched.start(2)] + value + text[matched.end(2):]


def qml_property(text: str, typ: str, name: str):
    match = match_literal(text, ("qml", typ, name, "", None, None))
    expression = match.group(2).strip()
    if typ in ("color", "string"):
        m = re.fullmatch(r"['\"]([^'\"]+)['\"]", expression)
        if not m:
            raise ValueError(f"Unsupported theme literal: {name}")
        if typ == "color" and not re.fullmatch(r"#[0-9A-Fa-f]{6}", m.group(1)):
            raise ValueError(f"Invalid theme color: {name}")
        return m.group(1)
    return decode_scalar(expression, "bool" if typ == "bool" else ("int" if typ == "int" else "float"))


def read_appearance(texts: dict[str, str]) -> dict:
    # Retained for the old standalone read consumer; integrated panel uses Theme/Glass directly.
    theme_props = {"white": "color", "bg0": "color", "blue": "color", "red": "color", "yellow": "color",
                   "grey1": "color", "fontMain": "string", "fontIcons": "string"}
    glass_props = {"tint": "color", "opacity": "real", "blurEnabled": "bool", "borderOpacity": "real",
                   "borderWidth": "real", "highlightOpacity": "real", "radius": "int", "radiusSmall": "int",
                   "radiusLarge": "int"}
    return {"theme": {name: qml_property(texts["theme"], kind, name) for name, kind in theme_props.items()},
            "glass": {name: qml_property(texts["glass"], kind, name) for name, kind in glass_props.items()}}


def snapshot():
    raw, texts = read_originals()
    return raw, texts, {group: digest(data) for group, data in raw.items()}


def read():
    raw, texts, revisions = snapshot()
    return {"ok": True, "values": read_values(texts), "revisions": revisions,
            "appearance": read_appearance(texts)}


def make_state_dir():
    STATE_DIR.mkdir(parents=True, exist_ok=True, mode=0o700)
    BACKUP_DIR.mkdir(parents=True, exist_ok=True, mode=0o700)


def sync_folder(folder: Path):
    fd = os.open(folder, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def atomic_write(path: Path, data: bytes, mode: int):
    """Preserve symlinks at the configured path, replacing the linked target."""
    target = path.resolve(strict=True)
    fd, name = tempfile.mkstemp(prefix=".dotfiles-settings-", dir=target.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            os.fchmod(stream.fileno(), mode)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, target)
        sync_folder(target.parent)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def new_backup_folder() -> Path:
    """Create a collision-safe directory named in the user's local date/time."""
    stamp = datetime.now().astimezone().strftime("%Y-%m-%d_%H-%M-%S.%f")
    for attempt in range(1, 10000):
        name = stamp if attempt == 1 else f"{stamp}_{attempt:02d}"
        folder = BACKUP_DIR / name
        try:
            folder.mkdir(mode=0o700)
            return folder
        except FileExistsError:
            continue
    raise OSError("Too many backup folders created within the same second")


def write_backups(changed: list[str], raw: dict[str, bytes], modes: dict[str, int]) -> Path:
    make_state_dir()
    txn = new_backup_folder()
    try:
        manifest = {}
        for group in changed:
            original = raw[group]
            out = txn / BACKUP_FILENAMES[group]
            fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "wb") as stream:
                stream.write(original)
                stream.flush()
                os.fsync(stream.fileno())
            manifest[group] = {"config": str(PATHS[group]), "sha256": digest(original),
                               "mode": oct(modes[group]), "backup": out.name}
        manifest_path = txn / "manifest.json"
        fd = os.open(manifest_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "wb") as stream:
            stream.write((json.dumps(manifest, indent=2) + "\n").encode("utf-8"))
            stream.flush()
            os.fsync(stream.fileno())
        sync_folder(txn)
        sync_folder(BACKUP_DIR)
        return txn
    except Exception:
        # No config file has been changed yet: remove a partial backup here.
        shutil.rmtree(txn)
        raise


def finish_backup(backup: Path):
    """Mark backup safe for retention cleanup, only AFTER a safe outcome."""
    marker = backup / COMPLETED_MARKER
    fd = os.open(marker, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as stream:
        stream.write(b"The save completed or the original files were restored.\n")
        stream.flush()
        os.fsync(stream.fileno())
    sync_folder(backup)


def completed_backup(path: Path) -> bool:
    """Only delete backups we can positively identify as ours and intact."""
    if (not path.is_dir() or path.is_symlink() or
            not (OLD_BACKUP_NAME.fullmatch(path.name) or NEW_BACKUP_NAME.fullmatch(path.name))):
        return False
    # Old folders are compatible without a marker. New folders without it may
    # be needed for recovery, so they are deliberately never pruned.
    old_format = bool(OLD_BACKUP_NAME.fullmatch(path.name))
    if not old_format and not (path / COMPLETED_MARKER).is_file():
        return False
    try:
        backup_date_sort_key(path)  # Malformed timestamp must never break Apply.
        entries = list(path.iterdir())
        if any(e.is_symlink() or not e.is_file() for e in entries):
            return False
        names = {entry.name for entry in entries}
        manifest_path = path / "manifest.json"
        info = json.loads(manifest_path.read_text(encoding="utf-8"))
        if not isinstance(info, dict) or not info or not set(info).issubset(BACKUP_FILENAMES):
            return False
        expected = {"manifest.json"}
        if not old_format:
            expected.add(COMPLETED_MARKER)
        for group, record in info.items():
            if not isinstance(record, dict) or record.get("backup") != BACKUP_FILENAMES[group]:
                return False
            fingerprint = record.get("sha256")
            if not isinstance(fingerprint, str) or not re.fullmatch(r"[a-f0-9]{64}", fingerprint):
                return False
            original = path / BACKUP_FILENAMES[group]
            if digest(original.read_bytes()) != fingerprint:
                return False
            expected.add(original.name)
        return names == expected
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return False


def backup_date_sort_key(path: Path) -> tuple[float, int, str]:
    """Sort by the backup's timestamp, including same-second suffixes.

    Legacy timestamps are UTC (Z); new human-readable ones are local time.
    This avoids depending on folder mtimes, which can change after copying.
    """
    name = path.name
    if OLD_BACKUP_NAME.fullmatch(name):
        stamp = datetime.strptime(name[:16], "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc)
        sequence = 1
    else:
        stamp = datetime.strptime(name[:26], "%Y-%m-%d_%H-%M-%S.%f").astimezone()
        suffix = name[26:]
        sequence = int(suffix[1:]) if suffix else 1
    return (stamp.timestamp(), sequence, name)


def prune_backups(current: Path) -> int:
    """Keep the newest ten *completed and intact* managed backup folders.

    Never discard the just-written backup. Unknown, damaged or unfinished
    backups are left alone, even if that means briefly exceeding the limit:
    protecting a recovery copy is more important than disk cleanup.
    """
    folders = [p for p in BACKUP_DIR.iterdir() if completed_backup(p)]
    folders.sort(key=backup_date_sort_key, reverse=True)
    to_keep = {current}
    for folder in folders:
        if len(to_keep) >= MAX_BACKUPS:
            break
        to_keep.add(folder)
    removed = 0
    for folder in folders:
        if folder not in to_keep:
            # Recheck immediately before deletion in case anything changed.
            if not completed_backup(folder):
                continue
            shutil.rmtree(folder)
            removed += 1
    if removed:
        sync_folder(BACKUP_DIR)
    return removed


def finalize_retention(backup: Path) -> str:
    """Retention failure must not undo an otherwise valid configuration save."""
    try:
        finish_backup(backup)
        removed = prune_backups(backup)
        return f"Removed {removed} old backup(s)." if removed else ""
    except Exception as exc:
        # Cleanup is secondary to a successfully committed configuration.
        # The panel should show the warning, not incorrectly report Apply failed.
        return f"Backup cleanup could not complete: {exc}. Backup preserved: {backup}"


def reload_hyprland():
    try:
        proc = subprocess.run(["hyprctl", "reload"], text=True, capture_output=True,
                              timeout=12, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise RuntimeError(f"Hyprland reload could not complete: {exc}") from exc
    if proc.returncode != 0:
        raise RuntimeError("Hyprland reload failed: " + (proc.stderr.strip() or proc.stdout.strip())[:250])


def apply(payload):
    if (not isinstance(payload, dict) or set(payload) != {"values", "revisions"}
            or not isinstance(payload["values"], dict) or not isinstance(payload["revisions"], dict)
            or set(payload["values"]) != set(FIELDS) or set(payload["revisions"]) != set(PATHS)):
        raise ValueError("Invalid request. Reopen Settings to load a fresh configuration.")
    if any(not isinstance(h, str) or not re.fullmatch(r"[a-f0-9]{64}", h)
           for h in payload["revisions"].values()):
        raise ValueError("Invalid configuration revision. Reopen Settings.")

    # An advisory lock prevents two concurrent *Settings* writes. No daemon.
    make_state_dir()
    lock_path = STATE_DIR / "apply.lock"
    descriptor = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
    with os.fdopen(descriptor, "rb") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        raw, original_texts, original_hashes = snapshot()
        if payload["revisions"] != original_hashes:
            raise ValueError("The configuration changed outside Settings. No files were modified; reopen Settings to refresh.")
        originals = read_values(original_texts)
        requested, rendered = {}, {}
        for key, spec in FIELDS.items():
            try:
                requested[key], rendered[key] = encode_scalar(payload["values"][key], spec)
            except ValueError as exc:
                raise ValueError(f"{key}: {exc}") from exc

        modified = original_texts.copy()
        for key, spec in FIELDS.items():
            if requested[key] != originals[key]:
                modified[spec[0]] = substitute(modified[spec[0]], spec, rendered[key])
        changed = [group for group in PATHS if modified[group] != original_texts[group]]
        if not changed:
            return {"ok": True, "changed": [], "values": originals, "revisions": original_hashes,
                    "warning": "No changes were necessary."}
        # Full preflight, including every result's value, before writing anything.
        verified_values = read_values(modified)
        if any(verified_values[key] != requested[key] for key in FIELDS):
            raise ValueError("Internal verification failed before writing; no changes were made.")
        output = {group: modified[group].encode("utf-8") for group in changed}
        modes = {group: stat.S_IMODE(PATHS[group].resolve(strict=True).stat().st_mode) for group in changed}
        backup = write_backups(changed, raw, modes)
        written = []
        rollback_errors = []
        try:
            for group in changed:
                path = PATHS[group]
                if digest(path.resolve(strict=True).read_bytes()) != original_hashes[group]:
                    raise RuntimeError(f"{path.name} changed during Apply")
                # Record this group before replace; restores even if fsync raises after replace.
                written.append(group)
                atomic_write(path, output[group], modes[group])
                if path.resolve(strict=True).read_bytes() != output[group]:
                    raise RuntimeError(f"Verification failed for {path.name}")
            post_raw, post_texts, post_hashes = snapshot()
            if any(post_raw[group] != output[group] for group in changed):
                raise RuntimeError("Post-write byte verification failed")
            if read_values(post_texts) != verified_values:
                raise RuntimeError("Post-write value verification failed")
            if "hypr" in changed:
                reload_hyprland()
        except Exception as exc:
            for group in reversed(written):
                try:
                    path = PATHS[group]
                    current = path.resolve(strict=True).read_bytes()
                    # Refuse to overwrite changes performed outside Settings after our write.
                    if current not in (output[group], raw[group]):
                        raise RuntimeError("file changed during rollback; manual recovery required")
                    if current != raw[group]:
                        atomic_write(path, raw[group], modes[group])
                    if path.resolve(strict=True).read_bytes() != raw[group]:
                        raise RuntimeError("restored file does not match the backup")
                except Exception as rollback_exc:
                    rollback_errors.append(f"{PATHS[group].name}: {rollback_exc}")
            if "hypr" in written and "hypr" not in {s.split(":")[0] for s in rollback_errors}:
                try:
                    reload_hyprland()
                except Exception as reload_exc:
                    rollback_errors.append(f"Hyprland restore reload: {reload_exc}")
            if rollback_errors:
                # Leave the backup unfinished, so retention NEVER deletes it.
                raise RuntimeError(f"Apply failed ({exc}). Automatic recovery INCOMPLETE: "
                                   f"{' / '.join(rollback_errors)}. Restore from {backup}") from exc
            finalize_retention(backup)  # All original bytes have been restored.
            raise RuntimeError(f"Apply failed ({exc}); original files restored. Backup: {backup}") from exc

        # The writes and any required Hyprland reload finished successfully.
        # Retention is deliberately AFTER the transaction, so an unsuccessful
        # Apply can never destroy old backups before a safe replacement exists.
        retention_note = finalize_retention(backup)
        warning = "Quickshell may reload when its theme QML files change." if any(
            group in changed for group in ("glass", "theme")) else ""
        if retention_note and retention_note.startswith("Backup cleanup"):
            warning = (warning + " " + retention_note).strip()
        return {"ok": True, "changed": changed, "values": verified_values,
                "revisions": post_hashes, "backup": str(backup), "warning": warning}


def main():
    try:
        if len(sys.argv) == 2 and sys.argv[1] == "read":
            result = read()
        elif len(sys.argv) == 3 and sys.argv[1] == "apply":
            result = apply(json.loads(sys.argv[2]))
        else:
            raise ValueError("Usage: settings_backend.py read | apply '<json>'")
        print(json.dumps(result, separators=(",", ":")), flush=True)
        return 0
    except (OSError, ValueError, RuntimeError, KeyError, json.JSONDecodeError) as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, separators=(",", ":")), flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
