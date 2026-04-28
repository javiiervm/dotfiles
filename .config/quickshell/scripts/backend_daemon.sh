#!/usr/bin/env bash

# Valores iniciales
SSID="Disconnected"; SIGNAL="0"; FREQ="0"; BT_DEV="None"; SINK_DESC="Speakers"; DND="false"; COUNT="0"
counter=0
LAST_STATE="" # <- Inicializamos la variable para guardar el estado

# OPTIMIZACIÓN 1: Buscamos la ruta de la batería UNA sola vez al arrancar, no cada 2 segundos.
BAT_PATH=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -n 1)

while true; do
    # 1. LECTURAS RÁPIDAS (Cada 2 segundos)
    if [ -n "$BAT_PATH" ]; then
        # OPTIMIZACIÓN 2: Usar 'read' nativo de bash en lugar de 'cat' evita crear subprocesos
        read CAP < "$BAT_PATH/capacity" 2>/dev/null || CAP=0
        read STAT < "$BAT_PATH/status" 2>/dev/null || STAT="Unknown"
    else
        CAP=100; STAT="Unknown"
    fi
    
    # Volumen (Optimizando la extracción de texto)
    VOL_RAW=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || echo "Volume: 0.00")
    [[ "$VOL_RAW" == *MUTED* ]] && MUTE="true" || MUTE="false"
    VOL_STR=${VOL_RAW#* }
    VOL_STR=${VOL_STR% \[MUTED\]}
    VOL=$(awk -v v="$VOL_STR" 'BEGIN {print int(v * 100)}')
    
    # 2. LECTURAS MEDIAS (Cada ~8s)
    if (( counter % 4 == 0 )); then
        bluetoothctl show 2>/dev/null | grep -q "Powered: yes" && BT_STAT="on" || BT_STAT="off"
        PERF=$(powerprofilesctl get 2>/dev/null || echo "balanced")
    fi

    # 3. LECTURAS LENTAS (Cada ~20s)
    if (( counter % 10 == 0 )); then
        # OPTIMIZACIÓN 3: Una sola llamada a nmcli para sacar SSID, Señal y Frecuencia a la vez
        WIFI_INFO=$(nmcli -t -f ACTIVE,SSID,SIGNAL,FREQ device wifi 2>/dev/null | awk -F: '$1=="yes" {print $2":"$3":"$4; exit}')
        if [ -n "$WIFI_INFO" ]; then
            SSID=$(echo "$WIFI_INFO" | cut -d: -f1)
            SIGNAL=$(echo "$WIFI_INFO" | cut -d: -f2)
            FREQ_RAW=$(echo "$WIFI_INFO" | cut -d: -f3)
            FREQ=$(echo "$FREQ_RAW" | tr -dc '0-9')
        else
            SSID="Disconnected"; SIGNAL="0"; FREQ="0"
        fi
        
        BT_DEV=$(bluetoothctl devices Connected 2>/dev/null | awk '{for(i=3;i<=NF;i++) printf $i" "; print ""; exit}' | sed 's/ *$//')
        [ -z "$BT_DEV" ] && BT_DEV="None"
        
        SINK_DESC=$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk -F'"' '/node.description/ {print $2; exit}')
        [ -z "$SINK_DESC" ] && SINK_DESC="Speakers"
        
        # OPTIMIZACIÓN 4: Eliminamos swaync-client. Tu notif_daemon.py ya hace esto por DBus a coste 0.
        DND="false"
        COUNT="0"
    fi

    # --- NUEVA LÓGICA DE OPTIMIZACIÓN ---
    # Guardamos todo el estado actual en una variable de texto
    CURRENT_STATE="${CAP}|${STAT}|${VOL}|${SSID}|${SIGNAL}|${FREQ}|${BT_STAT}|${BT_DEV}|${PERF}|${DND}|${COUNT}|${MUTE}|${SINK_DESC}|0|0"
    
    # Comparamos: si es diferente al estado anterior, lo enviamos a QML. Si no, silencio absoluto.
    if [ "$CURRENT_STATE" != "$LAST_STATE" ]; then
        echo "$CURRENT_STATE"
        LAST_STATE="$CURRENT_STATE"
    fi
    # ------------------------------------
    
    sleep 2
    counter=$((counter + 1))
    [ $counter -ge 20 ] && counter=0
done