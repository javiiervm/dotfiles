#!/bin/bash

# 1. Matar procesos y limpiar el sistema
killall -9 quickshell swaync dunst mako 2>/dev/null
pkill -9 -f "backend_daemon.sh"
pkill -9 -f "sys_backend.sh"
pkill -9 -f "backend.sh"
pkill -9 -f "notif_daemon.py"
pkill -f "qs -c overview"
rm -f /tmp/qs_notif_cmd

# 2. EL TRUCO MAESTRO: Crear un falso swaync-client y dunstctl
# Esto evita que tu backend_daemon.sh se quede colgado buscando programas muertos
mkdir -p /tmp/fake_bin

cat << 'EOF' > /tmp/fake_bin/swaync-client
#!/bin/bash
if [[ "$1" == "-c" || "$1" == "--count" ]]; then echo "0"; exit 0; fi
if [[ "$1" == "-D" || "$1" == "--dnd" ]]; then echo "false"; exit 0; fi
echo "0"
EOF

cat << 'EOF' > /tmp/fake_bin/dunstctl
#!/bin/bash
echo "0"
EOF

chmod +x /tmp/fake_bin/swaync-client
chmod +x /tmp/fake_bin/dunstctl

# Inyectamos los falsos programas en la ruta principal
export PATH="/tmp/fake_bin:$PATH"

# 3. Permisos
chmod +x /home/javier/.config/quickshell/scripts/*.sh 2>/dev/null
chmod +x /home/javier/.config/quickshell/scripts/*.py 2>/dev/null

# 4. Lanzar Quickshell
sleep 0.5
qs -c overview &
export QML_XHR_ALLOW_FILE_READ=1
nohup quickshell > /dev/null 2>&1 &

exit