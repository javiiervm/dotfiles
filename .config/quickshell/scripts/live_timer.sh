#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/qs-live-timer"
STATE_FILE="$STATE_DIR/state.env"
EVENT_FIFO="${XDG_RUNTIME_DIR:-/tmp}/qs-live-timer-events"
SCRIPT_PATH="$HOME/.config/quickshell/scripts/live_timer.sh"
mkdir -p "$STATE_DIR"

STATUS="idle"
TOTAL=0
REMAINING=0
DEADLINE=0
WATCHER_PID=""
TOKEN=""
LABEL="Timer"
DND_REQUESTED=0
DND_CHANGED_BY_TIMER=0
DND_STATE_FILE="/tmp/qs_dnd_state"
DND_FIFO="/tmp/qs_notif_cmd"

load_state() {
    STATUS="idle"
    TOTAL=0
    REMAINING=0
    DEADLINE=0
    WATCHER_PID=""
    TOKEN=""
    LABEL="Timer"
    DND_REQUESTED=0
    DND_CHANGED_BY_TIMER=0
    if [[ -f "$STATE_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$STATE_FILE"
    fi
    return 0
}

save_state() {
    local tmp="$STATE_FILE.tmp"
    {
        printf 'STATUS=%q\n' "$STATUS"
        printf 'TOTAL=%q\n' "$TOTAL"
        printf 'REMAINING=%q\n' "$REMAINING"
        printf 'DEADLINE=%q\n' "$DEADLINE"
        printf 'WATCHER_PID=%q\n' "$WATCHER_PID"
        printf 'TOKEN=%q\n' "$TOKEN"
        printf 'LABEL=%q\n' "$LABEL"
        printf 'DND_REQUESTED=%q\n' "$DND_REQUESTED"
        printf 'DND_CHANGED_BY_TIMER=%q\n' "$DND_CHANGED_BY_TIMER"
    } > "$tmp"
    mv "$tmp" "$STATE_FILE"
}

emit_refresh() {
    [[ -p "$EVENT_FIFO" ]] || return 0
    timeout 0.15 bash -c 'printf "refresh\n" > "$1"' _ "$EVENT_FIFO" 2>/dev/null || true
}


play_finished_alarm() {
    # Versioned filename intentionally forces regeneration after alarm tuning.
    local alarm_file="$STATE_DIR/timer-finished-v2.wav"

    # Three quick "pip-pip" pairs. Higher pitch and stronger level than the
    # previous gentle tone, but still short enough to avoid becoming annoying.
    if [[ ! -s "$alarm_file" ]]; then
        python3 - "$alarm_file" <<'PYALARM' >/dev/null 2>&1 || return 0
import math
import struct
import sys
import wave

path = sys.argv[1]
rate = 44100
frequency = 1450.0
amplitude = 0.52
beep_seconds = 0.085
intra_pair_gap_seconds = 0.070
inter_pair_gap_seconds = 0.260
fade_seconds = 0.008

beep_n = int(rate * beep_seconds)
intra_gap_n = int(rate * intra_pair_gap_seconds)
inter_gap_n = int(rate * inter_pair_gap_seconds)
fade_n = max(1, int(rate * fade_seconds))
frames = []
zero = struct.pack('<h', 0)

def add_silence(count):
    frames.extend([zero] * count)

def add_beep():
    for i in range(beep_n):
        env = 1.0
        if i < fade_n:
            env = i / fade_n
        elif i >= beep_n - fade_n:
            env = (beep_n - 1 - i) / fade_n
        env = max(0.0, min(1.0, env))

        # A small second harmonic makes the pip read more like an alarm tone
        # without making it harsh.
        phase = 2.0 * math.pi * frequency * i / rate
        sample = math.sin(phase) + 0.18 * math.sin(2.0 * phase)
        sample /= 1.18
        value = int(32767 * amplitude * env * sample)
        frames.append(struct.pack('<h', value))

for pair in range(3):
    add_beep()
    add_silence(intra_gap_n)
    add_beep()
    if pair < 2:
        add_silence(inter_gap_n)

with wave.open(path, 'wb') as wav:
    wav.setnchannels(1)
    wav.setsampwidth(2)
    wav.setframerate(rate)
    wav.writeframes(b''.join(frames))
PYALARM
    fi

    if command -v paplay >/dev/null 2>&1 && [[ -s "$alarm_file" ]]; then
        paplay "$alarm_file" >/dev/null 2>&1 &
    fi
}

get_dnd_state() {
    local value="0"
    if [[ -r "$DND_STATE_FILE" ]]; then
        read -r value < "$DND_STATE_FILE" || value="0"
    fi
    [[ "$value" == "1" ]] && printf '1' || printf '0'
}

send_dnd_command() {
    local command="$1"
    [[ -p "$DND_FIFO" ]] || return 0
    timeout 0.20 bash -c 'printf "%s\n" "$1" > "$2"' _ "$command" "$DND_FIFO" 2>/dev/null || true
}

restore_timer_dnd() {
    if [[ "${DND_CHANGED_BY_TIMER:-0}" == "1" ]]; then
        send_dnd_command "DND_OFF"
    fi
    DND_REQUESTED=0
    DND_CHANGED_BY_TIMER=0
}

kill_watcher() {
    if [[ -n "${WATCHER_PID:-}" ]] && kill -0 "$WATCHER_PID" 2>/dev/null; then
        kill "$WATCHER_PID" 2>/dev/null || true
    fi
    WATCHER_PID=""
}

current_remaining() {
    local now
    now=$(date +%s)
    if [[ "$STATUS" == "running" ]]; then
        local value=$(( DEADLINE - now ))
        (( value < 0 )) && value=0
        printf '%s' "$value"
    else
        printf '%s' "$REMAINING"
    fi
}

spawn_watcher() {
    local seconds="$1"
    local token="$2"
    nohup bash -c 'sleep "$1"; exec "$2" expire "$3"' _ "$seconds" "$SCRIPT_PATH" "$token" \
        >/dev/null 2>&1 &
    WATCHER_PID=$!
}

json_status() {
    load_state
    local remaining
    remaining=$(current_remaining)
    printf '{"status":"%s","total":%s,"remaining":%s,"label":"%s"}\n' \
        "$STATUS" "$TOTAL" "$remaining" "$LABEL"
}

cmd="${1:-status}"
case "$cmd" in
    status)
        json_status
        ;;

    start)
        seconds="${2:-0}"
        label="${3:-Focus}"
        dnd_requested="${4:-0}"
        [[ "$seconds" =~ ^[0-9]+$ ]] || exit 2
        (( seconds > 0 )) || exit 2
        load_state
        # Starting a new timer replaces any previous one and first restores
        # DND if that previous timer had enabled it.
        restore_timer_dnd
        kill_watcher
        STATUS="running"
        TOTAL="$seconds"
        REMAINING="$seconds"
        DEADLINE=$(( $(date +%s) + seconds ))
        TOKEN="$(date +%s%N)-$$"
        LABEL="$label"
        DND_REQUESTED=0
        DND_CHANGED_BY_TIMER=0
        if [[ "$dnd_requested" == "1" || "$dnd_requested" == "true" || "$dnd_requested" == "dnd" ]]; then
            DND_REQUESTED=1
            if [[ "$(get_dnd_state)" != "1" ]]; then
                send_dnd_command "DND_ON"
                DND_CHANGED_BY_TIMER=1
            fi
        fi
        spawn_watcher "$seconds" "$TOKEN"
        save_state
        emit_refresh
        ;;

    pause)
        load_state
        [[ "$STATUS" == "running" ]] || exit 0
        REMAINING=$(current_remaining)
        kill_watcher
        STATUS="paused"
        DEADLINE=0
        save_state
        emit_refresh
        ;;

    resume)
        load_state
        [[ "$STATUS" == "paused" ]] || exit 0
        (( REMAINING > 0 )) || exit 0
        STATUS="running"
        DEADLINE=$(( $(date +%s) + REMAINING ))
        TOKEN="$(date +%s%N)-$$"
        spawn_watcher "$REMAINING" "$TOKEN"
        save_state
        emit_refresh
        ;;

    cancel)
        load_state
        kill_watcher
        restore_timer_dnd
        STATUS="idle"
        TOTAL=0
        REMAINING=0
        DEADLINE=0
        TOKEN=""
        LABEL="Timer"
        save_state
        emit_refresh
        ;;

    expire)
        wanted="${2:-}"
        load_state
        [[ "$STATUS" == "running" && "$TOKEN" == "$wanted" ]] || exit 0
        restore_timer_dnd
        STATUS="finished"
        REMAINING=0
        DEADLINE=0
        WATCHER_PID=""
        save_state
        emit_refresh
        play_finished_alarm
        ;;

    clear)
        load_state
        kill_watcher
        # Normally expiry/cancel already restored DND. This also makes clear
        # safe if called directly while a timer still owns DND.
        restore_timer_dnd
        rm -f "$STATE_FILE"
        emit_refresh
        ;;

    *)
        echo "Usage: $0 {status|start <seconds> [label] [dnd:0|1]|pause|resume|cancel|clear}" >&2
        exit 2
        ;;
esac
