#!/bin/bash
set -euo pipefail

# === Zentrale Konfigurationsdatei ===
CONFIG_FILE="/etc/reverse_ssh_config"
declare -A CONFIG

# Funktion zum Laden der Konfigurationsdatei
load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    while IFS='=' read -r key value; do
      key=$(echo "$key" | xargs)
      value=$(echo "$value" | xargs)
      CONFIG["$key"]="$value"
    done < "$CONFIG_FILE"
  fi
}

# Funktion zum Speichern der Konfiguration
save_config() {
  : > "$CONFIG_FILE"
  for key in "${!CONFIG[@]}"; do
    echo "$key=${CONFIG[$key]}" >> "$CONFIG_FILE"
  done
}

# === Initiale Pfade und Werte ===
DEFAULT_SERVER="your.server.domain"
DEFAULT_SERVER_USER="youruser"
DEFAULT_LOCAL_USER="pi"
PORT_BASE=22000
PORT_MAX=22999

# === Verzeichnisse vorbereiten ===
mkdir -p /run/sshd
chmod 755 /run/sshd

# === Root-Prüfung ===
if [ "$EUID" -ne 0 ]; then
  echo "Bitte als root ausführen (z.B. sudo $0)." >&2
  exit 1
fi

# === Abfragen ===
read -p "Server-Domain [$DEFAULT_SERVER]: " SERVER
SERVER=${SERVER:-$DEFAULT_SERVER}
read -p "Server-User [$DEFAULT_SERVER_USER]: " SERVER_USER
SERVER_USER=${SERVER_USER:-$DEFAULT_SERVER_USER}
read -p "Lokaler User für Tunnel [$DEFAULT_LOCAL_USER]: " LOCAL_USER
LOCAL_USER=${LOCAL_USER:-$DEFAULT_LOCAL_USER}
read -s -p "Passwort für $SERVER_USER@$SERVER: " SERVER_PASS
echo ""

# === sshpass installieren ===
if ! command -v sshpass >/dev/null; then
  apt-get update && apt-get install -y sshpass
fi

# === SSH-Key erzeugen ===
KEYFILE="/home/$LOCAL_USER/.ssh/id_rsa"
if [ ! -f "$KEYFILE" ]; then
  sudo -u "$LOCAL_USER" ssh-keygen -t rsa -b 4096 -N "" -f "$KEYFILE"
fi

# === Key auf Server kopieren ===
sshpass -p "$SERVER_PASS" \
  ssh-copy-id -o StrictHostKeyChecking=accept-new \
  -i "$KEYFILE.pub" "$SERVER_USER@$SERVER"

# === Hostname & Client-ID ===
CLIENT_HOSTNAME=$(hostname)
load_config

if [ -z "${CONFIG[CLIENT_ID]:-}" ]; then
  UNIQUE_SOURCE="$(date +%s)-$CLIENT_HOSTNAME-$(curl -s https://ipinfo.io/ip || echo noip)"
  CLIENT_ID=$(echo "$UNIQUE_SOURCE" | sha256sum | cut -c1-16)
  CONFIG[CLIENT_ID]="$CLIENT_ID"
else
  CLIENT_ID="${CONFIG[CLIENT_ID]}"
fi

# === Port vom Server holen ===
echo "Hole freien Port vom Server..."
PORT=$(sshpass -p "$SERVER_PASS" ssh -o StrictHostKeyChecking=accept-new "$SERVER_USER@$SERVER" bash -s <<EOF
used_file=\$HOME/rpi_ports/used_ports.txt
connections_file=\$HOME/rpi_connections.txt
mkdir -p \$(dirname "\$used_file")
touch "\$used_file" "\$connections_file"
# Freien Port finden
for ((port=$PORT_BASE; port<=$PORT_MAX; port++)); do
  if ! grep -q ":\\\$port" "\$used_file"; then
    echo \\\$port >> "\$used_file"
    tmp_file=\$(mktemp)
    grep -v "^.*(\$CLIENT_ID).*" "\$connections_file" > "\$tmp_file" || true
    echo "$CLIENT_ID ($CLIENT_HOSTNAME) - Port \\\$port - \$(date)" >> "\$tmp_file"
    mv "\$tmp_file" "\$connections_file"
    echo \\\$port
    break
  fi
done
EOF
)

if [ -z "$PORT" ]; then
  echo "Fehler: kein freier Port gefunden." >&2
  exit 2
fi

# === Konfiguration speichern ===
CONFIG[CLIENT_HOSTNAME]="$CLIENT_HOSTNAME"
CONFIG[SERVER]="$SERVER"
CONFIG[SERVER_USER]="$SERVER_USER"
CONFIG[LOCAL_USER]="$LOCAL_USER"
CONFIG[PORT]="$PORT"
save_config

# === autossh prüfen ===
USE_AUTOSSH="no"
if apt-get install -y autossh; then
  if command -v autossh >/dev/null; then
    USE_AUTOSSH="yes"
  fi
fi

# === Service-Datei erzeugen ===
SERVICE_NAME="reverse_ssh_tunnel_$LOCAL_USER"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
EXEC_CMD="/usr/bin/ssh -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=accept-new -N -R $PORT:localhost:22 $SERVER_USER@$SERVER"
if [ "$USE_AUTOSSH" = "yes" ]; then
  EXEC_CMD="/usr/lib/autossh/autossh -M 0 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -N -R $PORT:localhost:22 $SERVER_USER@$SERVER"
fi

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Reverse SSH Tunnel for $LOCAL_USER
After=network.target

[Service]
User=$LOCAL_USER
ExecStart=$EXEC_CMD
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# === Watchdog-Skript ===
WATCHDOG_SCRIPT="/usr/local/bin/check_reverse_ssh.sh"
cat > "$WATCHDOG_SCRIPT" <<EOF
#!/bin/bash
CONFIG_FILE="$CONFIG_FILE"
source <(grep = "\$CONFIG_FILE")
SERVICE="reverse_ssh_tunnel_\$LOCAL_USER"
if journalctl -u "\$SERVICE" | grep -q "remote port forwarding failed"; then
  systemctl restart "\$SERVICE"
  exit 0
fi
PORT=\$PORT
if [[ -n "\$PORT" && -z \$(ss -tnp | grep ":\$PORT") ]]; then
  systemctl restart "\$SERVICE"
fi
EOF
chmod +x "$WATCHDOG_SCRIPT"

# === Timer erstellen ===
TIMER_FILE="/etc/systemd/system/reverse_ssh_watchdog.timer"
SERVICE_WATCHDOG_FILE="/etc/systemd/system/reverse_ssh_watchdog.service"

cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Watchdog für Reverse SSH Tunnel

[Timer]
OnBootSec=5min
OnUnitActiveSec=15min
Unit=reverse_ssh_watchdog.service

[Install]
WantedBy=timers.target
EOF

cat > "$SERVICE_WATCHDOG_FILE" <<EOF
[Unit]
Description=Check und ggf. Restart für Reverse SSH Tunnel
After=network.target

[Service]
Type=oneshot
ExecStart=$WATCHDOG_SCRIPT
EOF

# === Aktivieren ===
systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME"
systemctl enable --now reverse_ssh_watchdog.timer

# === Abschlussmeldung ===
echo "Setup abgeschlossen!"
echo "Client-ID: $CLIENT_ID"
echo "→ SSH Port: $PORT"
echo "→ Service: $SERVICE_NAME"
echo "→ Konfiguration: $CONFIG_FILE"
