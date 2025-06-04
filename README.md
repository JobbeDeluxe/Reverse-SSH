## 🔁 Reverse SSH Setup Script

Dieses Bash-Skript richtet auf einem Linux-Client (z.\u202fB. Raspberry Pi) automatisch einen **Reverse-SSH-Tunnel** zu einem zentralen Server ein. Dadurch ist der Client selbst hinter Firewalls oder NAT erreichbar \u2013 ideal f\u00fcr Remote-Wartung, Monitoring oder Fernzugriff auf Ger\u00e4te ohne \u00f6ffentliche IP.

### 🔧 Funktionen

* F\u00fchrt alle n\u00f6tigen Schritte f\u00fcr den Reverse-SSH-Tunnel automatisiert aus:

  * SSH-Key generieren
  * Key auf den Server kopieren (via `sshpass`)
  * Freien Port auf dem Server dynamisch reservieren
  * Systemd-Service zur automatischen Tunnel-Wiederherstellung einrichten
  * Optionaler Watchdog-Service zur \u00dcberwachung und Reaktivierung bei Tunnelverlust
* Speichert alle relevanten Informationen in `/etc/reverse_ssh_config`

### 💠 Voraussetzungen

* Auf dem Client:

  * Debian-basiertes System (z.\u202fB. Raspberry Pi OS)
  * Root-Rechte (z.\u202fB. via `sudo`)
  * `sshpass` (wird bei Bedarf automatisch installiert)
* Auf dem Server:

  * Ein Linux-SSH-Server
  * Schreibrechte im Home-Verzeichnis des Benutzerkontos (z.\u202fB. `~/rpi_ports/`)
  * Passwortbasierte SSH-Authentifizierung erlaubt (f\u00fcr den ersten Zugriff)

### 🚀 Anwendung

```bash
sudo ./setup_reverse_ssh.sh
```

Das Skript fragt nach Serverdomain, SSH-Benutzer und Passwort, erledigt dann automatisch den Rest und aktiviert den Tunnel per systemd-Service.

### 📦 Ergebnis

* Der Client ist \u00fcber `ssh -p <zugewiesener Port> <user>@<server>` erreichbar.
* Tunnel wird bei Verbindungsverlust automatisch neu gestartet.
* Protokollierung und R\u00fcckfallmechanismus via systemd-Timer enthalten.
