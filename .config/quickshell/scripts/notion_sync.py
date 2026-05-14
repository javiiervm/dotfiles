import os
import sys
import json
import requests
from datetime import datetime, timezone, timedelta
import icalendar
import recurring_ical_events

CACHE_FILE = os.path.expanduser('~/.cache/qs_notion.json')

NOTION_API_KEY = os.environ.get("NOTION_API_KEY")
NOTION_DB_1 = os.environ.get("NOTION_DB_ID")
NOTION_DB_2 = os.environ.get("NOTION_DB_ID_2")
ICAL_URL = os.environ.get("ICAL_URL")

if not NOTION_API_KEY and not ICAL_URL:
    with open(CACHE_FILE, 'w') as f:
        json.dump({"header": "Not Configured", "days": []}, f)
    sys.exit(1)

DATABASES = [db for db in [NOTION_DB_1, NOTION_DB_2] if db]
headers = {
    "Authorization": f"Bearer {NOTION_API_KEY}",
    "Notion-Version": "2022-06-28",
    "Content-Type": "application/json"
}

all_events = []
now = datetime.now(timezone.utc)
two_weeks_later = now + timedelta(days=14)

start_date_str = now.strftime("%Y-%m-%d")
end_date_str = two_weeks_later.strftime("%Y-%m-%d")

def fetch_database(db_id):
    url = f"https://api.notion.com/v1/databases/{db_id}/query"
    payload = {
        "filter": {
            "and": [
                {"property": "Date", "date": {"on_or_after": start_date_str}},
                {"property": "Date", "date": {"on_or_before": end_date_str}}
            ]
        },
        "page_size": 25
    }
    
    try:
        response = requests.post(url, headers=headers, json=payload)
        response.raise_for_status()
        
        for result in response.json().get("results", []):
            props = result["properties"]
            try:
                title = props["Name"]["title"][0]["plain_text"]
            except (KeyError, IndexError):
                continue

            try:
                date_prop = props["Date"]["date"]
                start_str = date_prop["start"]
                end_str = date_prop.get("end")
                
                dt_start = datetime.fromisoformat(start_str.replace('Z', '+00:00'))
                is_allday = len(start_str) <= 10
                
                if dt_start.tzinfo is None:
                    dt_start = dt_start.replace(tzinfo=timezone.utc)
                
                if end_str:
                    dt_end = datetime.fromisoformat(end_str.replace('Z', '+00:00'))
                    if dt_end.tzinfo is None: dt_end = dt_end.replace(tzinfo=timezone.utc)
                else:
                    dt_end = dt_start + timedelta(days=1) if is_allday else dt_start + timedelta(hours=1)

                # FILTRO CLAVE: Si ya ha terminado, lo ignoramos
                if dt_end <= now:
                    continue

                time_str = "All day" if is_allday else dt_start.strftime("%H:%M")
            except Exception:
                continue

            try:
                location = props["Location"]["rich_text"][0]["plain_text"]
            except (KeyError, IndexError):
                location = ""

            all_events.append({
                "title": title, "time": time_str, "location": location,
                "_raw_start": dt_start, "is_allday": is_allday
            })
    except Exception:
        pass

for db in DATABASES:
    fetch_database(db)

if ICAL_URL:
    try:
        cal_resp = requests.get(ICAL_URL)
        cal_resp.raise_for_status()
        cal = icalendar.Calendar.from_ical(cal_resp.text)
        events_in_range = recurring_ical_events.of(cal).between(now, two_weeks_later)
        
        for component in events_in_range:
            dtstart = component.get('dtstart')
            dtend = component.get('dtend')
            if not dtstart: continue
                
            try:
                dt_start_raw = dtstart.dt
                is_allday = not isinstance(dt_start_raw, datetime)

                if is_allday:
                    dt_start = datetime.combine(dt_start_raw, datetime.min.time()).replace(tzinfo=timezone.utc)
                    if dtend:
                        dt_end = datetime.combine(dtend.dt, datetime.min.time()).replace(tzinfo=timezone.utc)
                    else:
                        dt_end = dt_start + timedelta(days=1)
                    time_str = "All day"
                else:
                    dt_start = dt_start_raw
                    if dt_start.tzinfo is None: dt_start = dt_start.replace(tzinfo=timezone.utc)
                    
                    if dtend:
                        dt_end_raw = dtend.dt
                        if not isinstance(dt_end_raw, datetime):
                            dt_end = datetime.combine(dt_end_raw, datetime.min.time()).replace(tzinfo=timezone.utc)
                        elif dt_end_raw.tzinfo is None:
                            dt_end = dt_end_raw.replace(tzinfo=timezone.utc)
                        else:
                            dt_end = dt_end_raw
                    else:
                        dt_end = dt_start + timedelta(hours=1)
                    time_str = dt_start.strftime("%H:%M")

                # FILTRO CLAVE: Si ya ha terminado, lo ignoramos
                if dt_end <= now:
                    continue

                title = str(component.get('summary', 'Evento'))
                location = str(component.get('location', ''))
                
                all_events.append({
                    "title": title, "time": time_str, "location": location,
                    "_raw_start": dt_start, "is_allday": is_allday
                })
            except Exception:
                continue
    except Exception:
        pass

# ORDENACIÓN MAGISTRAL: 1º por Día, 2º All Day arriba (False va antes que True), 3º Hora de inicio
all_events.sort(key=lambda x: (x["_raw_start"].date(), not x["is_allday"], x["_raw_start"]))

# AGRUPACIÓN POR DÍAS
days_dict = {}
today_date = now.date()

for ev in all_events:
    ev_date = ev["_raw_start"].date()
    date_key = ev_date.strftime('%Y-%m-%d')

    if date_key not in days_dict:
        if ev_date == today_date: day_label = "Today"
        elif ev_date == today_date + timedelta(days=1): day_label = "Tomorrow"
        else: day_label = ev["_raw_start"].strftime("%A")

        days_dict[date_key] = {
            "day_label": day_label,
            "date_label": ev["_raw_start"].strftime("%d %b"),
            "events": []
        }

    days_dict[date_key]["events"].append({
        "title": ev["title"],
        "time": ev["time"],
        "location": ev["location"]
    })

output = {
    "header": now.strftime("%A, %d %b (This Week)"),
    "days": list(days_dict.values())
}

try:
    with open(CACHE_FILE, 'w') as f:
        json.dump(output, f)
except Exception:
    pass