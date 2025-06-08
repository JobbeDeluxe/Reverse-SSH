#!/bin/bash
set -euo pipefail

# Serverdaten
CONNECTIONS_FILE="$HOME/rpi_connections.txt"

# Prüfen ob Datei existiert
if [ ! -f "$CONNECTIONS_FILE" ]; then
  echo "❌ Verbindungsdatei nicht gefunden: $CONNECTIONS_FILE"
  exit 1
fi

# Funktion zur Portprüfung mit /dev/tcp
check_port() {
  local port=$1
  # Verwende Timeout von 1 Sekunde
  if timeout 1 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/$port" 2>/dev/null; then
    return 0
  else
    return 1
  fi
}

# Clients extrahieren und Status prüfen
CLIENT_LINES=()
while IFS= read -r line; do
  if [[ -z "$line" ]]; then
    continue
  fi
  
  PORT=$(echo "$line" | grep -o "Port [0-9]\+" | grep -o "[0-9]\+")
  HOST=$(echo "$line" | grep -o "([^)]*)" | sed 's/[()]//g')
  CLIENT_ID=$(echo "$line" | awk '{print $1}')
  
  if [[ -n "$PORT" ]]; then
    if check_port "$PORT"; then
      STATUS="[ONLINE]"
    else
      STATUS="[OFFLINE]"
    fi
    CLIENT_LINES+=("$line $STATUS")
  fi
done < "$CONNECTIONS_FILE"

if [ "${#CLIENT_LINES[@]}" -eq 0 ]; then
  echo "Keine aktiven Clients gefunden."
  exit 1
fi

# Auswahl anzeigen (beginnend mit 1)
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
    # Korrektur für Array-Index (0-basiert)
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
