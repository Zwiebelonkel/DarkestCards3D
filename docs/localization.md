# Lokalisierung

Das Spiel bietet Deutsch (`de`, Vorgabe), Englisch (`en`), Spanisch (`es`),
Französisch (`fr`) und Polnisch (`pl`). Die Auswahl unter **Einstellungen → Sprache**
wird in `settings.cfg` gespeichert und sofort angewendet. Regionale Angaben wie
`de-DE` werden normalisiert; unbekannte Sprachcodes fallen auf Englisch zurück.

## Übersetzungsdateien

Alle Kataloge liegen unter `localization/`, als UTF-8 mit dieser Kopfzeile:

```csv
keys,en,de,es,fr,pl
```

| Datei | Inhalt |
| --- | --- |
| `cards.csv` | Kartennamen und Beschreibungen, Ereigniskarten, Packs |
| `effects.csv` | Effekte, Werteanzeigen, Seltenheiten und Kartenüberschriften |
| `journal.csv` | Kapitel, Erklärungen und Spielmechaniken |
| `menus.csv` | Hauptmenü, Einstellungen, Mikrofontest, Multiplayer und Netzwerkhinweise |
| `game.csv` | Kampfmeldungen, Sammlung, Schmiede, Automaten, Fortschritt und weitere Spieltexte |
| `models.csv` | Zusätzliche Beschriftungen auf importierten 3D-Modellen |

`keys` enthält den ursprünglichen Autorentext. Er ist eine stabile Kennung,
keine Anzeigevorgabe. Deshalb stehen in dieser Spalte weiterhin deutsche und
englische Quellen; die fünf Sprachspalten sind voneinander getrennt. Zeilenumbrüche
innerhalb einer Zelle werden als echte Zeilenumbrüche in korrekt zitiertem CSV
gespeichert. Platzhalter wie `%s`, `%d` und `%%` müssen in jeder Sprache in derselben
Reihenfolge erhalten bleiben. Identische Kennungen werden nur einmal gepflegt.

Godot importiert die CSV-Dateien als native `.translation`-Ressourcen. Alle fünf
Sprachen sind in `project.godot` registriert und werden auch exportiert. Nach
CSV-Änderungen das Projekt in Godot öffnen oder `godot --headless --import --path .`
ausführen. Die erzeugten Übersetzungsdateien nicht von Hand bearbeiten.

## Neue Spieltexte einbinden

Statische `Label`, `Label3D` und `Button`-Texte können direkt die Quellkennung
enthalten; Godot übersetzt sie und aktualisiert sie bei einem Sprachwechsel.
Bei zusammengesetzten Texten immer zuerst die gesamte Vorlage übersetzen:

```gdscript
label.text = Localization.format_text("Drew %s", [
    Localization.localized_arg(str(card_data["name"]))
])
```

`Localization.text(source)` übersetzt Text für eigene Darstellungen, etwa
`TextMesh`, und muss vor `to_upper()` oder eigenen Textumbrüchen aufgerufen werden.
`localized_arg` kennzeichnet ausdrücklich übersetzbare Kartennamen und andere
Autorentexte. Unmarkierte Werte bleiben unverändert, insbesondere Steam-Namen,
eigene Lobbytitel, Dateipfade und Kennungen. Keine sprachabhängigen Satzfragmente
zusammenkleben; stattdessen vollständige CSV-Vorlagen verwenden.

Katalogdaten, Karten-IDs, Speicherstände und RPC-Daten bleiben kanonisch. Ein
Sprachwechsel aktualisiert die Darstellung, löst aber keine Käufe, Belohnungen,
Karteneffekte oder Zufallswürfe aus. Eigene Ansichten können dafür das Signal
`Localization.locale_changed` abonnieren. Vorhandene formatierte Statusmeldungen
werden aus ihrer Vorlage aktualisiert; länger gespeicherte Meldungen wie das
Kampfergebnis behalten zusätzlich ihre ursprünglichen Argumente beim Controller.

Die Pixelschrift erhält Godots eingebettete Ersatzschrift für fehlende Zeichen,
insbesondere polnische Buchstaben und französisches `œ`. Buchseiten und kleine
3D-Beschriftungen messen die tatsächliche Übersetzung und passen Umbrüche oder
Schriftgröße an. Importierte Textgeometrie wird zur Laufzeit durch lokalisierbare
3D-Schrift ersetzt. Die vorhandenen Filter-Overlays und Nearest-Filter bleiben aktiv.

## Prüfungen

```powershell
python -X utf8 tests/audit_localization.py --scenes
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/world_localization_test.tscn' -SuccessMarker 'WORLD_LOCALIZATION_TESTS: PASS' -ImportAssets -Visual
```

Der CSV-Audit prüft Vollständigkeit, widersprüchliche Kennungen, Platzhalter und
Szenentexte. Die Godot-Tests laufen mit umgeleiteten Speicherpfaden in einer
separaten Projektkopie. Weitere Tests: `localization_ui_test`,
`localization_table_test`, `card_localization_test`, `journal_localization_test`
und `model_localization_test`. Sie prüfen Sprachwechsel, Texte, unveränderte
Spielzustände und bei den 3D-Darstellungen die Einpassung.
