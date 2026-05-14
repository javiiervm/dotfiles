import os
import json
import socket
import time
import subprocess
from datetime import datetime, timedelta

# Cambiamos /tmp por ~/.cache para que los datos sobrevivan a los reinicios
CACHE_DIR = os.path.expanduser("~/.cache")
OUT_FILE = os.path.join(CACHE_DIR, "qs_app_usage.json")
HISTORY_FILE = os.path.join(CACHE_DIR, "qs_app_usage_history.json")

SIG = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
SOCK_PATH = f"/run/user/{os.getuid()}/hypr/{SIG}/.socket2.sock"

app_usage = {}
history_data = {}
active_app = None
last_time = time.time()
current_day = datetime.now().date()

def format_time(seconds):
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    if h > 0: return f"{h}h {m}m"
    return f"{m}m"

def load_history():
    global history_data, app_usage
    if os.path.exists(HISTORY_FILE):
        try:
            with open(HISTORY_FILE, "r") as f:
                data = json.load(f)
                history_data = data.get("days", {})
                
                # Si hoy ya tenía datos guardados de antes del reinicio, los cargamos
                today_str = current_day.isoformat()
                if today_str in data.get("apps", {}):
                    app_usage = data["apps"][today_str]
        except:
            pass

def get_initial_window():
    try:
        out = subprocess.check_output(["hyprctl", "activewindow", "-j"])
        return json.loads(out).get("class", "none")
    except:
        return "none"

def save_data():
    global last_time, active_app
    now = time.time()
    
    if active_app and active_app != "none":
        app_usage[active_app] = app_usage.get(active_app, 0) + (now - last_time)
    
    last_time = now
    today_total_sec = sum(app_usage.values())
    today_str = current_day.isoformat()
    
    # --- CALCULAR ESTADÍSTICAS ---
    yesterday = (current_day - timedelta(days=1)).isoformat()
    y_sec = history_data.get(yesterday, 0)
    diff = today_total_sec - y_sec
    vs_yesterday = f"↑ {format_time(diff)}" if diff >= 0 else f"↓ {format_time(abs(diff))}"
    
    # Media histórica (excluyendo hoy si está incompleto, o incluyendo si es el único día)
    all_secs = list(history_data.values())
    avg_sec = (sum(all_secs) / len(all_secs)) if all_secs else today_total_sec
    
    # Datos para la gráfica semanal (Lunes = 0, Domingo = 6)
    start_of_week = current_day - timedelta(days=current_day.weekday())
    week_secs = []
    for i in range(7):
        d = start_of_week + timedelta(days=i)
        if d == current_day:
            week_secs.append(today_total_sec)
        else:
            week_secs.append(history_data.get(d.isoformat(), 0))
            
    max_week_sec = max(week_secs) if max(week_secs) > 0 else 1
    chart_data = [round(s / max_week_sec, 3) for s in week_secs]

    # --- LISTA DE APPS ---
    apps_list = []
    for app, sec in sorted(app_usage.items(), key=lambda x: x[1], reverse=True)[:5]:
        if sec < 1: continue 
        percent = sec / today_total_sec if today_total_sec > 0 else 0
        apps_list.append({
            "name": app.capitalize(), "time": format_time(sec),
            "icon": app.lower(), "percent": round(percent, 3)
        })

    # --- GUARDAR SALIDA PARA QML ---
    data_out = {
        "total": format_time(today_total_sec),
        "avg_daily": format_time(avg_sec),
        "vs_yesterday": vs_yesterday,
        "chart": chart_data,
        "current_day_index": current_day.weekday(),
        "apps": apps_list
    }
    with open(OUT_FILE, "w") as f:
        json.dump(data_out, f)
        
    # --- GUARDAR HISTÓRICO ---
    history_data[today_str] = today_total_sec
    with open(HISTORY_FILE, "w") as f:
        json.dump({"days": history_data, "apps": {today_str: app_usage}}, f)

def reset_if_new_day():
    global current_day, app_usage
    now_day = datetime.now().date()
    if now_day != current_day:
        app_usage = {}
        current_day = now_day

def main():
    global active_app, last_time
    load_history()
    active_app = get_initial_window()
    save_data()

    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.connect(SOCK_PATH)

    while True:
        data = client.recv(4096)
        if not data: break
        reset_if_new_day()
        
        for line in data.decode("utf-8").strip().split('\n'):
            if line.startswith("activewindow>>"):
                parts = line.split(">>")[1].split(",")
                if len(parts) >= 1:
                    save_data() 
                    active_app = parts[0].strip()

if __name__ == "__main__":
    main()