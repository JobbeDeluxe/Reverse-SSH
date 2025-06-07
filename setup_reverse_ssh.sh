#!/bin/bash
set -euo pipefail

# === Fehlerausgabe-Funktion ===
error_exit() {
  echo "Fehler: $1" >&2
  exit 1
}

# === Konfiguration ===
CONFIG_FILE="/etc/reverse_ssh_config"
declare -A CONFIG
PORT_BASE=22000
PORT_MAX=22999

# === Konfiguration laden ===
load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    while IFS='=' read -r key value; do
      key=$(echo "$key" | xargs)
      value=$(echo "$value" | xargs)
      CONFIG["$key"]="$value"
    done < "$CONFIG_FILE"
  fi
}

# === Konfiguration speichern ===
save_config() {
  : > "$CONFIG_FILE"
  for key in "${!CONFIG[@]}"; do
    echo "$key=${CONFIG[$key]}" >> "$CONFIG_FILE"
  done
}

# === Root-Prüfung ===
if [ "$EUID" -ne 0 ]; then
  error_exit "Bitte als root ausführen (z.B. sudo $0)."
fi

# === Optional: SSH-Verzeichnis vorbereiten (für manche Systeme nötig) ===
if [ ! -d /run/sshd ]; then
  echo "Erstelle /run/sshd (falls benötigt)..."
  mkdir -p /run/sshd
  chmod 755 /run/sshd
fi

# === Abfragen ===
read -p "Server-Domain [your.server.domain]: " SERVER
SERVER=${SERVER:-your.server.domain}
read -p "Server-User [youruser]: " SERVER_USER
SERVER_USER=${SERVER_USER:-youruser}
read -p "Lokaler User für Tunnel [pi]: " LOCAL_USER
LOCAL_USER=${LOCAL_USER:-pi}
read -s -p "Passwort für $SERVER_USER@$SERVER: " SERVER_PASS
echo ""
read -p "Watchdog-Intervall in Minuten [15]: " INTERVAL
INTERVAL=${INTERVAL:-15}

# === Programm-Prüfungen ===
for cmd in sshpass ssh ssh-copy-id curl systemctl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Installiere fehlendes Paket: $cmd"
    apt-get update && apt-get install -y "$cmd"
  fi
done

# === SSH-Server prüfen ===
if ! systemctl is-active ssh &>/dev/null; then
  error_exit "Der lokale SSH-Server läuft nicht."
fi

# === Schlüssel erzeugen ===
USER_HOME=$(eval echo "~$LOCAL_USER")
KEYFILE="$USER_HOME/.ssh/id_rsa"
if [ ! -f "$KEYFILE" ]; then
  sudo -u "$LOCAL_USER" ssh-keygen -t rsa -b 4096 -N "" -f "$KEYFILE" || error_exit "SSH-Key konnte nicht erzeugt werden."
fi

# === Key kopieren ===
sshpass -p "$SERVER_PASS" \
  ssh-copy-id -o StrictHostKeyChecking=accept-new \
  -i "$KEYFILE.pub" "$SERVER_USER@$SERVER" || error_exit "ssh-copy-id fehlgeschlagen."

# === Client-ID ===
CLIENT_HOSTNAME=$(hostname)
load_config

if [ -z "${CONFIG[CLIENT_ID]:-}" ]; then
  UNIQUE_SOURCE="$(date +%s)-$CLIENT_HOSTNAME-$(curl -s https://ipinfo.io/ip || echo noip)"
  CLIENT_ID=$(echo "$UNIQUE_SOURCE" | sha256sum | cut -c1-16)
  CONFIG[CLIENT_ID]="$CLIENT_ID"
  CONFIG[CLIENT_HOSTNAME]="$CLIENT_HOSTNAME"
  save_config  # ⬅️ direkt nach Generierung speichern!
else
  CLIENT_ID="${CONFIG[CLIENT_ID]}"
fi

# === Port vom Server holen und Dateien aufräumen ===
echo "Hole freien Port vom Server..."
PORT=$(sshpass -p "$SERVER_PASS" ssh -o StrictHostKeyChecking=accept-new "$SERVER_USER@$SERVER" bash -s -- "$CLIENT_ID" "$CLIENT_HOSTNAME" <<'EOF'
used_file="$HOME/rpi_ports/used_ports.txt"
connections_file="$HOME/rpi_connections.txt"
mkdir -p "$(dirname "$used_file")"
touch "$used_file" "$connections_file"

CLIENT_ID="$1"
CLIENT_HOSTNAME="$2"
PORT_BASE=22000
PORT_MAX=22999

# Alte Einträge mit CLIENT_ID aus connections_file entfernen
grep -v "$CLIENT_ID" "$connections_file" > "${connections_file}.tmp" || true
mv "${connections_file}.tmp" "$connections_file"

# Ports aus connections_file (ohne Einträge mit CLIENT_ID) sammeln
USED_PORTS=$(grep -v "$CLIENT_ID" "$connections_file" | grep -o "Port [0-9]\+" | grep -o "[0-9]\+" | sort -n | uniq)

# Freien Port suchen
PORT=$PORT_BASE
while echo "$USED_PORTS" | grep -q "^$PORT\$"; do
  ((PORT++))
  if [ "$PORT" -gt "$PORT_MAX" ]; then
    echo "Kein freier Port verfügbar." >&2
    exit 1
  fi
done

# Neue Verbindung in connections_file eintragen
echo "$CLIENT_ID ($CLIENT_HOSTNAME) - Port $PORT - $(date)" >> "$connections_file"

# used_ports.txt aktualisieren: alte Ports des Clients entfernen + neuen Port hinzufügen
grep -v "^$PORT\$" "$used_file" | grep -v -f <(echo "$PORT") > "${used_file}.tmp" || true
echo "$PORT" >> "${used_file}.tmp"
sort -n -u "${used_file}.tmp" > "$used_file"
rm "${used_file}.tmp"

echo "$PORT"
EOF
)

if [ -z "$PORT" ]; then
  echo "Fehler: kein freier Port gefunden." >&2
  exit 2
fi


if [ -z "$PORT" ]; then
  error_exit "Kein freier Port gefunden."
fi

# === Konfiguration speichern ===
CONFIG[CLIENT_HOSTNAME]="$CLIENT_HOSTNAME"
CONFIG[SERVER]="$SERVER"
CONFIG[SERVER_USER]="$SERVER_USER"
CONFIG[LOCAL_USER]="$LOCAL_USER"
CONFIG[PORT]="$PORT"
CONFIG[INTERVAL]="$INTERVAL"
save_config

# === autossh prüfen ===
USE_AUTOSSH="no"
if apt-get install -y autossh && command -v autossh >/dev/null; then
  USE_AUTOSSH="yes"
  AUTOSSH_PATH=$(command -v autossh)
fi

# === systemd Service erstellen ===
SERVICE_NAME="reverse_ssh_tunnel_$LOCAL_USER"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

SSH_CMD="ssh -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -N -R $PORT:localhost:22 $SERVER_USER@$SERVER"
[ "$USE_AUTOSSH" = "yes" ] && SSH_CMD="$AUTOSSH_PATH -M 0 $SSH_CMD"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Reverse SSH Tunnel for $LOCAL_USER
After=network.target

[Service]
User=$LOCAL_USER
ExecStart=$SSH_CMD
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# === Watchdog ===
WATCHDOG_SCRIPT="/usr/local/bin/check_reverse_ssh.sh"
cat > "$WATCHDOG_SCRIPT" <<'EOF'
#!/bin/bash
CONFIG_FILE="/etc/reverse_ssh_config"
declare -A CONFIG
while IFS='=' read -r key value; do CONFIG["$key"]="$value"; done < "$CONFIG_FILE"
SERVICE="reverse_ssh_tunnel_${CONFIG[LOCAL_USER]}"
PORT="${CONFIG[PORT]}"
if journalctl -u "$SERVICE" | grep -q "remote port forwarding failed"; then
  systemctl restart "$SERVICE"
  exit 0
fi
if [[ -n "$PORT" && -z $(ss -tnp | grep ":$PORT") ]]; then
  systemctl restart "$SERVICE"
fi
EOF
chmod +x "$WATCHDOG_SCRIPT"

# === Watchdog Timer ===
TIMER_FILE="/etc/systemd/system/reverse_ssh_watchdog.timer"
SERVICE_WATCHDOG_FILE="/etc/systemd/system/reverse_ssh_watchdog.service"

cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Watchdog für Reverse SSH Tunnel

[Timer]
OnBootSec=5min
OnUnitActiveSec=${INTERVAL}min
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
echo "✅ Setup abgeschlossen!"
echo "Client-ID: $CLIENT_ID"
echo "→ SSH Port: $PORT"
echo "→ Service: $SERVICE_NAME"
echo "→ Konfiguration: $CONFIG_FILE"
echo "→ Watchdog-Intervall: ${INTERVAL}min"
