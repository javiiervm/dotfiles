#!/usr/bin/env python3
"""Event-driven Hyprland application usage tracker.

Tracks focus changes immediately in memory and batches JSON writes to limit
background disk activity. The output schemas are unchanged for DynamicIsland.
"""

import json
import os
import signal
import socket
import subprocess
import time
from datetime import datetime, timedelta, time as midnight_time

CACHE_DIR = os.path.expanduser("~/.cache")
OUT_FILE = os.path.join(CACHE_DIR, "qs_app_usage.json")
HISTORY_FILE = os.path.join(CACHE_DIR, "qs_app_usage_history.json")
FLUSH_INTERVAL_SECONDS = 30

SIG = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
SOCK_PATH = f"/run/user/{os.getuid()}/hypr/{SIG}/.socket2.sock"

app_usage = {}
history_data = {}
active_app = None
last_time = time.time()
current_day = datetime.fromtimestamp(last_time).date()
dirty = False


def format_time(seconds):
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    if h > 0:
        return f"{h}h {m}m"
    return f"{m}m"


def load_history():
    """Recover the same per-day app data and totals as the previous daemon."""
    global history_data, app_usage
    if os.path.exists(HISTORY_FILE):
        try:
            with open(HISTORY_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            history_data = data.get("days", {})
            today_str = current_day.isoformat()
            if today_str in data.get("apps", {}):
                app_usage = data["apps"][today_str]
        except (OSError, ValueError, TypeError):
            pass


def get_initial_window():
    try:
        out = subprocess.check_output(
            ["hyprctl", "activewindow", "-j"], stderr=subprocess.DEVNULL
        )
        return json.loads(out).get("class", "none")
    except (OSError, subprocess.CalledProcessError, ValueError):
        return "none"


def save_data():
    """Write both existing JSON formats. Called on a schedule, not per focus."""
    global dirty
    today_total_sec = sum(app_usage.values())
    today_str = current_day.isoformat()

    yesterday = (current_day - timedelta(days=1)).isoformat()
    y_sec = history_data.get(yesterday, 0)
    diff = today_total_sec - y_sec
    vs_yesterday = (
        f"↑ {format_time(diff)}"
        if diff >= 0
        else f"↓ {format_time(abs(diff))}"
    )

    all_secs = list(history_data.values())
    avg_sec = (sum(all_secs) / len(all_secs)) if all_secs else today_total_sec

    week_secs = []
    week_times = []
    for i in range(6, -1, -1):
        d = current_day - timedelta(days=i)
        sec = today_total_sec if d == current_day else history_data.get(d.isoformat(), 0)
        week_secs.append(sec)
        week_times.append(format_time(sec))

    max_week_sec = max(week_secs) if max(week_secs) > 0 else 1
    chart_data = [round(s / max_week_sec, 3) for s in week_secs]

    apps_list = []
    for app, sec in sorted(app_usage.items(), key=lambda x: x[1], reverse=True)[:5]:
        if sec < 1:
            continue
        percent = sec / today_total_sec if today_total_sec > 0 else 0
        apps_list.append({
            "name": app.capitalize(),
            "time": format_time(sec),
            "icon": app.lower(),
            "percent": round(percent, 3),
        })

    data_out = {
        "total": format_time(today_total_sec),
        "avg_daily": format_time(avg_sec),
        "vs_yesterday": vs_yesterday,
        "chart": chart_data,
        "chart_times": week_times,
        "current_day_index": 6,
        "apps": apps_list,
    }

    os.makedirs(CACHE_DIR, exist_ok=True)
    with open(OUT_FILE, "w", encoding="utf-8") as f:
        json.dump(data_out, f)

    history_data[today_str] = today_total_sec
    with open(HISTORY_FILE, "w", encoding="utf-8") as f:
        json.dump({"days": history_data, "apps": {today_str: app_usage}}, f)

    dirty = False


def _add_elapsed(seconds):
    """Add only real elapsed time; an empty desktop does not count as an app."""
    global dirty
    if seconds > 0 and active_app and active_app != "none":
        app_usage[active_app] = app_usage.get(active_app, 0) + seconds
        dirty = True


def advance_usage(until):
    """Charge elapsed time to the correct day, including at midnight."""
    global last_time, current_day, app_usage, dirty
    if until < last_time:
        # Wall clock adjustments must not subtract time from any application.
        last_time = until
        return

    target_day = datetime.fromtimestamp(until).date()
    while current_day < target_day:
        next_day = current_day + timedelta(days=1)
        midnight = datetime.combine(next_day, midnight_time.min).timestamp()
        _add_elapsed(max(0, midnight - last_time))
        last_time = midnight
        # Save the day being closed, so a midnight rollover cannot lose it.
        save_data()
        app_usage = {}
        current_day = next_day
        dirty = True  # Ensure the new day's summary is written as well.

    _add_elapsed(until - last_time)
    last_time = until


def _terminate(_signal, _frame):
    # The finally block in main() flushes usage before terminating cleanly.
    raise KeyboardInterrupt


def main():
    global active_app
    load_history()
    active_app = get_initial_window()
    save_data()  # Initial state, just as in the original version.

    signal.signal(signal.SIGTERM, _terminate)
    signal.signal(signal.SIGINT, _terminate)

    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        client.connect(SOCK_PATH)
        buffer = ""
        next_flush = time.monotonic() + FLUSH_INTERVAL_SECONDS

        while True:
            # Wake at most once per 30 s without launching a polling process.
            client.settimeout(max(0.01, next_flush - time.monotonic()))
            try:
                data = client.recv(4096)
            except socket.timeout:
                data = None

            if data is not None:
                if not data:
                    break
                buffer += data.decode("utf-8", errors="replace")
                # socket2 can send several events, or split one across reads.
                while "\n" in buffer:
                    line, buffer = buffer.split("\n", 1)
                    if line.startswith("activewindow>>"):
                        app_class = line[len("activewindow>>"):].split(",", 1)[0].strip()
                        advance_usage(time.time())
                        active_app = app_class or "none"

            if time.monotonic() >= next_flush:
                advance_usage(time.time())
                if dirty:
                    save_data()
                next_flush = time.monotonic() + FLUSH_INTERVAL_SECONDS
    except KeyboardInterrupt:
        pass
    finally:
        advance_usage(time.time())
        if dirty:
            save_data()
        client.close()


if __name__ == "__main__":
    main()
