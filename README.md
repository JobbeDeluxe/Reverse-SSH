🔁 Reverse SSH Setup Script
Dieses Bash-Skript richtet auf einem Linux-Client (z. B. Raspberry Pi) automatisch einen Reverse-SSH-Tunnel zu einem zentralen Server ein. Dadurch ist der Client selbst hinter Firewalls oder NAT erreichbar – ideal für Remote-Wartung, Monitoring oder Fernzugriff auf Geräte ohne öffentliche IP.

🔧 Funktionen
Führt alle nötigen Schritte für den Reverse-SSH-Tunnel automatisiert aus:

SSH-Key generieren

Key auf den Server kopieren (via sshpass)

Freien Port auf dem Server dynamisch reservieren

Systemd-Service zur automatischen Tunnel-Wiederherstellung einrichten

Optionaler Watchdog-Service zur Überwachung und Reaktivierung bei Tunnelverlust

Speichert alle relevanten Informationen in /etc/reverse_ssh_config

🛠 Voraussetzungen
Auf dem Client:

Debian-basiertes System (z. B. Raspberry Pi OS)

Root-Rechte (z. B. via sudo)

sshpass (wird bei Bedarf automatisch installiert)

Auf dem Server:

Ein Linux-SSH-Server

Schreibrechte im Home-Verzeichnis des Benutzerkontos (z. B. ~/rpi_ports/)

Passwortbasierte SSH-Authentifizierung erlaubt (für den ersten Zugriff)

🚀 Anwendung
bash
Kopieren
Bearbeiten
sudo ./setup_reverse_ssh.sh
Das Skript fragt nach Serverdomain, SSH-Benutzer und Passwort, erledigt dann automatisch den Rest und aktiviert den Tunnel per systemd-Service.

📦 Ergebnis
Der Client ist über ssh -p <zugewiesener Port> <user>@<server> erreichbar.

Tunnel wird bei Verbindungsverlust automatisch neu gestartet.

Protokollierung und Rückfallmechanismus via systemd-Timer enthalten.
