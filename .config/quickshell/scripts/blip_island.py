#!/usr/bin/env python3
"""On-demand local Blip adapter for the Quickshell Dynamic Island.

Uses Blip's current local state format and the --peer/--file CLI observed
on Blip 1.2.3 for Linux. Both are undocumented implementation details.
No credentials or raw state bytes are printed or stored by this adapter.
"""

import argparse
import base64
import json
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote, urlsplit

STATE_PATH = Path.home() / ".local/share/net.blip.Blip/state.dat"
JWT_PATTERN = re.compile(rb"eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+")
DEVICE_PATTERN = re.compile(
    rb"\x0a\x24([0-9a-fA-F-]{36})\x10([\x00-\x7f])\x1a([\x00-\x7f])"
)
UUID_PATTERN = re.compile(r"[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}\Z")


class BlipError(Exception):
    pass


def respond(**payload):
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), flush=True)


def read_state():
    try:
        return STATE_PATH.read_bytes()
    except OSError as exc:
        raise BlipError("Blip state is unavailable. Open Blip and sign in.") from exc


def local_identity(data):
    for match in JWT_PATTERN.finditer(data):
        try:
            segment = match.group().split(b".")[1]
            segment += b"=" * (-len(segment) % 4)
            claims = json.loads(base64.urlsafe_b64decode(segment))
            user_id = claims.get("user_id")
            device_id = claims.get("device_id")
            if (
                isinstance(user_id, str)
                and user_id
                and isinstance(device_id, str)
                and UUID_PATTERN.fullmatch(device_id)
            ):
                return user_id, device_id.lower()
        except (ValueError, UnicodeError, TypeError, KeyError):
            continue
    raise BlipError("Blip account information could not be read.")


def remote_devices(data, own_id):
    devices = {}
    for match in DEVICE_PATTERN.finditer(data):
        device_id = match.group(1).decode("ascii").lower()
        size = match.group(3)[0]
        if device_id == own_id or not 1 <= size <= 80:
            continue
        try:
            name = data[match.end():match.end() + size].decode("utf-8")
        except UnicodeDecodeError:
            continue
        if not name.strip() or not name.isprintable():
            continue
        devices[device_id] = {"id": device_id, "name": name.strip()}
    return sorted(devices.values(), key=lambda d: d["name"].casefold())


def resolve_local_file(value):
    parts = urlsplit(value)
    if parts.scheme:
        if parts.scheme != "file" or parts.netloc not in ("", "localhost"):
            raise BlipError("Only local file URLs are supported.")
        candidate = Path(unquote(parts.path))
    else:
        candidate = Path(value)
    try:
        path = candidate.expanduser().resolve(strict=True)
    except (OSError, RuntimeError) as exc:
        raise BlipError("The selected file no longer exists.") from exc
    if not path.is_file():
        raise BlipError("Select regular files, not folders.")
    return path


def list_devices():
    data = read_state()
    _, own_id = local_identity(data)
    respond(ok=True, devices=remote_devices(data, own_id))


def send_files(device_id, file_urls):
    if not UUID_PATTERN.fullmatch(device_id):
        raise BlipError("Invalid destination device.")
    if not file_urls:
        raise BlipError("Select at least one file.")

    data = read_state()
    user_id, own_id = local_identity(data)
    devices = remote_devices(data, own_id)
    target = next((d for d in devices if d["id"] == device_id.lower()), None)
    if target is None:
        raise BlipError("Destination device is no longer in Blip's local state.")

    # Validate every file before starting any transfer to avoid predictable
    # partial batches when one of the dropped paths no longer exists.
    paths = [resolve_local_file(file_url) for file_url in file_urls]
    total = len(paths)
    for index, file_path in enumerate(paths, start=1):
        try:
            result = subprocess.run(
                ["blip", f"--peer={user_id}:{target['id']}", f"--file={file_path}"],
                capture_output=True,
                timeout=25,
                check=False,
            )
        except FileNotFoundError as exc:
            raise BlipError("Blip is not installed or is missing from PATH.") from exc
        except subprocess.TimeoutExpired as exc:
            raise BlipError(
                f"Blip did not respond for file {index}/{total}; "
                f"{index - 1} request(s) were sent."
            ) from exc
        if result.returncode != 0:
            raise BlipError(
                f"Blip rejected file {index}/{total}; "
                f"{index - 1} request(s) were sent."
            )
        respond(ok=True, status="progress", completed=index, total=total)

    respond(ok=True, status="dispatched", device=target["name"], count=total)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("list", help="List device records cached by Blip")
    send = sub.add_parser("send", help="Request one or more file transfers")
    send.add_argument("device_id", help="Target device UUID")
    send.add_argument("file_urls", nargs="+", help="Local file paths or file:// URLs")
    args = parser.parse_args()
    try:
        if args.action == "list":
            list_devices()
        else:
            send_files(args.device_id, args.file_urls)
    except BlipError as exc:
        respond(ok=False, error=str(exc))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
