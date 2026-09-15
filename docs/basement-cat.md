# Katze im Keller

Die Begegnung startet einmal pro Spielstand, nachdem man den Keller betreten
und nach rechts gedreht hat (Raum 3, Blickrichtung 3). Die Katze läuft aus der
hinteren Ecke vor den Spieler. Die gemeinsame Main-Kamera richtet sich auf sie
aus; anschließend fahren Engel links, Satan rechts und die bestehende
First-Person-Pistole in der Mitte ins Bild.

Hover erklärt die beiden Entscheidungen, ein Klick entscheidet:

- **Satan:** einmalig exakt 1000 Soul Coins. Derselbe Mündungsblitz, Schusston
  und Waffenrückstoß wie in der Siegsequenz begleiten den Wechsel auf
  `catDead.png`. Die Katze wird weggeschleudert und bleibt dauerhaft verschwunden.
- **Engel:** keine Auszahlung. Die Waffe fährt wieder nach unten; die Katze
  bleibt und spielt dauerhaft die zweibildrige `catSpare.png`-Animation ab.
  Nach dem Verlassen des Kellers hilft sie am Clicker, sofern dieser freigeschaltet ist.

`GameCurrency.resolve_basement_cat_choice()` speichert Entscheidung und
Belohnung gemeinsam in der bestehenden atomaren Currency-Datei. Die
Entscheidung gilt pro Save-Slot; Einkommen-Multiplikatoren verändern die
versprochenen 1000 Coins nicht. Bei einem Speicherfehler bleibt die Auswahl
offen und es wird kein Schuss abgespielt. Wiederholte Eingaben erzeugen weder
eine zweite Entscheidung noch zusätzliche Coins.

## Katze am Clicker

Nach der abgeschlossenen Rückreise aus dem Keller wird der Umzug pro Spielstand
gespeichert. Auch das Laden eines bereits verschonten Spielstands im Hub zählt
als Verlassen der alten Kellerszene. Sobald die Clicker-Karte vorhanden ist,
verschwindet die Katze im Keller und sitzt auf dem Clicker-Button des Levelprogress.
Ohne Clicker wartet sie im Keller mit `catSpare`; eine spätere Freischaltung
aktiviert ihre Hilfe automatisch. Eine erschossene Katze erscheint dort nie.

Die vorhandene `catClick.png` enthält drei Bilder mit je 32 × 32 Pixeln.
Sie läuft mit drei Bildern pro Sekunde. Beim Erreichen des dritten Bildes
(Godot-Frameindex 2) erzeugt die Katze einmal den aktuellen manuellen Klickwert,
inklusive Clicker-Upgrades, Golden Clicker und SoulCoin-Bonus. Sie benötigt
keine Auto-Clicker-Karte und kann gemeinsam mit dieser arbeiten.

Der zentrale Wallet-Timer steuert Bild und Auszahlung: Ein eingeklapptes
Levelprogress arbeitet weiter, mehrere HUD-Instanzen verdoppeln keine Einkünfte.
Nur ein sichtbares, geöffnetes Panel spielt den Buttondruck samt Klickton.
SceneTree-Pausen stoppen den Timer; ein Online-Pauseoverlay läuft wie beim
vorhandenen Auto-Clicker weiter. Gespeichert wird der Umzug, kein Zeitstempel
für Offline-Einkommen und kein angefangener Animationsdurchlauf.

## Aufbau

- `scenes/rooms/BasementCatEncounter.tscn` enthält die Katze und eine lokale
  Lichtquelle; die Szene ist dauerhaft in `Basement.tscn` instanziert.
- `scripts/rooms/BasementCatEncounter.gd` steuert Weg, Kamera, Treffer und
  sichtbaren Speicherzustand. Wegpunkte und Zeiten sind im Inspector einstellbar.
- `scripts/ui/CatChoicePresentation.gd` verwendet die vorhandenen Engel-,
  Satan-, Pistolen- und Flash-Assets. Die UI liegt unter dem CRT-Filter.
- `Main.gd` sperrt während der Begegnung Raumwechsel, Drehung, Kisten und
  Journal. Pause hält die Begegnung an, auch beim Online-Pauseoverlay.

## Tests

```powershell
./tests/run_basement_cat_backend_tests.ps1 -Godot 'C:/path/to/godot.exe'
./tests/run_cat_clicker_backend_tests.ps1 -Godot 'C:/path/to/godot.exe'
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/basement_cat_test.tscn' -SuccessMarker 'BASEMENT_CAT_TESTS: PASS' -ImportAssets -Visual -QuitAfterFrames 12000
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/cat_clicker_integration_test.tscn' -SuccessMarker 'CAT_CLICKER_INTEGRATION_TESTS: PASS' -ImportAssets -Visual -QuitAfterFrames 12000
```

Die isolierten Tests prüfen reale Tür-/Tastatur-/Mauseingaben, Hovertexte,
Abfolge, Pausen, Speicherfehler, exakte Auszahlung, Flug, dauerhafte
Abwesenheit, `catSpare`-Animation und beide Ergebnisse nach dem Neuladen.
Die Clicker-Prüfungen decken den Umzug bei abgeschlossener Türreise, sichtbare
Frame-Auszahlung, manuellen Klick unter der Katze, mehrere Visoren, gefaltete
Anzeige, Pause, spätere Clicker-Freischaltung und Profilwechsel ab. Backendtests
prüfen auch große Zeitabschnitte, Bonus-Bruchteile und Speicherfehler.

Verifiziert: 94 Integrationsprüfungen mit Forward+-Rendering und 44
Backendprüfungen. Die Integrationssuite prüft ausdrücklich auch das
Online-Pauseoverlay und die vollständige Sichtbarkeit der verschonten Katze.
Die absichtlich provozierte fehlgeschlagene Speicherung erzeugt einmal die
erwartete Save-Fehlermeldung; der anschließende Wiederholungsversuch besteht.
Kistenfund, Keller-/Friedhofnavigation und Black Market wurden zusätzlich
als Regression geprüft.

Vorschauen: [Entscheidung](previews/basement-cat-choice.png) ·
[Verschonte Katze](previews/basement-cat-spared.png).
