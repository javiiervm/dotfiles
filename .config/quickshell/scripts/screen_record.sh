#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/qs-screenrec"
STATE_FILE="$STATE_DIR/state.env"
SEG_DIR="$STATE_DIR/segments"
CAMERA_QML="$HOME/.config/quickshell/components/CameraOverlay.qml"
EVENT_FIFO="${XDG_RUNTIME_DIR:-/tmp}/qs-screenrec-events"
mkdir -p "$STATE_DIR"

emit_event() {
    # Never block if Quickshell is not listening.
    if [[ -p "$EVENT_FIFO" ]]; then
        timeout 0.15 bash -c 'printf "%s\n" "$1" > "$2"' _ "${1:-refresh}" "$EVENT_FIFO" 2>/dev/null || true
    fi
}

save_state() {
    local tmp="$STATE_FILE.tmp"
    {
        printf 'STATUS=%q\n' "$STATUS"
        printf 'PID=%q\n' "${PID:-}"
        printf 'STARTED_AT=%q\n' "${STARTED_AT:-0}"
        printf 'ELAPSED=%q\n' "${ELAPSED:-0}"
        printf 'CAPTURE=%q\n' "${CAPTURE:-screen}"
        printf 'GEOMETRY=%q\n' "${GEOMETRY:-}"
        printf 'OUTPUT_NAME=%q\n' "${OUTPUT_NAME:-}"
        printf 'AUDIO=%q\n' "${AUDIO:-none}"
        printf 'AUDIO_SOURCE=%q\n' "${AUDIO_SOURCE:-}"
        printf 'OUTPUT_FILE=%q\n' "${OUTPUT_FILE:-}"
        printf 'SEGMENT=%q\n' "${SEGMENT:-0}"
        printf 'NULL_MODULE=%q\n' "${NULL_MODULE:-}"
        printf 'LOOPBACK1=%q\n' "${LOOPBACK1:-}"
        printf 'LOOPBACK2=%q\n' "${LOOPBACK2:-}"
        printf 'COMBINED_SINK=%q\n' "${COMBINED_SINK:-}"
        printf 'CAMERA=%q\n' "${CAMERA:-0}"
        printf 'CAMERA_PID=%q\n' "${CAMERA_PID:-}"
    } > "$tmp"
    mv "$tmp" "$STATE_FILE"
}

load_state() {
    STATUS="idle"; PID=""; STARTED_AT=0; ELAPSED=0; CAPTURE="screen"; GEOMETRY=""; OUTPUT_NAME=""
    AUDIO="none"; AUDIO_SOURCE=""; OUTPUT_FILE=""; SEGMENT=0
    NULL_MODULE=""; LOOPBACK1=""; LOOPBACK2=""; COMBINED_SINK=""
    CAMERA=0; CAMERA_PID=""
    if [[ -f "$STATE_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$STATE_FILE"
    fi

    # A missing state file simply means that no recording has ever been
    # started.  Always return success so `set -e` does not abort callers such
    # as `start` and `status` on a fresh session.
    return 0
}

cleanup_audio() {
    for id in "${LOOPBACK1:-}" "${LOOPBACK2:-}" "${NULL_MODULE:-}"; do
        [[ -n "$id" ]] && pactl unload-module "$id" >/dev/null 2>&1 || true
    done
    NULL_MODULE=""; LOOPBACK1=""; LOOPBACK2=""; COMBINED_SINK=""; AUDIO_SOURCE=""
}

cleanup_camera() {
    if [[ -n "${CAMERA_PID:-}" ]] && kill -0 "$CAMERA_PID" 2>/dev/null; then
        kill -TERM "$CAMERA_PID" 2>/dev/null || true
        # One-shot shutdown wait only; no background polling is introduced.
        for _ in {1..20}; do
            kill -0 "$CAMERA_PID" 2>/dev/null || break
            sleep 0.05
        done
        kill -KILL "$CAMERA_PID" 2>/dev/null || true
    fi
    CAMERA_PID=""
}

start_camera() {
    [[ "${CAMERA:-0}" == "1" ]] || return 0
    command -v qs >/dev/null || command -v quickshell >/dev/null || {
        echo "Quickshell is not installed; cannot open camera overlay" >&2
        return 1
    }
    [[ -f "$CAMERA_QML" ]] || {
        echo "Camera overlay not found: $CAMERA_QML" >&2
        return 1
    }

    local qs_bin
    qs_bin="$(command -v qs 2>/dev/null || command -v quickshell)"
    "$qs_bin" -p "$CAMERA_QML" >/dev/null 2>&1 &
    CAMERA_PID=$!

    # Give the layer-shell surface and camera stream a brief one-time moment to
    # appear before wf-recorder starts. This is not a recurring timer.
    sleep 0.30
    if ! kill -0 "$CAMERA_PID" 2>/dev/null; then
        CAMERA_PID=""
        echo "Camera overlay failed to start. Make sure qt6-multimedia is installed." >&2
        return 1
    fi
}

setup_audio() {
    AUDIO_SOURCE=""
    case "$AUDIO" in
        none) ;;
        system)
            local sink
            sink="$(pactl get-default-sink 2>/dev/null || true)"
            [[ -n "$sink" ]] || { echo "No default audio sink found" >&2; return 1; }
            AUDIO_SOURCE="${sink}.monitor"
            ;;
        mic)
            AUDIO_SOURCE="$(pactl get-default-source 2>/dev/null || true)"
            [[ -n "$AUDIO_SOURCE" ]] || { echo "No default microphone found" >&2; return 1; }
            ;;
        both)
            local sink mic
            sink="$(pactl get-default-sink 2>/dev/null || true)"
            mic="$(pactl get-default-source 2>/dev/null || true)"
            [[ -n "$sink" && -n "$mic" ]] || { echo "Default system/microphone source not found" >&2; return 1; }
            COMBINED_SINK="QSCombined_${USER}_$$"
            NULL_MODULE="$(pactl load-module module-null-sink sink_name="$COMBINED_SINK" sink_properties=device.description=QuickshellRecordingMix)"
            LOOPBACK1="$(pactl load-module module-loopback source="${sink}.monitor" sink="$COMBINED_SINK" latency_msec=20)"
            LOOPBACK2="$(pactl load-module module-loopback source="$mic" sink="$COMBINED_SINK" latency_msec=20)"
            AUDIO_SOURCE="${COMBINED_SINK}.monitor"
            ;;
        *) echo "Unknown audio mode: $AUDIO" >&2; return 2 ;;
    esac
}

stop_segment() {
    if [[ -n "${PID:-}" ]] && kill -0 "$PID" 2>/dev/null; then
        kill -INT "$PID" 2>/dev/null || true
        # Event-time wait only; there is no permanent polling daemon.
        for _ in {1..100}; do
            kill -0 "$PID" 2>/dev/null || break
            sleep 0.05
        done
        kill -TERM "$PID" 2>/dev/null || true
    fi
    PID=""
}

start_segment() {
    SEGMENT=$((SEGMENT + 1))
    local seg
    seg="$SEG_DIR/segment-$(printf '%03d' "$SEGMENT").mp4"
    local -a cmd=(wf-recorder -y -f "$seg")

    if [[ "$CAPTURE" == "area" ]]; then
        cmd+=( -g "$GEOMETRY" )
    elif [[ "$CAPTURE" == "screen" && -n "$OUTPUT_NAME" ]]; then
        cmd+=( -o "$OUTPUT_NAME" )
    fi

    if [[ "$AUDIO" != "none" ]]; then
        cmd+=( --audio="$AUDIO_SOURCE" )
    fi

    "${cmd[@]}" >/dev/null 2>&1 &
    PID=$!
    STARTED_AT="$(date +%s)"
    save_state
}

write_json() {
    load_state
    local now current elapsed
    now="$(date +%s)"
    elapsed="${ELAPSED:-0}"
    if [[ "$STATUS" == "running" && "${STARTED_AT:-0}" -gt 0 ]]; then
        current=$((now - STARTED_AT))
        (( current < 0 )) && current=0
        elapsed=$((elapsed + current))
    fi
    python3 - "$STATUS" "$elapsed" "${OUTPUT_FILE:-}" "${AUDIO:-none}" "${CAPTURE:-screen}" "${CAMERA:-0}" <<'PY'
import json,sys
print(json.dumps({
    "status": sys.argv[1],
    "elapsed": int(sys.argv[2]),
    "output": sys.argv[3],
    "audio": sys.argv[4],
    "capture": sys.argv[5],
    "camera": sys.argv[6] == "1",
}))
PY
}

cmd="${1:-status}"
case "$cmd" in
    start)
        capture="${2:-screen}"
        audio="${3:-none}"
        camera="${4:-0}"
        [[ "$camera" == "1" ]] || camera="0"
        load_state
        if [[ "$STATUS" == "running" || "$STATUS" == "paused" ]]; then
            echo "A recording is already active" >&2
            exit 3
        fi
        command -v wf-recorder >/dev/null || { echo "wf-recorder is not installed" >&2; exit 4; }
        command -v ffmpeg >/dev/null || { echo "ffmpeg is not installed" >&2; exit 4; }
        if [[ "$capture" == "area" ]]; then
            command -v slurp >/dev/null || { echo "slurp is not installed" >&2; exit 4; }
        else
            command -v hyprctl >/dev/null || { echo "hyprctl is not installed" >&2; exit 4; }
        fi

        rm -rf "$SEG_DIR"
        mkdir -p "$SEG_DIR" "$HOME/Videos/Recordings"
        STATUS="starting"; PID=""; STARTED_AT=0; ELAPSED=0; SEGMENT=0
        CAPTURE="$capture"; AUDIO="$audio"; CAMERA="$camera"; CAMERA_PID=""; GEOMETRY=""; OUTPUT_NAME=""
        OUTPUT_FILE="$HOME/Videos/Recordings/recording-$(date +%Y-%m-%d_%H-%M-%S).mp4"
        NULL_MODULE=""; LOOPBACK1=""; LOOPBACK2=""; COMBINED_SINK=""; AUDIO_SOURCE=""
        save_state; emit_event refresh

        if [[ "$CAPTURE" == "area" ]]; then
            GEOMETRY="$(slurp -f '%x,%y %wx%h')" || { STATUS="idle"; save_state; emit_event refresh; exit 0; }
            [[ -n "$GEOMETRY" ]] || { STATUS="idle"; save_state; emit_event refresh; exit 0; }
        else
            # Full-screen recording is intentionally non-interactive: capture the
            # monitor Hyprland currently considers focused. This avoids turning
            # the pointer into a slurp selector for the normal "Screen" mode.
            OUTPUT_NAME="$(hyprctl monitors -j 2>/dev/null | python3 -c '
import json, sys
try:
    monitors = json.load(sys.stdin)
    focused = next((m for m in monitors if m.get("focused")), None)
    chosen = focused or (monitors[0] if monitors else None)
    print(chosen.get("name", "") if chosen else "")
except Exception:
    print("")
')"
            if [[ -z "$OUTPUT_NAME" ]]; then
                echo "Could not determine the focused Hyprland monitor" >&2
                STATUS="idle"; save_state; emit_event refresh
                exit 5
            fi
        fi

        if ! setup_audio; then
            cleanup_audio
            cleanup_camera
            STATUS="idle"; save_state; emit_event refresh
            exit 5
        fi
        if ! start_camera; then
            cleanup_audio
            cleanup_camera
            STATUS="idle"; save_state; emit_event refresh
            exit 5
        fi
        STATUS="running"
        start_segment
        save_state; emit_event refresh
        ;;

    pause)
        load_state
        [[ "$STATUS" == "running" ]] || exit 0
        now="$(date +%s)"
        if [[ "${STARTED_AT:-0}" -gt 0 ]]; then ELAPSED=$((ELAPSED + now - STARTED_AT)); fi
        stop_segment
        STARTED_AT=0
        STATUS="paused"
        save_state; emit_event refresh
        ;;

    resume)
        load_state
        [[ "$STATUS" == "paused" ]] || exit 0
        STATUS="running"
        start_segment
        save_state; emit_event refresh
        ;;

    stop)
        load_state
        [[ "$STATUS" == "running" || "$STATUS" == "paused" ]] || exit 0
        if [[ "$STATUS" == "running" ]]; then
            now="$(date +%s)"
            if [[ "${STARTED_AT:-0}" -gt 0 ]]; then ELAPSED=$((ELAPSED + now - STARTED_AT)); fi
            stop_segment
        fi
        cleanup_camera
        STATUS="finalizing"; STARTED_AT=0
        save_state; emit_event refresh

        list="$STATE_DIR/concat.txt"
        : > "$list"
        shopt -s nullglob
        segments=("$SEG_DIR"/segment-*.mp4)
        if (( ${#segments[@]} == 0 )); then
            cleanup_audio
            cleanup_camera
            STATUS="idle"; save_state; emit_event refresh
            exit 6
        elif (( ${#segments[@]} == 1 )); then
            mv "${segments[0]}" "$OUTPUT_FILE"
        else
            for seg in "${segments[@]}"; do printf "file '%s'\n" "${seg//\'/\'\\\'\'}" >> "$list"; done
            if ! ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i "$list" -c copy "$OUTPUT_FILE"; then
                # Rare codec/timestamp mismatch fallback: re-encode to broadly compatible MP4.
                ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i "$list" -c:v libx264 -preset veryfast -c:a aac "$OUTPUT_FILE"
            fi
        fi
        cleanup_audio
        cleanup_camera
        rm -rf "$SEG_DIR" "$list"
        STATUS="finished"
        save_state; emit_event refresh
        ;;

    clear)
        load_state
        [[ "$STATUS" == "running" || "$STATUS" == "paused" || "$STATUS" == "finalizing" ]] && exit 0
        cleanup_camera
        STATUS="idle"; ELAPSED=0; OUTPUT_FILE=""; STARTED_AT=0; PID=""; SEGMENT=0; CAMERA=0
        save_state; emit_event refresh
        ;;

    status|*) write_json ;;
esac
