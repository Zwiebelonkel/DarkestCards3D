# Online-Testversion und Absturzlogs

Das gesamte ZIP in einen neuen Ordner entpacken und `DarkestCards.exe` starten.
Beide Spieler sollten dieselbe neue Version verwenden. Alle mitgelieferten DLLs
muessen neben der EXE bleiben. Steam muss laufen. Die Testversion verwendet die
bisherigen Spielstaende.

Die EXE laeuft ohne Godot-Editor. Der Windows-Build verwendet standardmaessig
einen Release-Export mit den passenden Release-DLLs. Die Steam-Abhaengigkeit
wird auf eine konkrete Version mit SHA-256-Pruefsummen festgelegt; Details und
Quellen stehen in `addons/godotsteam/DEPENDENCY.md`.

## Ursache des nativen Absturzes

Mit GodotSteam 4.22.1 stuerzt der Release-Prozess beim Freigeben eines
`SteamMultiplayerPeer` reproduzierbar ab. Das kann beim Verlassen einer Lobby
oder beim Beenden einer Online-Partie auftreten und setzt kein Beenden der
Anwendung voraus. Die native Probe reproduziert den Fehler bereits ohne Lobby
oder Mitspieler. Die generische Kontrollprobe mit Godots eingebautem
`MultiplayerPeerExtension` besteht unter Godot 4.4.1 sowohl im Debug- als auch
im Release-Build.

Im nativen Destruktor von GodotSteam 4.22.1 steht `close()`. Bei einer
GDExtension fuehrt dieser Aufruf ueber die Engine zurueck zum Peer, dessen
Engine-Anteil zu diesem Zeitpunkt bereits zerstoert wurde. Die vorherige
GDExtension 4.20.1 ruft stattdessen die eigene `_close()`-Implementierung auf.
Der Unterschied entstand bei der Zusammenfuehrung der Modul- und
GDExtension-Quellen am 9. August 2026. Die konkreten Quellstellen sind in der
Abhaengigkeitsdokumentation verlinkt.

Als Ersatz ist das offizielle GodotSteam-4.20.1-Paket fuer Godot 4.4+ mit
Steamworks 1.64 ausgewaehlt. Seine mitgelieferte `plugin.cfg` meldet `4.20`;
Archiv-Tag und Pruefsummen identifizieren die Version 4.20.1 eindeutig.
Das Release-Paket besteht unter Godot 4.4.1 je acht native
Erstellungs-/Freigabezyklen und Host-Verbindungszyklen, einschliesslich
Steam-Shutdown, jeweils mit Prozess-Exitcode 0. Die Pruefungen mit den
vollstaendigen Produktionsszenen bestehen ebenfalls in beiden Export-Modi.
Ein Debug-Export allein gilt
nicht als Nachweis fuer einen behobenen Release-Absturz; Debug- und
Release-DLLs werden nicht vermischt.

## Protokolle

Die Windows-EXE schreibt auch im Release-Build Engine-Fehler nach
`%APPDATA%\Godot\app_userdata\DarkestCards\logs\godot.log`.
Zusaetzliche, sofort auf die Platte geschriebene Sitzungsprotokolle liegen im
Unterordner `sessions` als `session-*.jsonl`.

Bei einem erneuten Absturz den gesamten `logs`-Ordner des betroffenen Spielers
sichern. Dazu notieren: Host, Gast oder Zuschauer; letzter sichtbarer Schritt;
und ob die andere Person gleichzeitig die Lobby verlassen hat. Ein Neustart
erzeugt weitere Dateien, behaelt aber die letzten Protokolle. Es werden maximal
acht Engine-Logs und acht Sitzungslog-Segmente zu je 512 KiB aufbewahrt.

Die Sitzungslogs enthalten:

- Engine-Version, Release-/Debug-Modus und Steam-Erweiterungsversion.
- SHA-256 der zum Build-Modus gehoerenden Windows-Steam-DLL zum Vergleich
  verteilter EXE-Pakete.
- Lobby-Erstellung, abgebrochene Anfragen, native Verbindungszustandswechsel und
  Steam-Abbruchcodes samt bereinigter Fehlerbeschreibung.
- Beginn und Ende des Verbindungsabbaus sowie Freigabe des nativen Peers.
- Spielende-Animation, Schwarzblende, Kartenbereinigung und Menue-Rueckkehr.
- Verworfene Ereignisse alter Sitzungen und den letzten gespeicherten Schritt
  vor einem unterbrochenen vorherigen Lauf.

Ein harter nativer Absturz kann GDScript umgehen. Dann ist der letzte bereits
geschriebene Schritt vorhanden, aber nicht zwingend ein nativer Stacktrace.
`exit_tree_reached` belegt nur, dass Godots Aufraeumen begonnen hat; es wird nicht
als Beweis fuer einen erfolgreichen Prozess-Exit ausgegeben.

## Behobene Ablaufprobleme

Steam-Lobby-Handler und Multiplayer-Signalhandler veraendern die Verbindung erst,
wenn die nativen Callbacks zurueckgekehrt sind. Eine monotone Sitzungskennung
verhindert, dass spaete Verbindungsereignisse oder alte Animations-Finalizer eine
spaeter gestartete Lobby beenden. Beim Schliessen des Lobby-Menues werden auch
noch laufende Beitritts-/Erstellungsanfragen abgebrochen. Eine abgebrochene
Erstellung bleibt gesperrt, bis Steam ihr Ergebnis geliefert hat, damit ein
altes Ergebnis nicht als neue Lobby akzeptiert wird. Dasselbe gilt fuer
abgebrochene Beitritte, insbesondere einen erneuten Beitritt derselben Lobby.
Einladungen bleiben waehrend dieser Wartephase vorgemerkt.

Clients erkennen den Austritt des urspruenglichen Hosts auch vor Abschluss des
P2P-Handshakes. Die automatische Steam-Lobby-Owner-Migration wird dabei nicht
als neuer Spielserver behandelt. Waehrend des Abbaus greifen Menue und
Zuschauerabfragen nicht mehr auf eine bereits getrennte Verbindung zu.

Die Tests verwenden eigene temporaere Speicherstaende. Automatisierte ENet- und
Release-Tests ersetzen keinen abschliessenden Versuch mit zwei Steam-Konten auf
den zuvor betroffenen Rechnern.

Mit dem festgelegten Steam-Paket bestehen die nativen Steam-, Lifecycle-,
Spielende- und Ersatzkarten-Pruefungen sowohl als echter Release-Export als
auch als separater Debug-Export. Alle acht Laeufe enden mit Erfolgsmarkierung
und Prozess-Exitcode 0. Die nativen Tests erstellen und schliessen jeweils
acht Host-Verbindungen. Die echten Sieg-/Niederlagen-Sequenzen wurden bereits
zusaetzlich mit gerendertem Spielfeld geprueft.

## Erneut bauen

Im Projektordner mit Godot 4.4.1 und den passenden installierten Export-Templates:

```powershell
./build_windows_online.ps1 -Godot 'C:/path/to/Godot_v4.4.1-stable_win64.exe'
```

Das Skript erstellt einen Snapshot im temporaeren Ordner und exportiert
standardmaessig mit `--export-release`. Die fertige EXE, passenden DLLs,
Anleitung, SHA-256-Pruefsummen
und ZIP liegen in einem neuen Unterordner von `builds`. Bestehende Exporte werden
nicht ueberschrieben. Fuer Regressionstests siehe
`tests/NETWORK_LIFECYCLE_TESTING.md` im Projekt.
