#!/bin/bash
set -euo pipefail

# Serverdaten
CONNECTIONS_FILE="$HOME/rpi_connections.txt"
STATUS_DIR="$HOME/.client_status"
LOG_FILE="$STATUS_DIR/offline_log.txt"
mkdir -p "$STATUS_DIR"

# Prüfen ob Datei existiert
if [ ! -f "$CONNECTIONS_FILE" ]; then
  echo "❌ Verbindungsdatei nicht gefunden: $CONNECTIONS_FILE"
  exit 1
fi

# Funktion zur Portprüfung mit /dev/tcp
check_port() {
  local port=$1
  if timeout 1 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/$port" 2>/dev/null; then
    return 0
  else
    return 1
  fi
}

# Funktion: Status aktualisieren
update_offline_log() {
  local id="$1"
  local status="$2"
  local today=$(date +%Y-%m-%d)

  mkdir -p "$STATUS_DIR/$id"
  local logfile="$STATUS_DIR/$id/status.log"

  if [[ "$status" == "OFFLINE" ]]; then
    echo "$today OFFLINE" >> "$logfile"
  else
    echo "$today ONLINE" >> "$logfile"
  fi
}

# Funktion: Ist Client tot?
is_dead_client() {
  local id="$1"
  local logfile="$STATUS_DIR/$id/status.log"

  if [[ ! -f "$logfile" ]]; then
    return 1
  fi

  # Nur letzte 90 Tage betrachten
  local days=()
  while IFS= read -r line; do
    local d=$(echo "$line" | awk '{print $1}')
    local s=$(echo "$line" | awk '{print $2}')
    days+=("$d:$s")
  done < <(tail -n 300 "$logfile")

  declare -A seen
  local streak=0
  local last_date=""
  for entry in "${days[@]}"; do
    local d=${entry%%:*}
    local s=${entry##*:}
    seen["$d"]+="$s "
  done

  for i in {0..90}; do
    local day=$(date -d "$i days ago" +%Y-%m-%d)
    local statuses=${seen[$day]:-}
    if [[ "$statuses" == *"ONLINE"* ]]; then
      streak=0
    elif [[ "$statuses" == *"OFFLINE"* ]]; then
      ((streak++))
    else
      streak=0
    fi

    if (( streak >= 5 )); then
      return 0
    fi
  done

  return 1
}

# Clients extrahieren und Status prüfen
CLIENT_LINES=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue

  PORT=$(echo "$line" | grep -o "Port [0-9]\+" | grep -o "[0-9]\+")
  HOST=$(echo "$line" | grep -o "([^)]*)" | sed 's/[()]//g')
  CLIENT_ID=$(echo "$line" | awk '{print $1}')

  if [[ -n "$PORT" ]]; then
    if check_port "$PORT"; then
      STATUS="ONLINE"
    else
      STATUS="OFFLINE"
    fi

    update_offline_log "$CLIENT_ID" "$STATUS"

    if is_dead_client "$CLIENT_ID"; then
      STATUS="❌ DEAD"
    fi

    CLIENT_LINES+=("$line [$STATUS]")
  fi

done < "$CONNECTIONS_FILE"

if [ "${#CLIENT_LINES[@]}" -eq 0 ]; then
  echo "Keine aktiven Clients gefunden."
  exit 1
fi

# Auswahl anzeigen
echo ""
echo "Verfügbare Clients:"
for i in "${!CLIENT_LINES[@]}"; do
  echo "[$((i+1))] ${CLIENT_LINES[$i]}"
  done
echo "[0] Beenden"
echo ""

# Auswahl abfragen
while true; do
  read -p "Mit welchem Client verbinden? [1-${#CLIENT_LINES[@]} / 0=exit]: " INDEX
  if [[ "$INDEX" == "0" ]]; then
    echo "Verbindung abgebrochen."
    exit 0
  fi
  if [[ "$INDEX" =~ ^[0-9]+$ ]] && (( INDEX >= 1 && INDEX <= ${#CLIENT_LINES[@]} )); then
    SELECTED_INDEX=$((INDEX-1))
    break
  else
    echo "Ungültige Auswahl: Bitte Zahl zwischen 1 und ${#CLIENT_LINES[@]} eingeben (0 zum Beenden)"
  fi
  done

# Auswahl verarbeiten
SELECTED="${CLIENT_LINES[$SELECTED_INDEX]}"
PORT=$(echo "$SELECTED" | grep -o "Port [0-9]\+" | grep -o "[0-9]\+")
HOST=$(echo "$SELECTED" | grep -o "([^)]*)" | sed 's/[()]//g')
CLIENT_ID=$(echo "$SELECTED" | awk '{print $1}')

# Verbindung aufbauen
echo "Verbinde mit $HOST (ID: $CLIENT_ID) auf Port $PORT..."
ssh -o StrictHostKeyChecking=accept-new -p "$PORT" "127.0.0.1"
