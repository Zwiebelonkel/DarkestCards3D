# Permanente Special-/Progressionskarten

Die 17 neuen Karten verwenden das vorhandene Kartenformat, die gespeicherte
Sammlung und die bestehende Sonderkarten-Abgrenzung. Sie haben Angriff und
Defense 0, keine Kampfeffekte und sind weder für Deck, Kampfwert-Upgrades noch
Fusion zulässig. Vorhandene Karten bleiben unverändert.

## Balance und Kartendaten

Alle neuen Effektwerte stehen direkt bei den Karten in `data/cards.json` unter
`upgrade_modifiers`. Dafür ist kein zusätzlicher Autoload nötig.

| Karten-ID | Seltenheit | Startwert | Voraussetzung |
| --- | --- | --- | --- |
| `lucky_coin` | legendary | `lucky_coin_bonus: 0.05` | – |
| `golden_clicker` | epic | `manual_click_bonus: 0.05` je Kopie | `clicker` |
| `auto_clicker` | mythic | `auto_click_coins_per_second: 0.02` | `clicker` |
| `black_market_access` | legendary | `area_unlock: black_market` | – |
| `dealer_license` | mythic | `shop_discount: 0.10` | – |
| `fusion_upgrade_1` | legendary | `fusion_requirement: 4` | – |
| `fusion_upgrade_2` | mythic | `fusion_requirement: 3` | `fusion_upgrade_1` |
| `soulcoin_boost_1` | rare | `soulcoin_multiplier: 1.02` | – |
| `soulcoin_boost_2` | epic | `soulcoin_multiplier: 1.05` | Stufe I |
| `soulcoin_boost_3` | legendary | `soulcoin_multiplier: 1.10` | Stufe II |
| `soulcoin_boost_4` | mythic | `soulcoin_multiplier: 1.15` | Stufe III |
| `xp_boost_1` | rare | `xp_multiplier: 1.02` | – |
| `xp_boost_2` | epic | `xp_multiplier: 1.05` | Stufe I |
| `xp_boost_3` | legendary | `xp_multiplier: 1.10` | Stufe II |
| `xp_boost_4` | mythic | `xp_multiplier: 1.15` | Stufe III |
| `graveyard_key` | legendary | `area_unlock: graveyard` | – |
| `basement_key` | legendary | `area_unlock: basement` | – |

Golden Clicker ist stapelbar, passend zum vorhandenen Clicker Upgrade; alle
anderen neuen Karten sind einmalige Freischaltungen. Coin-/XP-Stufen verwenden
das Maximum, Fusion das Minimum der gültigen Modifikatoren. Voraussetzungen
werden rekursiv geprüft: Eine allein vorhandene hohe Stufe aus einem bearbeiteten
Save aktiviert keinen Bonus. Zyklen in `requires` werden abgewiesen.

Neue Datenfelder:

- `requires: Array[String]`: benötigte Sonderkarten; Prüfung vor Erwerb und Wirkung.
- `permanent_upgrade: bool`: Kennzeichnung der permanenten Karten in der UI.
- `upgrade_modifiers: Dictionary`: zentrale Effektwerte aus obiger Tabelle.
- `area_unlock: String`: freigeschalteter Bereich; unabhängig von dessen Scene.
- `reward_weight: float`: relatives Gewicht innerhalb eines Kartenpools; Standard 1.
- `flavor_text: String`: der vorgegebene englische Beschreibungsspruch, getrennt
  vom kurzen, übersetzten Effekttext.

`unique_unlock`, `category`, `random_reward`, `attack`, `defense`, `effects` und
die Darstellung mit vorhandenen Bildern verwenden weiterhin das bestehende Format.
Die neuen Karten nutzen vorhandene Bilder als Platzhalter.

Lucky Coin hat `reward_weight: 0.02`: innerhalb eines Legendary-Pools ist sein
Gewicht 50-mal kleiner als das einer normalen Karte. Der permanente Bonus erhöht
die gesamte Rare+-Chance relativ, beispielsweise von 20 % auf 21 %, nicht auf
25 %. Die zusätzliche Masse kommt zuerst aus Common, bei Bedarf aus Uncommon.
Gesamtgewicht und Verhältnis der höheren Seltenheiten bleiben erhalten.
Garantierte Seltenheiten werden nicht geändert. Alle allgemeinen Random- und
Pack-Auswahlen prüfen Voraussetzungen, bereits besessene Uniques und noch nicht
eingesammelte Uniques im aktuellen Pack. Die vorhandene Ersatzwahl bei vollständig
erschöpften Pack-Seltenheiten bleibt bestehen.

Weitere Balance-Stellen:

- `scripts/GameCurrency.gd`: `BASE_MANUAL_CLICK_REWARD = 0.02`,
  `CLICKER_UPGRADE_REWARD = 0.01`, `AUTO_CLICK_INTERVAL = 1.0` Sekunden.
- `scripts/autoload/CollectionManager.gd`: `FUSION_REQUIRED_CARDS = 5` als Grundwert.
- `scripts/packs/PackDefinition.gd`: vorhandene Pack-Preise und Rarity-Gewichte.
- `scripts/CardUpgradeManager.gd`: bestehender `STAT_UPGRADE_COST_STEP`.
- `ProgressionArea`: eigener `shop_pool`, `shop_card_ids` und Platzhaltertext.

## Zentrale Funktionen

`CollectionManager` bietet:

- `has_unlock(card_id)` und `requirements_met(card_id)`.
- `get_soulcoin_multiplier()`, `get_xp_multiplier()`.
- `get_fusion_requirement()`; Backend und Schmiede-UI verwenden denselben Wert.
- `get_shop_discount(shop_pool = "normal")`; weitere Rabattquellen können
  denselben Datenmodifikator verwenden, Gesamtgrenze 100 %.
- `get_lucky_coin_bonus()`, `get_manual_click_bonus()`, `get_auto_click_rate()`.
- `get_area_unlock_card_id(area_id)`, `has_area_access(area_id)`, `unlock_area(area_id)`.

`GameCurrency` bietet zusätzlich:

- `get_manual_click_base_reward()`, `get_manual_click_reward()`, `award_manual_click()`.
- `advance_auto_clicker(delta)` für verstrichene Online-Spielzeit.
- `get_shop_price(base_price, shop_pool = "normal")` mit Rundung auf Cent.
- `get_level_bonus_reward()` für die Vorschau des erhöhten Levelbonus.
- `format_coins(amount = -1, compact = false)`; kompakt entfernt unnötige Nachkommastellen.

Weitere Schnittstellen: `PackDefinition.get_price(pack_id, pack_data = {})`,
`PackPreviewViewport.set_price()`,
`CardDatabase.get_adjusted_rarity_weights(weights, lucky_bonus = -1)`.
`HospitalDoor.area_id` und `refresh_area_access()` verbinden bestehende Türen
mit der Zugangsprüfung. `ProgressionArea` bietet `set_interaction_enabled()`,
`open()`, `close()`, `is_open()`, `get_shop_price()`, `get_shop_card_ids()` und
das Signal `screen_open_changed(open)` zur Einbindung in weitere Szenen.
`CardUpgradeManager.get_stat_upgrade_cost()` und der Parameter `coins_bonus`
des Signals `GameCurrency.level_up` sind jetzt `float`, damit 4,50 bzw. 28,75
SoulCoins korrekt angezeigt und ausgezahlt werden.

## Speichern und Einkommen

Alle Freischaltungen liegen weiterhin mit ihren Exemplaren und Mengen in
`user://collection.json`. Diese Sonderkarten werden nicht verbraucht; auch Keys
bleiben erhalten. Besuchte neue Bereiche werden zusätzlich unter
`metadata.area_access` atomar gespeichert. Die vorhandene Slotraum-Freischaltung
und ihre Schlüssel-Interaktion bleiben kompatibel. Ein Collection-Reload meldet
die geänderten IDs, damit aktive Anzeigen und Auto-Clicker-Cache aktualisiert werden.

Die vorhandene `user://currency.cfg` speichert zusätzlich
`currency.reward_remainder` und `progression.xp_reward_remainder`. So liefern auch
kleinste Belohnungen langfristig genau den vorgesehenen Bonus. Alte Saves ohne
diese Felder starten mit Rest 0.

SoulCoin-Boosts gelten einmalig auf reguläre Coin-Gutschriften, manuelle und
automatische Klicks, Match-Belohnungen sowie Levelboni. XP-Boosts gelten zentral
auf reguläre XP einschließlich Matches. Slot-Einsätze und bereits festgelegte
Glücksspielauszahlungen sowie Pack-Rückerstattungen behalten ihre exakten
Transaktionsbeträge. Der Auto Clicker läuft nur mit gültiger Freischaltung im
laufenden, nicht pausierten Spiel; er zahlt gebündelt pro Sekunde. Es gibt keine
gespeicherten Zeitstempel und keine Offline-Einnahmen.

## Zugänge und begehbare Bereiche

Der Friedhofsschlüssel (`graveyard_key`) ist ausschließlich ein Geheimfund im
Keller: Wirf die Kisten weg, um den darunter verborgenen Schlüssel zu finden.
Der Fund schreibt die Karte automatisch gut. Wie beim Messerfund der
Slotraum-Schlüsselkarte schließt `random_reward: false` sie aus allgemeinen
Zufallsbelohnungen, festen Seltenheitswürfen, Packs und deren Ersatzpools aus.
Bereits vorhandene Exemplare und gespeicherte Friedhofszugänge bleiben erhalten.
Diese Fundorte sind Entwicklerdokumentation; das Journal enthält keine
Raum-, Fundort- oder Navigationstipps und zeigt Schlüssel nur als normale Karten.

Die drei Zugänge stehen im Hub und verwenden `HospitalDoor` mit `area_id`.
Black Market liegt neben dem Pack-Shop, Graveyard neben der Sammlung und
Basement neben dem Upgrade-Shop.
Ohne passende Karte bleibt die Tür gesperrt. Friedhof und Keller sind als
`GraveyardRoom` und `BasementRoom` direkt in Main instanziert und teilen dessen
3D-Welt und Kamera. Nach Freischaltung fliegt die Main-Kamera beim Türklick
sichtbar durch die geöffneten Hospitaltüren und den Verbindungsgang zum festen
Raummittelpunkt. Der Keller verwendet dieselbe Hospital-Raumhülle wie der
Slotraum mit einem Treppengang; zum Friedhof führt ein Hospitalgang.

A/D dreht den Blick wie im Slotraum um 90°. Ein Klick auf die sichtbare
Rückkehrtür führt zur vorherigen Hub-Position und Blickrichtung zurück.
Escape öffnet das reguläre Pausemenü. Die Räume verwenden weder eine eigene
Kamera noch ein eigenes HUD oder einen separaten Viewport; Wegpunkte,
W/S-Bewegung und eine eigenständige F6-Besichtigung entfallen. Während des
Türflugs sind weitere Interaktionen gesperrt. Die Zugangskarten bleiben
erhalten, und die Rückkehr ist auch nach Kartenverlust während des Besuchs
möglich. Ein erneuter Eintritt prüft wieder den gültigen Zugang.

Der Black Market besitzt den separaten Pool `black_market` und eine zunächst
leere Kartenliste. Der normale Dealer-Rabatt gilt dort nicht. Zusätzliche Lore,
Karten und Events können in den Raumbausteinen von Friedhof und Keller ergänzt
werden. Details zum Aufbau und zum Generator der Hub-Raumhülle mit echten
Türöffnungen stehen in [exploration-rooms.md](exploration-rooms.md).

## Geänderte und neue Dateien

Die folgende Liste umfasst die Änderungen dieser Aufgabe, nicht bereits vorher
vorhandene Änderungen im Arbeitsverzeichnis.

| Datei | Änderung |
| --- | --- |
| `data/cards.json` | 17 Karten, Voraussetzungen, konfigurierbare Modifier und Platzhalterbilder. |
| `scripts/autoload/CollectionManager.gd` | Generische Upgrade-/Area-Abfragen, Reload-Signal, dynamische und atomare Fusion. |
| `scripts/autoload/CardDatabase.gd` | Zentrale zulässige und gewichtete Reward-Auswahl, Lucky-Coin-Bonus. |
| `scripts/GameCurrency.gd` | Income-/XP-Multiplikatoren, Restwerte, Clicker, Online-Auto-Ertrag, zentrale Preise. |
| `scripts/CardUpgradeManager.gd` | Rabattierte Stat-Preise als Dezimalbetrag. |
| `scripts/UpgradeMachine.gd` | Effektkauf verwendet zentrale Preise. |
| `scripts/UpgradeUI.gd` | Effekt-/Stat-Preise mit Nachkommastellen und Aktualisierung bei Unlocks. |
| `scripts/packs/PackDefinition.gd` | Gemeinsame Packpreis-Abfrage mit Pool-Unterstützung. |
| `scripts/ui/PackShopUI.gd` | Rabattierte Packpreise, Kaufmengen und Live-Aktualisierung. |
| `scripts/PackPreviewViewport.gd` | Aktualisierbare Packpreis-Anzeige. |
| `scripts/ui/PackOpeningScreen.gd` | Abbuchung desselben rabattierten Packpreises. |
| `scripts/ui/LevelProgress.gd` | Zentral berechnete Klick-Erträge und Levelbonus-Vorschau. |
| `scripts/props/FusionWorkbench.gd` | Auswahlgrenze, Slots und Beschriftung passen sich 5/4/3 an. |
| `scripts/props/HospitalDoor.gd` | Optionale generische Area-Sperre auf der vorhandenen Tür. |
| `scripts/rooms/ProgressionArea.gd` | Wiederverwendbarer Zugang mit Bildschirm, Rückkehr und separatem Shop-Pool. |
| `scenes/props/ProgressionArea.tscn` | Einfacher Tür-/Bereichs-Platzhalter. |
| `scripts/main/Main.gd` | Bereichszugänge und modale Interaktionssperren im Hub. |
| `scenes/main/Main.tscn` | Drei konfigurierte Zugänge. |
| `scripts/card/Card3D.gd` | Permanente Kartenkennzeichnung. |
| `scenes/table/GameTable.gd` | Match- und Levelbelohnungen ohne Abschneiden von Coin-Bruchteilen. |
| `scripts/ui/SettingsMenu.gd` | Tatsächliche Coin-/Levelbelohnungen in Test-Statusmeldungen. |
| `scripts/ui/JournalContent.gd` | Neue Progressionsmechaniken und Beschreibungstexte im bestehenden Journal. |
| `localization/cards.csv` | Neue Karten in allen fünf vorhandenen Sprachen. |
| `localization/game.csv` | Dynamische Fusionsanzahl und dezimale Preis-/Rewardtexte. |
| `localization/journal.csv` | Übersetzungen der ergänzten Progressionsmechaniken. |
| `tests/progression_upgrades_test.gd`, `.tscn` | Voraussetzungen, Uniques, Save/Load, Bereiche und echte Fusion inklusive UI-Slots. |
| `tests/progression_rewards_test.gd`, `.tscn` | Neue Daten und gewichtete Reward-/Pack-Auswahl. |
| `tests/progression_economy_test.gd`, `.tscn` | Bruchteilboni, Clicker, Online-Zeit und tatsächliche Shopkäufe. |
| `tests/progression_areas_test.gd`, `.tscn` | Weltzugänge, Sperren, Bildschirm und vorhandene Tür-Kompatibilität. |
| `tests/journal_content_test.gd` | Progressionstexte, Flavor, dynamische Balance-Werte und Unabhängigkeit vom Kartenbesitz. |
| `docs/progression-cards.md` | Diese Implementierungs-, API- und Balance-Dokumentation. |

## Tests ausführen

Die Tests verwenden den vorhandenen isolierten Runner; echte Spielstände werden
nicht geöffnet oder geändert. Beispiel:

```powershell
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/progression_upgrades_test.tscn' -SuccessMarker 'PROGRESSION_UPGRADES_TESTS: PASS' -ImportAssets
```

Weitere Scenes/Marker: `progression_rewards_test.tscn` /
`PROGRESSION_REWARD_TESTS: PASS`, `progression_economy_test.tscn` /
`PROGRESSION_ECONOMY_TESTS: PASS`, `progression_areas_test.tscn` /
`PROGRESSION_AREAS_TESTS: PASS`.

Geprüft mit Godot 4.4.1 in isolierten Testprojekten:

| Testbereich | Ergebnis |
| --- | --- |
| Neue Upgrades, Save/Load, Voraussetzungen und dynamische Fusions-UI | 86 Prüfungen bestanden |
| Neue Karten und zentrale Reward-Auswahl | 119 Prüfungen bestanden |
| Einkommen, Bruchteilboni, Auto Clicker und echte rabattierte Käufe | 29 Prüfungen bestanden |
| Drei Weltzugänge, echte Mausbedienung, Rückkehr und Bildschirm-Sperren | 38 Prüfungen bestanden; Ansichten visuell kontrolliert |
| Bestehende Fusion / Special Cards / Starthand / Schlüsselkarte | 104 / 39 / 108 / 41 Prüfungen bestanden |
| Bestehende Slot-Währung / Upgrade-Kosten / Pack-Batches / Pack-Mengen | 27 / 26 / 47 / 40 Prüfungen bestanden |
| Kampf, Mehrspielerrollen und tatsächliche Clicker-Bedienung | `MATCH_FEATURE_TESTS: PASS` |
| Bisherige XP-/Level-Grenzen, Überlauf, Save-Migration und Visor | `progression_test.gd` bestanden |
| Kartenübersetzung / Journal-Inhalt / Journal-Übersetzung und Seitenlayout | 3550 / 325 / 6469 Prüfungen bestanden |
