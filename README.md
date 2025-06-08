Client Seite:
====================================
## 🔁 Reverse SSH Setup Script

Dieses Bash-Skript richtet auf einem Linux-Client (z. B. Raspberry Pi) automatisch einen Reverse-SSH-Tunnel zu einem zentralen Server ein. Dadurch ist der Client selbst hinter Firewalls oder NAT erreichbar – ideal für Remote-Wartung, Monitoring oder Fernzugriff auf Geräte ohne öffentliche IP.

### 🔧 Funktionen

* Führt alle nötigen Schritte für den Reverse-SSH-Tunnel automatisiert aus:

  * SSH-Key generieren
  * Key auf den Server kopieren (via `sshpass`)
  * Freien Port auf dem Server dynamisch reservieren
  * Systemd-Service zur automatischen Tunnel-Wiederherstellung einrichten
  * Optionaler Watchdog-Service zur überwachung und Reaktivierung bei Tunnelverlust
* Speichert alle relevanten Informationen in `/etc/reverse_ssh_config`

### 💠 Voraussetzungen

* Auf dem Client:

  * Debian-basiertes System (z.B. Raspberry Pi OS)
  * Root-Rechte (z.B. via `sudo`)
  * `sshpass` (wird bei Bedarf automatisch installiert)
* Auf dem Server:

  * Ein Linux-SSH-Server
  * Schreibrechte im Home-Verzeichnis des Benutzerkontos (z.B. `~/rpi_ports/`)
  * Passwortbasierte SSH-Authentifizierung erlaubt (für den ersten Zugriff)

### 🚀 Anwendung

```bash
sudo ./setup_reverse_ssh.sh
```

Das Skript fragt nach Serverdomain, SSH-Benutzer und Passwort, erledigt dann automatisch den Rest und aktiviert den Tunnel per systemd-Service.

### 📦 Ergebnis

* Der Client ist über `ssh -p <zugewiesener Port> <user>@<server>` erreichbar.
* Tunnel wird bei Verbindungsverlust automatisch neu gestartet.
* Protokollierung und Rückfallmechanismus via systemd-Timer enthalten.



Server Seite:
====================================
Connect-Skript für Reverse-SSH-Server
====================================

Dieses Skript dient dazu, sich bequem mit einem der verbundenen Reverse-SSH-Clients zu verbinden.
Es liest die Datei `rpi_connections.txt`, in der alle bekannten Clients mit zugewiesenem Reverse-Port
gespeichert sind, und bietet eine interaktive Auswahl an.

Funktionsweise
--------------

- Liest die Datei `~/rpi_connections.txt`, die von den Clients beim Verbindungsaufbau auf dem Server automatisch gepflegt wird.
- Zeigt eine nummerierte Liste aller aktiven Clients an (Hostname, Port, Client-ID).
- Nach Auswahl eines Clients wird eine SSH-Verbindung zum jeweiligen Reverse-Port auf `127.0.0.1` aufgebaut.

Voraussetzungen
---------------

- Die Datei `rpi_connections.txt` muss im Home-Verzeichnis des Servers liegen und regelmäßig durch die Client-Installationsskripte aktualisiert werden.
- Der Reverse-SSH-Tunnel des gewünschten Clients muss aktiv sein (z. B. über `autossh` oder systemd-Service).
- SSH muss lokal auf dem Server verfügbar sein.

Nutzung
-------
```bash
bash ./connect_client.sh
```

Anschließend erfolgt eine interaktive Auswahl, z. B.:

    Verfügbare Clients:
    [1] 12ab34cd56ef78gh (raspberrypi1) - Port 22001 - 2025-06-04 18:00:00 [ONLINE]
    [2] 90ef12ab34cd56gh (raspberrypi2) - Port 22002 - 2025-06-04 18:01:00 [OFFLINE]
    [0] Beenden

    Mit welchem Client verbinden? [1-2 / 0=exit]:

Nach Auswahl eines Eintrags wird automatisch eine SSH-Verbindung zu `127.0.0.1` über den angegebenen Port aufgebaut.

Beispiel
--------

Verbindung zu einem Client auf Port 22001:

    ssh -p 22001 127.0.0.1

Dieses Skript übernimmt das automatisch für dich nach Auswahl.

Hinweise
--------

- Wenn keine Clients verbunden sind oder die Datei nicht existiert, wird ein entsprechender Hinweis angezeigt.
- Die Datei `rpi_connections.txt` sollte ausschließlich durch das Reverse-SSH-Setup-Skript gepflegt werden und keine manuellen Einträge enthalten.
