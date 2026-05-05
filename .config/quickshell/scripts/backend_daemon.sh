#!/usr/bin/env bash

# 1. PREPARACIÓN DEL CANAL DE EVENTOS (FIFO)
FIFO="/tmp/qs_backend_fifo"
rm -f "$FIFO"
mkfifo "$FIFO"

# Abrimos el FIFO en el Descriptor de Archivo 3 para lectura y escritura.
# Esto es vital: evita que el lector se cierre cuando no hay nadie escribiendo.
exec 3<> "$FIFO"

# --- VARIABLES INICIALES ---
CAP=100; STAT="Unknown"; VOL=0; MUTE="false"; SINK_DESC="Speakers"
SSID="Disconnected"; SIGNAL="0"; FREQ="0"; BT_STAT="off"; BT_DEV="None"
PERF="balanced"; DND="false"; COUNT="0"

BAT_PATH=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -n 1)

# ==========================================
# FUNCIONES DE LECTURA INDIVIDUALES
# ==========================================

update_bat() {
    if [ -n "$BAT_PATH" ]; then
        read CAP < "$BAT_PATH/capacity" 2>/dev/null || CAP=0
        read STAT < "$BAT_PATH/status" 2>/dev/null || STAT="Unknown"
    fi
}

update_vol() {
    VOL_RAW=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || echo "Volume: 0.00")
    [[ "$VOL_RAW" == *MUTED* ]] && MUTE="true" || MUTE="false"
    VOL_STR=${VOL_RAW#* }
    VOL_STR=${VOL_STR% \[MUTED\]}
    VOL=$(awk -v v="$VOL_STR" 'BEGIN {print int(v * 100)}')
    SINK_DESC=$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk -F'"' '/node.description/ {print $2; exit}')
    [ -z "$SINK_DESC" ] && SINK_DESC="Speakers"
}

update_net() {
    WIFI_INFO=$(nmcli -t -f ACTIVE,SSID,SIGNAL,FREQ device wifi 2>/dev/null | awk -F: '$1=="yes" {print $2":"$3":"$4; exit}')
    if [ -n "$WIFI_INFO" ]; then
        SSID=$(echo "$WIFI_INFO" | cut -d: -f1)
        SIGNAL=$(echo "$WIFI_INFO" | cut -d: -f2)
        FREQ_RAW=$(echo "$WIFI_INFO" | cut -d: -f3)
        FREQ=$(echo "$FREQ_RAW" | tr -dc '0-9')
    else
        SSID="Disconnected"; SIGNAL="0"; FREQ="0"
    fi
}

update_bt() {
    bluetoothctl show 2>/dev/null | grep -q "Powered: yes" && BT_STAT="on" || BT_STAT="off"
    BT_DEV=$(bluetoothctl devices Connected 2>/dev/null | awk '{for(i=3;i<=NF;i++) printf $i" "; print ""; exit}' | sed 's/ *$//')
    [ -z "$BT_DEV" ] && BT_DEV="None"
}

update_perf() {
    PERF=$(powerprofilesctl get 2>/dev/null || echo "balanced")
}

# ==========================================
# GESTIÓN DE EMISIÓN DE ESTADO
# ==========================================
LAST_STATE=""
emit_state() {
    CURRENT="${CAP}|${STAT}|${VOL}|${SSID}|${SIGNAL}|${FREQ}|${BT_STAT}|${BT_DEV}|${PERF}|${DND}|${COUNT}|${MUTE}|${SINK_DESC}|0|0"
    # Solo imprimimos si algo ha cambiado realmente
    if [ "$CURRENT" != "$LAST_STATE" ]; then
        echo "$CURRENT"
        LAST_STATE="$CURRENT"
    fi
}

# --- Carga inicial al arrancar ---
update_bat; update_vol; update_net; update_bt; update_perf
emit_state

# ==========================================
# MONITORES DE EVENTOS (NUEVO CORAZÓN)
# ==========================================
# Estos procesos se envían a segundo plano. Simplemente escuchan al 
# sistema nativamente y "empujan" una palabra clave al FIFO cuando algo pasa.

# 1. Volumen (Pipewire/PulseAudio) - ¡Respuesta instántanea sin polling!
( pactl subscribe 2>/dev/null | grep --line-buffered "sink" | while read -r _; do echo "VOL" >&3; done ) &

# 2. Wi-Fi y Red (NetworkManager) - Altera al instante si pierdes o ganas conexión
( nmcli monitor 2>/dev/null | while read -r _; do echo "NET" >&3; done ) &

# 3. Bluetooth (DBus) - Detecta si enciendes el BT o conectas unos cascos
( dbus-monitor --system "type='signal',interface='org.freedesktop.DBus.Properties',path_namespace='/org/bluez'" 2>/dev/null | grep --line-buffered "PropertiesChanged" | while read -r _; do echo "BT" >&3; done ) &

# 4. Batería (Udev) - Detecta al milisegundo si enchufas/desenchufas el cargador
( udevadm monitor --subsystem-match=power_supply 2>/dev/null | grep --line-buffered "change" | while read -r _; do echo "BAT" >&3; done ) &

# 5. Latido de Respaldo (TICK)
# Como la señal Wi-Fi o los saltos del 1% de batería a veces no emiten un evento agresivo,
# hacemos un chequeo silencioso cada 30 segundos en lugar de cada 2.
( while true; do sleep 30; echo "TICK" >&3; done ) &

# Limpiamos todos los subprocesos de fondo y el FIFO si se cierra Quickshell
trap 'kill $(jobs -p) 2>/dev/null; exec 3>&-; rm -f "$FIFO"' EXIT

# ==========================================
# BUCLE PRINCIPAL (BLOQUEANTE = 0% CPU)
# ==========================================
# El comando 'read' paraliza la ejecución del script por completo. 
# Solo despierta cuando llega un evento de uno de los 5 monitores de arriba.
while read -r event <&3; do
    case "$event" in
        "VOL") update_vol ;;
        "NET") update_net ;;
        "BT")  update_bt ;;
        "BAT") update_bat ;;
        "TICK") update_bat; update_net; update_bt; update_perf ;;
    esac
    
    emit_state
done