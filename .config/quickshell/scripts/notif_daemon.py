#!/usr/bin/env python3
import sys
import json
import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib
import threading
import os
import subprocess
from PIL import Image

DBusGMainLoop(set_as_default=True)

class NotificationServer(dbus.service.Object):
    def __init__(self):
        bus_name = dbus.service.BusName(
            'org.freedesktop.Notifications', 
            bus=dbus.SessionBus(), 
            replace_existing=True
        )
        super().__init__(bus_name, '/org/freedesktop/Notifications')
        self.notifications = []
        self.dnd = False
        self.next_id = 1
        self.emit_state()

    def safe_print(self, msg):
        try:
            print(msg, flush=True)
        except BrokenPipeError:
            os._exit(0)

    @dbus.service.signal('org.freedesktop.Notifications', signature='us')
    def ActionInvoked(self, id, action_key):
        pass

    @dbus.service.method('org.freedesktop.Notifications', in_signature='susssasa{sv}i', out_signature='u')
    def Notify(self, app_name, replaces_id, app_icon, summary, body, actions, hints, timeout):
        notif_id = int(replaces_id) if replaces_id > 0 else self.next_id
        if replaces_id == 0:
            self.next_id += 1

        urgency = int(hints.get("urgency", 1))

        icon = str(app_icon) if app_icon else ""

        if not icon:
            if "image-path" in hints:
                icon = str(hints["image-path"])
            elif "image-data" in hints or "icon_data" in hints:
                img_key = "image-data" if "image-data" in hints else "icon_data"
                try:
                    img_data = hints[img_key]
                    width = int(img_data[0])
                    height = int(img_data[1])
                    rowstride = int(img_data[2])
                    has_alpha = bool(img_data[3])
                    pixels = bytes(img_data[6])

                    mode = 'RGBA' if has_alpha else 'RGB'
                    image = Image.frombytes(mode, (width, height), pixels, 'raw', mode, rowstride, 1)
                    
                    tmp_path = f"/tmp/qs_notif_icon_{notif_id}.png"
                    image.save(tmp_path)
                    icon = tmp_path
                except Exception as e:
                    pass

        if not icon:
            app_str = str(app_name).lower().replace(" ", "-")
            if app_str:
                icon = app_str

        if not icon:
            icon = "dialog-information"

        notif = {
            "id": notif_id,
            "app": str(app_name),
            "title": str(summary),
            "body": str(body).replace("\n", " "),
            "icon": icon,
            "urgency": urgency
        }

        existing = next((i for i, n in enumerate(self.notifications) if n["id"] == notif_id), -1)
        if existing >= 0:
            self.notifications[existing] = notif
        else:
            self.notifications.insert(0, notif)

        self.emit_state()

        if not self.dnd:
            self.safe_print(f"POPUP|{json.dumps(notif)}")
            try:
                subprocess.Popen(
                    ["paplay", "/usr/share/sounds/freedesktop/stereo/message.oga"],
                    stdout=subprocess.DEVNULL, 
                    stderr=subprocess.DEVNULL
                )
            except Exception:
                pass

        return notif_id

    @dbus.service.method('org.freedesktop.Notifications', in_signature='', out_signature='ssss')
    def GetServerInformation(self):
        return ("QSDaemon", "Custom", "1.0", "1.2")

    @dbus.service.method('org.freedesktop.Notifications', in_signature='', out_signature='as')
    def GetCapabilities(self):
        return ["body", "body-markup", "actions", "icons", "persistence"]

    @dbus.service.method('org.freedesktop.Notifications', in_signature='u', out_signature='')
    def CloseNotification(self, id):
        self.remove_notif(id)
        
    def remove_notif(self, nid):
        self.notifications = [n for n in self.notifications if n["id"] != nid]
        self.emit_state()

    def emit_state(self):
        state = {
            "dnd": self.dnd,
            "count": len(self.notifications),
            "notifications": self.notifications
        }
        self.safe_print(f"STATE|{json.dumps(state)}")

    def clear_all(self):
        self.notifications = []
        self.emit_state()

    def toggle_dnd(self):
        self.dnd = not self.dnd
        self.emit_state()

FIFO_PATH = "/tmp/qs_notif_cmd"
if not os.path.exists(FIFO_PATH):
    os.mkfifo(FIFO_PATH)

server = NotificationServer()

def listen_fifo():
    while True:
        try:
            with open(FIFO_PATH, "r") as f:
                for line in f:
                    cmd = line.strip()
                    if cmd == "CLEAR":
                        GLib.idle_add(server.clear_all)
                    elif cmd == "TOGGLE_DND":
                        GLib.idle_add(server.toggle_dnd)
                    elif cmd.startswith("REMOVE|"):
                        try:
                            nid = int(cmd.split("|")[1])
                            GLib.idle_add(server.remove_notif, nid)
                        except Exception:
                            pass
                    elif cmd.startswith("ACTION|"):
                        try:
                            parts = cmd.split("|")
                            nid = int(parts[1])
                            action_key = parts[2]
                            GLib.idle_add(server.ActionInvoked, nid, action_key)
                        except Exception:
                            pass
                    elif cmd.startswith("CLEAR_APP|"):
                        try:
                            app_to_clear = cmd.split("|")[1].lower()
                            server.notifications = [n for n in server.notifications if n["app"].lower() != app_to_clear]
                            GLib.idle_add(server.emit_state)
                        except Exception:
                            pass
        except Exception:
            pass

threading.Thread(target=listen_fifo, daemon=True).start()

try:
    loop = GLib.MainLoop()
    loop.run()
except KeyboardInterrupt:
    sys.exit(0)