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

    @dbus.service.method('org.freedesktop.Notifications', in_signature='susssasa{sv}i', out_signature='u')
    def Notify(self, app_name, replaces_id, app_icon, summary, body, actions, hints, timeout):
        notif_id = int(replaces_id) if replaces_id > 0 else self.next_id
        if replaces_id == 0:
            self.next_id += 1

        # Extraer la urgencia (por defecto 1 si no existe)
        # Se suele recibir como dbus.Byte, así que lo convertimos a int
        urgency = int(hints.get("urgency", 1))

        icon = str(app_icon) if app_icon else "dialog-information"

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
        # IGNORAR el borrado automático para conservar el historial
        pass
        
    def remove_notif(self, nid):
        # Nueva función para el botón X individual
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
        except Exception:
            pass

threading.Thread(target=listen_fifo, daemon=True).start()

try:
    loop = GLib.MainLoop()
    loop.run()
except KeyboardInterrupt:
    sys.exit(0)