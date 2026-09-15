# Karten-Upgrades, Holo und God-Packs

- Angriff und Defense verwenden einen gemeinsamen Upgrade-Zaehler je Kartentyp,
  passend zum bestehenden Upgrade-System. Jeder erfolgreiche Stat-Kauf macht
  beide naechsten Stat-Upgrades um 5 Soul Coins teurer: standardmaessig
  5, 10, 15, 20 usw. Andere Karten behalten ihre eigenen Preise. Fehlgeschlagene
  Kaeufe erhoehen den Zaehler nicht. Alte Spielstaende leiten ihn aus bereits
  gekauften Angriff-/Defense-Punkten ab; danach wird er explizit gespeichert.
- Effektwuerfe haben einen eigenen Zaehler je Kartentyp und Spielstand. Jeder
  bezahlte Wurf mit Effekt erhoeht den naechsten Preis: 12, 24, 36 usw. Soul Coins.
  Ein bezahlter Wurf ohne Effekt setzt ihn auf 12 zurueck. Entfernen von Effekten,
  Stat-Upgrades und abgewiesene Kaeufe veraendern diesen Zaehler nicht.
- Der Pisse-Eimer (`piss`) zahlt das Fuenffache fuer alle Upgrades: Stats kosten
  25, 50, 75 usw., Effektwuerfe 60, 120, 180 usw. Haendlerrabatte werden danach
  einmal angewendet. Lava bleibt sein angeborener Effekt und kann weder aus
  Packs noch beim Effektwuerfeln zusaetzlich vergeben werden. Alte zusaetzliche
  Lava-Effekte werden beim Laden herausgefiltert.
- Jede neu gezogene Pack-Karte hat unabhaengig von Pack und Seltenheit eine
  Holo-Chance von 1 Prozent. Das Ergebnis gehoert zum Kartenexemplar und bleibt
  beim Sammeln, Laden, Deckbau und Online-Spiel erhalten. Vorhandene Karten ohne
  Holo-Merkmal bleiben normal. Der Holo-Shader kommt zusaetzlich zu den bisherigen
  Seltenheitseffekten auf die Karte.
- God-Packs bleiben im Shop sichtbar und sind ab Spielerlevel 10 kaufbar. Der
  Shop zeigt die Sperre an; auch die Kauf-Funktion prueft das Mindestlevel vor
  Abbuchung und Oeffnung. Basic und Ultra haben keine neue Levelbeschraenkung.

Die Sammlung und der Deckeditor fassen gleiche Kartentypen weiterhin zusammen.
Bei der Darstellung und der Zuordnung vorhandener Exemplare zum Deck werden
Holo-Exemplare zuerst verwendet.

## Pruefen

Die Tests laufen ueber `tests/run_match_feature_tests.ps1` in einem eigenen
temporaeren Projekt mit separaten Speicherstaenden. Beispiel:

```powershell
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot_console.exe' -TestScene 'res://tests/upgrade_cost_test.tscn' -SuccessMarker 'UPGRADE_COST_TESTS: PASS'
```

`build_windows_online.ps1` erstellt die eigenstaendige Windows-Testversion mit
passenden Debug-DLLs. Der bekannte native Fehler im regulaeren Release-Export
ist in `online-crash-diagnostics.md` dokumentiert.
