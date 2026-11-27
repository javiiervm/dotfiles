#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/qs-screenrec"
STATE_FILE="$STATE_DIR/state.env"
SEG_DIR="$STATE_DIR/segments"
CAMERA_QML="$HOME/.config/quickshell/components/CameraOverlay.qml"
EVENT_FIFO="${XDG_RUNTIME_DIR:-/tmp}/qs-screenrec-events"
LOG_FILE="$STATE_DIR/recorder.log"
mkdir -p "$STATE_DIR"

emit_event() {
    if [[ -p "$EVENT_FIFO" ]]; then
        timeout 0.15 bash -c 'printf "%s\n" "$1" > "$2"' _ "${1:-refresh}" "$EVENT_FIFO" 2>/dev/null || true
    fi
}

save_state() {
    local key tmp="$STATE_FILE.tmp"
    for key in STATUS PID STARTED_AT ELAPSED CAPTURE GEOMETRY OUTPUT_NAME AUDIO AUDIO_SOURCE OUTPUT_FILE SEGMENT NULL_MODULE LOOPBACK1 LOOPBACK2 COMBINED_SINK CAMERA CAMERA_PID CAMERA_OUTPUT MONITOR_LAYOUT PIDS; do
        printf '%s=%q\n' "$key" "${!key}"
    done > "$tmp"
    mv "$tmp" "$STATE_FILE"
}

load_state() {
    STATUS=idle; PID=''; STARTED_AT=0; ELAPSED=0; CAPTURE=screen; GEOMETRY=''; OUTPUT_NAME=''
    AUDIO=none; AUDIO_SOURCE=''; OUTPUT_FILE=''; SEGMENT=0
    NULL_MODULE=''; LOOPBACK1=''; LOOPBACK2=''; COMBINED_SINK=''
    CAMERA=0; CAMERA_PID=''; CAMERA_OUTPUT=''; MONITOR_LAYOUT=''; PIDS=''
    [[ ! -f "$STATE_FILE" ]] || source "$STATE_FILE"
    return 0
}

notify_error() {
    printf '%s\n' "$*" >&2
    if command -v notify-send >/dev/null; then
        notify-send -u normal 'Screen recording' "$*" || true
    fi
}

is_alive() {
    local pid="${1:-}" stat
    [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null || return 1
    stat="$(ps -o stat= -p "$pid" 2>/dev/null || true)"
    [[ -n "$stat" && "$stat" != Z* ]]
}

cleanup_audio() {
    local id
    for id in "$LOOPBACK1" "$LOOPBACK2" "$NULL_MODULE"; do
        [[ -z "$id" ]] || pactl unload-module "$id" >/dev/null 2>&1 || true
    done
    NULL_MODULE=''; LOOPBACK1=''; LOOPBACK2=''; COMBINED_SINK=''; AUDIO_SOURCE=''
}

cleanup_camera() {
    if is_alive "$CAMERA_PID"; then
        kill -TERM "$CAMERA_PID" 2>/dev/null || true
        for _ in {1..20}; do
            is_alive "$CAMERA_PID" || break
            sleep 0.05
        done
        if is_alive "$CAMERA_PID"; then kill -KILL "$CAMERA_PID" 2>/dev/null || true; fi
    fi
    CAMERA_PID=''
}

start_camera() {
    [[ "$CAMERA" == 1 ]] || return 0
    local qs_bin
    qs_bin="$(command -v qs || command -v quickshell)" || return 1
    [[ -f "$CAMERA_QML" ]] || return 1
    QS_SCREENREC_CAMERA_OUTPUT="$CAMERA_OUTPUT" "$qs_bin" -p "$CAMERA_QML" >> "$LOG_FILE" 2>&1 9>&- &
    CAMERA_PID=$!
    sleep 0.35
    is_alive "$CAMERA_PID"
}

setup_audio() {
    AUDIO_SOURCE=''
    case "$AUDIO" in
        none) ;;
        system)
            local sink
            sink="$(pactl get-default-sink)" || return 1
            [[ -n "$sink" ]] || return 1
            AUDIO_SOURCE="${sink}.monitor" ;;
        mic)
            AUDIO_SOURCE="$(pactl get-default-source)" || return 1
            [[ -n "$AUDIO_SOURCE" ]] || return 1 ;;
        both)
            local sink mic
            sink="$(pactl get-default-sink)" || return 1
            mic="$(pactl get-default-source)" || return 1
            [[ -n "$sink" && -n "$mic" ]] || return 1
            COMBINED_SINK="QSCombined_${USER}_$$"
            NULL_MODULE="$(pactl load-module module-null-sink sink_name="$COMBINED_SINK" sink_properties=device.description=QuickshellRecordingMix)" || return 1
            LOOPBACK1="$(pactl load-module module-loopback source="${sink}.monitor" sink="$COMBINED_SINK" latency_msec=20)" || return 1
            LOOPBACK2="$(pactl load-module module-loopback source="$mic" sink="$COMBINED_SINK" latency_msec=20)" || return 1
            AUDIO_SOURCE="${COMBINED_SINK}.monitor" ;;
        *) return 1 ;;
    esac
}

# Parse Hyprland's current enabled outputs. Coordinates are logical pixels.
monitor_query() {
    python3 -c '
import json, sys
mode = sys.argv[1]
monitors = [m for m in json.load(sys.stdin) if not m.get("disabled") and m.get("mirrorOf", "none") in ("none", "", None)]
if not monitors:
    sys.exit(1)
monitors.sort(key=lambda m: m["name"])
def geom(m):
    w, h = m["width"], m["height"]
    if int(m.get("transform", 0)) % 2:
        w, h = h, w
    scale = float(m.get("scale", 1)) or 1
    return m["x"], m["y"], max(2, round(w / scale)), max(2, round(h / scale))
if mode == "names":
    print("\n".join(m["name"] for m in monitors))
elif mode == "focused":
    print(next((m["name"] for m in monitors if m.get("focused")), monitors[0]["name"]))
elif mode == "labels":
    for m in monitors:
        _, _, w, h = geom(m)
        name, desc = m["name"], m.get("description", "").strip()
        print(f"{name}  ·  {desc}  ·  {w}×{h}".replace("\n", " "))
elif mode == "area":
    pos, size = sys.argv[2].split()
    x, y = map(int, pos.split(",")); w, h = map(int, size.split("x"))
    for m in monitors:
        mx, my, mw, mh = geom(m)
        if mx <= x and my <= y and x+w <= mx+mw and y+h <= my+mh:
            print(m["name"]); break
    else:
        sys.exit(1)
elif mode == "layout":
    # Fit the logical desktop into a 4K canvas without distorting it.
    rects = [(m["name"], *geom(m)) for m in monitors]
    left = min(r[1] for r in rects); top = min(r[2] for r in rects)
    right = max(r[1]+r[3] for r in rects); bottom = max(r[2]+r[4] for r in rects)
    scale = min(1, 3840/(right-left), 2160/(bottom-top))
    def even(v): return 2*round(v/2)
    layout = []
    for name,x,y,w,h in rects:
        x0,y0 = even((x-left)*scale),even((y-top)*scale)
        x1,y1 = even((x+w-left)*scale),even((y+h-top)*scale)
        layout.append(dict(name=name,x=x0,y=y0,w=max(2,x1-x0),h=max(2,y1-y0)))
    print(json.dumps(layout))
' "$@" <<< "$MONITORS_JSON"
}

select_capture() {
    local focus
    local -a names=()
    MONITORS_JSON="$(hyprctl monitors -j)" || return 1
    focus="$(monitor_query focused)" || return 1
    mapfile -t names < <(monitor_query names)
    ((${#names[@]})) || return 1
    CAMERA_OUTPUT="$focus"

    if [[ "$CAPTURE" == area ]]; then
        GEOMETRY="$(slurp -f '%x,%y %wx%h')" || return 2
        [[ -n "$GEOMETRY" ]] || return 2
        CAMERA_OUTPUT="$(monitor_query area "$GEOMETRY")" || {
            notify_error 'Select an area inside a single monitor.'; return 2;
        }
        return 0
    fi

    if [[ "$CAPTURE" == all ]]; then
        if ((${#names[@]} == 1)); then
            CAPTURE=screen; OUTPUT_NAME="${names[0]}"
        else
            MONITOR_LAYOUT="$(monitor_query layout)" || return 1
        fi
    fi

    if [[ "$CAPTURE" == screen ]]; then
        OUTPUT_NAME="${OUTPUT_NAME:-$focus}"
        local found=0 name
        for name in "${names[@]}"; do [[ "$name" != "$OUTPUT_NAME" ]] || found=1; done
        ((found)) || return 1
        CAMERA_OUTPUT="$OUTPUT_NAME"
    fi
}

stop_segment() {
    local pid active failed=0
    local -a running=()
    if [[ -n "$PIDS" ]]; then read -r -a running <<< "$PIDS"
    elif [[ -n "$PID" ]]; then running=("$PID"); fi
    # Signal every capture before waiting for any of them.
    for pid in "${running[@]}"; do
        if is_alive "$pid"; then kill -INT "$pid" 2>/dev/null || true; fi
    done
    for _ in {1..200}; do
        active=0
        for pid in "${running[@]}"; do if is_alive "$pid"; then active=1; fi; done
        ((active)) || break
        sleep 0.05
    done
    for pid in "${running[@]}"; do
        if is_alive "$pid"; then kill -TERM "$pid" 2>/dev/null || true; failed=1; fi
    done
    if ((failed)); then
        sleep 0.5
        for pid in "${running[@]}"; do if is_alive "$pid"; then kill -KILL "$pid" 2>/dev/null || true; fi; done
    fi
    PID=''; PIDS=''
    return "$failed"
}

start_segment() {
    SEGMENT=$((SEGMENT + 1))
    local prefix="$SEG_DIR/segment-$(printf '%03d' "$SEGMENT")" name i=0 pid
    local -a args names=() running=()
    PIDS=''; PID=''
    if [[ "$CAPTURE" == all ]]; then
        # Reject topology changes between pause/resume rather than silently
        # creating captures with incompatible geometry.
        MONITORS_JSON="$(hyprctl monitors -j)" || return 1
        [[ "$(monitor_query layout)" == "$MONITOR_LAYOUT" ]] || {
            echo 'Monitor layout changed; stop and save this recording before starting another.' >> "$LOG_FILE"
            return 1
        }
        mapfile -t names < <(python3 -c 'import json,sys; print("\n".join(m["name"] for m in json.loads(sys.argv[1])))' "$MONITOR_LAYOUT")
        ((${#names[@]} > 1)) || return 1
        mkdir -p "$prefix"
        for name in "${names[@]}"; do
            args=(wf-recorder -y --no-dmabuf -D -r 30 -c libx264 -p preset=ultrafast -p crf=20 -o "$name" -f "$prefix/output-$i.mkv")
            if ((i == 0)) && [[ "$AUDIO" != none ]]; then args+=(--audio="$AUDIO_SOURCE"); fi
            "${args[@]}" >> "$LOG_FILE" 2>&1 9>&- &
            running+=("$!"); i=$((i+1))
        done
    else
        args=(wf-recorder -y -f "$prefix.mp4")
        if [[ "$CAPTURE" == area ]]; then args+=(-g "$GEOMETRY")
        else args+=(-o "$OUTPUT_NAME"); fi
        [[ "$AUDIO" == none ]] || args+=(--audio="$AUDIO_SOURCE")
        "${args[@]}" >> "$LOG_FILE" 2>&1 9>&- &
        running+=("$!")
    fi
    PIDS="${running[*]}"; PID="${running[0]}"
    STARTED_AT="$(date +%s)"
    sleep 0.8
    for pid in "${running[@]}"; do
        if ! is_alive "$pid"; then
            stop_segment || true; STARTED_AT=0
            local recovery="$STATE_DIR/recovery-failed-$(date +%Y%m%d-%H%M%S)-$$"
            if [[ -d "$prefix" ]]; then mv "$prefix" "$recovery" || true
            elif [[ -f "$prefix.mp4" ]]; then mv "$prefix.mp4" "$recovery.mp4" || true; fi
            SEGMENT=$((SEGMENT - 1))
            return 1
        fi
    done
}

compose_all() {
    python3 - "$SEG_DIR" "$MONITOR_LAYOUT" "$AUDIO" <<'PY_COMPOSE'
import json, pathlib, subprocess, sys
root = pathlib.Path(sys.argv[1]); layout = json.loads(sys.argv[2]); audio = sys.argv[3]

def probe(path, stream):
    if not path.is_file(): return False
    result = subprocess.run(['ffprobe','-v','error','-select_streams',stream,'-show_entries','stream=codec_name','-of','csv=p=0',str(path)],capture_output=True,text=True)
    return result.returncode == 0 and bool(result.stdout.strip())

for directory in sorted(root.glob('segment-*')):
    if not directory.is_dir(): continue
    inputs = [directory / f'output-{i}.mkv' for i in range(len(layout))]
    if not all(probe(p,'v:0') for p in inputs):
        raise SystemExit(f'Missing or invalid capture in {directory}; raw recordings retained.')
    if audio != 'none' and not probe(inputs[0],'a:0'):
        raise SystemExit(f'Missing audio in {directory}; raw recordings retained.')
    filters = [f'[{i}:v]setpts=PTS-STARTPTS,fps=30,scale={m["w"]}:{m["h"]},setsar=1,format=yuv420p[v{i}]' for i,m in enumerate(layout)]
    labels = ''.join(f'[v{i}]' for i in range(len(layout)))
    positions = '|'.join(f'{m["x"]}_{m["y"]}' for m in layout)
    filters.append(f'{labels}xstack=inputs={len(layout)}:layout={positions}:fill=black:shortest=0[v]')
    cmd = ['ffmpeg','-hide_banner','-loglevel','error','-y','-filter_complex_threads','2']
    for path in inputs: cmd += ['-i',str(path)]
    cmd += ['-filter_complex',';'.join(filters),'-map','[v]']
    if audio != 'none': cmd += ['-map','0:a:0','-af','apad','-shortest','-c:a','aac']
    cmd += ['-c:v','libx264','-preset','veryfast','-crf','20','-pix_fmt','yuv420p',str(directory)+'.mp4']
    subprocess.run(cmd,check=True)
PY_COMPOSE
}

fail_start() {
    stop_segment || true
    cleanup_camera
    cleanup_audio
    STATUS=idle; STARTED_AT=0
    save_state; emit_event refresh
    notify_error "$1 (log: $LOG_FILE)"
    exit 5
}

add_elapsed() {
    local now
    now="$(date +%s)"
    if ((STARTED_AT > 0 && now >= STARTED_AT)); then ELAPSED=$((ELAPSED + now - STARTED_AT)); fi
    STARTED_AT=0
}

write_json() {
    load_state
    local now elapsed="$ELAPSED"
    now="$(date +%s)"
    if [[ "$STATUS" == running ]] && ((STARTED_AT > 0 && now >= STARTED_AT)); then
        elapsed=$((elapsed + now - STARTED_AT))
    fi
    python3 - "$STATUS" "$elapsed" "$OUTPUT_FILE" "$AUDIO" "$CAPTURE" "$CAMERA" <<'PY'
import json, sys
print(json.dumps(dict(status=sys.argv[1], elapsed=int(sys.argv[2]), output=sys.argv[3], audio=sys.argv[4], capture=sys.argv[5], camera=sys.argv[6] == '1')))
PY
}

cmd="${1:-status}"
if [[ "$cmd" != status ]]; then
    exec 9>"$STATE_DIR/action.lock"
    flock -n 9 || exit 3
fi

case "$cmd" in
    start)
        capture="${2:-screen}"; audio="${3:-none}"; camera="${4:-0}"
        [[ "$camera" == 1 ]] || camera=0
        case "$capture" in screen|area|all) ;; *) exit 2 ;; esac
        case "$audio" in none|system|mic|both) ;; *) exit 2 ;; esac
        load_state
        case "$STATUS" in running|paused|starting|finalizing) notify_error 'A recording is already active.'; exit 3 ;; esac
        for dep in hyprctl python3 ffmpeg ffprobe; do command -v "$dep" >/dev/null || { notify_error "Missing dependency: $dep"; exit 4; }; done
        if [[ "$capture" == area ]]; then command -v slurp >/dev/null || { notify_error 'Missing dependency: slurp'; exit 4; }; fi
        STATUS=starting; PID=''; STARTED_AT=0; ELAPSED=0; SEGMENT=0
        CAPTURE="$capture"; AUDIO="$audio"; CAMERA="$camera"; CAMERA_PID=''
        GEOMETRY=''; OUTPUT_NAME="${5:-}"; CAMERA_OUTPUT=''; MONITOR_LAYOUT=''; PIDS=''
        OUTPUT_FILE="$HOME/Videos/Recordings/recording-$(date +%Y-%m-%d_%H-%M-%S).mp4"
        NULL_MODULE=''; LOOPBACK1=''; LOOPBACK2=''; COMBINED_SINK=''; AUDIO_SOURCE=''
        save_state; emit_event refresh
        if select_capture; then :; else
            rc=$?; STATUS=idle; save_state; emit_event refresh
            ((rc == 2)) && exit 0
            notify_error 'Could not select a monitor.'; exit 5
        fi
        command -v wf-recorder >/dev/null || fail_start 'wf-recorder is not installed.' 
        if [[ -d "$SEG_DIR" ]]; then
            mv "$SEG_DIR" "$STATE_DIR/recovery-$(date +%Y%m%d-%H%M%S)-$$" || fail_start 'Could not preserve previous captures.'
        fi
        mkdir -p "$SEG_DIR" "$HOME/Videos/Recordings"
        : > "$LOG_FILE"
        setup_audio || fail_start 'Could not initialize audio.'
        start_camera || fail_start 'Could not open the camera overlay.'
        start_segment || fail_start 'The recorder failed to start.'
        STATUS=running; save_state; emit_event refresh ;;

    pause)
        load_state; [[ "$STATUS" == running ]] || exit 0
        add_elapsed
        if ! stop_segment; then notify_error 'The recorder did not stop cleanly. Check the saved segments.'; fi
        STATUS=paused; save_state; emit_event refresh ;;

    resume)
        load_state; [[ "$STATUS" == paused ]] || exit 0
        if ! start_segment; then
            STATUS=paused; save_state; emit_event refresh
            notify_error 'Could not resume recording. Stop to save previous segments.'; exit 5
        fi
        STATUS=running; save_state; emit_event refresh ;;

    stop)
        load_state; [[ "$STATUS" == running || "$STATUS" == paused ]] || exit 0
        if [[ "$STATUS" == running ]]; then add_elapsed; fi
        if ! stop_segment; then notify_error 'Recorder did not shut down cleanly; checking available segments.'; fi
        cleanup_camera; cleanup_audio
        STATUS=finalizing; save_state; emit_event refresh
        if [[ "$CAPTURE" == all ]]; then
            if ! compose_all >> "$LOG_FILE" 2>&1; then
                STATUS=idle; save_state; emit_event refresh
                notify_error "Could not compose all monitors. Raw captures remain in $SEG_DIR"; exit 6
            fi
        fi
        shopt -s nullglob
        segments=()
        for seg in "$SEG_DIR"/segment-*.mp4; do
            if [[ -s "$seg" ]] && [[ -n "$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$seg" 2>/dev/null || true)" ]]; then
                segments+=("$seg")
            fi
        done
        if ((${#segments[@]} == 0)); then
            STATUS=idle; save_state; emit_event refresh
            notify_error "No valid recording segments. Check $LOG_FILE"; exit 6
        fi
        list="$STATE_DIR/concat.txt"
        if ((${#segments[@]} == 1)); then
            if ! mv "${segments[0]}" "$OUTPUT_FILE"; then fail_start 'Could not save recording.'; fi
        else
            : > "$list"
            for seg in "${segments[@]}"; do printf "file '%s'\n" "${seg//\'/\'\\\'\'}" >> "$list"; done
            if ! ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i "$list" -c copy "$OUTPUT_FILE" >> "$LOG_FILE" 2>&1; then
                if ! ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i "$list" -c:v libx264 -preset veryfast -c:a aac "$OUTPUT_FILE" >> "$LOG_FILE" 2>&1; then
                    STATUS=idle; save_state; emit_event refresh
                    notify_error "Could not join segments. They remain in $SEG_DIR"; exit 6
                fi
            fi
        fi
        rm -rf "$SEG_DIR" "$list"
        STATUS=finished; save_state; emit_event refresh ;;

    clear)
        load_state
        case "$STATUS" in running|paused|starting|finalizing) exit 0 ;; esac
        cleanup_camera; STATUS=idle; ELAPSED=0; OUTPUT_FILE=''; STARTED_AT=0; PID=''; SEGMENT=0; CAMERA=0
        save_state; emit_event refresh ;;
    status|*) write_json ;;
esac
