# Erweiterung des unteren Kampfkarten-Pools

28 eigenständige Kampfkarten: 10 Common, 10 Uncommon und 8 Rare. Alle bestehenden
86 Karteneinträge wurden gegen einen vor dieser Änderung angelegten Snapshot
verglichen und sind unverändert. Es gibt kein Evolution-System und keine neuen
Special Cards, Voraussetzungen oder permanenten Unlocks.

## Karten

Angriff/Defense und Effekte der implementierten Karten:

| Seltenheit | Name | ID | ATK / DEF | Effekt |
| --- | --- | --- | --- | --- |
| common | Rat | `rat` | 2 / 2 | – |
| common | Street Dog | `street_dog` | 3 / 4 | – |
| common | Brick | `brick` | 4 / 6 | – |
| common | Plastic Chair | `plastic_chair` | 2 / 7 | Armor 10 % |
| common | Angry Pigeon | `angry_pigeon` | 4 / 2 | – |
| common | Moldy Bread | `moldy_bread` | 1 / 5 | Poison: 1 Schaden für 2 eigene Züge des Ziels |
| common | Bottle | `bottle` | 5 / 1 | – |
| common | Shopping Cart | `shopping_cart` | 2 / 8 | – |
| common | Sock | `sock` | 1 / 3 | – |
| common | Sewer Rat | `sewer_rat` | 4 / 3 | – |
| uncommon | Crab | `crab` | 5 / 7 | Thorns 15 % |
| uncommon | Security Guard | `security_guard` | 4 / 10 | Armor 25 % |
| uncommon | Drunk Guy | `drunk_guy` | 8 / 4 | Random Damage 0,5–1,5× |
| uncommon | Stray Cat | `stray_cat` | 5 / 5 | Lifesteal 10 % |
| uncommon | Broken Robot | `broken_robot` | 7 / 8 | – |
| uncommon | Cactus Dealer | `cactus_dealer` | 6 / 6 | Thorns 20 % |
| uncommon | Sewer Worker | `sewer_worker` | 6 / 9 | Armor 10 % |
| uncommon | Angry Goose | `angry_goose` | 7 / 5 | – |
| uncommon | Trash Monster | `trash_monster` | 6 / 8 | Random Damage 0,75–1,25× |
| uncommon | Rat King | `rat_king` | 3 / 5 | Swarm Power |
| rare | Butcher | `butcher` | 10 / 8 | Cleave 50 % |
| rare | Paramedic | `paramedic` | 6 / 12 | Neighbor Heal 1 |
| rare | Bouncer | `bouncer` | 7 / 10 | Armor 35 % |
| rare | Pickpocket | `pickpocket` | 9 / 8 | Curse 1 |
| rare | Rabid Dog | `rabid_dog` | 13 / 5 | Poison: 2 Schaden für 2 eigene Züge des Ziels |
| rare | Cultist | `cultist` | 7 / 13 | Grave Return |
| rare | Chainsaw Guy | `chainsaw_guy` | 11 / 7 | Cleave 50 % |
| rare | Repair Bot | `repair_bot` | 8 / 12 | Neighbor Heal 1 |

Die angegebenen englischen Namen und Beschreibungssprüche sind in `cards.json`
unverändert übernommen und in den fünf vorhandenen Sprachen übersetzt.

## Placeholder

Alle neuen Karten verwenden ausschließlich das bereits vorhandene und importierte
Bild `res://assets/effects/placeholder.png`: ein weißes Pixel-Fragezeichen auf
schwarzem Hintergrund. Es wurden keine Bilder erzeugt, heruntergeladen oder
ersetzt. Jede neue Karte besitzt einen gültigen Bildpfad; ihre späteren Artworks
können einzeln über `image` eingetragen werden.

Die Karten enthalten weder `animated` noch `frame_count`, `frame_columns`,
`frame_rows` oder `frame_fps`. Der vorhandene Card3D-Renderer behandelt sie als
statische Bilder und setzt die Texturkoordinaten entsprechend zurück.

## Bewusste Anpassungen

Die Anpassungen verwenden vorhandene Effekte und gleichen besonders starke
Synergien an den bestehenden Kartenpool an.

- **Security Guard:** Der vorgeschlagene `bodyguard: 0.25` wurde durch
  `armor.value: 0.25` ersetzt. Bodyguard steht zwar im Effektkatalog, besitzt aber
  keinen Kampfpfad. Rüstung schützt diese Karte selbst; sie leitet keinen Schaden
  von Nachbarn um. Werte 4/10 bleiben erhalten.
- **Bouncer:** Entsprechend `armor.value: 0.35` statt Bodyguard. Weil Eigenrüstung
  die effektive Lebensdauer stark erhöht, wurden die Werte von 8/14 auf **7/10**
  reduziert. So wird aus dem Ersatz kein übermäßig starker Rare-Tank.
- **Butcher und Chainsaw Guy:** `_apply_cleave()` verwendet bereits fest
  **50 % des Angriffswerts**, unabhängig vom Datenparameter. Deshalb steht bei
  beiden `side_damage: 0.5` statt der vorgeschlagenen 0.25 bzw. 0.35. Die Werte
  wurden auf **10/8** bzw. **11/7** angepasst; gegenüber Toaster (12/6, ebenfalls
  50 % Cleave) tauschen sie Angriff gegen Lebenspunkte. Die bestehende
  Cleave-Implementierung und andere Karten wurden nicht geändert.
- **Rat King:** **3/5 statt 7/7**, weil Swarm Power den Angriff mit allen identischen
  Karten auf beiden Tischseiten multipliziert. Gegenüber Ant (2/6) bietet er mehr
  Angriff bei weniger Defense. Rat, Sewer Rat und Rat King zählen dabei jeweils
  nur ihre eigene ID; sie bilden keinen gemeinsamen Schwarm oder Entwicklungsbaum.
- **Sewer Rat:** Der ausdrücklich optionale Gift-Effekt entfällt. Mit 4/3 und Gift
  wäre er eine direkte Verbesserung von Corpse bei derselben Seltenheit gewesen.
  Damit haben nur zwei der zehn neuen Commons einen angeborenen Effekt.
- **Paramedic und Repair Bot:** `neighbor_heal.value: 1` bleibt unverändert und
  heilt nach vorhandener Logik **zu Beginn des eigenen Zuges**, nicht bei erlittenem
  Schaden. Ihre Effektbeschreibung wurde entsprechend präzisiert.

Armor 10 % und 35 % erhalten eigene `name`-/`description`-Metadaten direkt im
Effekt-Dictionary, damit die vorhandene UI nicht ersatzweise „Armor 25 %“ anzeigt.
Das verwendet die bereits unterstützten Metadaten und verändert weder den
gemeinsamen Effektkatalog noch vorhandene Karten. Für Netzwerkdaten ohne
Text-Metadaten leitet die Effektanzeige abweichende Rüstungsbeschriftungen ebenfalls
aus dem tatsächlichen Prozentwert ab.

Alle anderen Werte entsprechen der Vorgabe. Bruchteile von Treffer-, Dornen- und
Heilwerten werden vom bestehenden Resolver auf ganze Punkte gerundet. Grave Return
rettet die Karte einmal mit gerundeten 50 % der maximalen HP; es erzeugt keine
neue Karte. Gift und Execute umgehen diesen Schutz, wie bei vorhandenen Karten.

## Integration und geänderte Dateien

| Datei | Änderung dieser Aufgabe |
| --- | --- |
| `data/cards.json` | 28 normale Kampfkarten im bestehenden Format angehängt. |
| `localization/cards.csv` | 56 Übersetzungszeilen für die neuen Namen und Sprüche. |
| `localization/effects.csv` | Fünf Übersetzungszeilen für genaue Rüstungswerte und den Heilungszeitpunkt. |
| `scripts/ui/EffectPresentation.gd` | Korrekte Beschriftung für Rüstungswerte ohne passende Katalogvariante, auch nach Netzwerkübertragung. |
| `tests/lower_rarity_cards_test.gd` | Gültigkeit, Bilder, Effekte, Pools, Decks, Save/Load und Darstellung prüfen. |
| `tests/lower_rarity_cards_test.tscn` | Einstiegsszene für den isolierten Test. |
| `docs/lower-rarity-cards.md` | Kartenliste, Parameteranpassungen und Integrationshinweise. |

Separate Reward-, Rarity-, Collection-, Journal-, Kampf- und Fusionslisten sind
nicht nötig: Diese Systeme leiten ihre Pools aus `CardDatabase` ab. Mit
`category: combat`, gültiger Rarity und ohne `random_reward: false` sind die neuen
Karten reguläre Packbelohnungen und Deckkarten. Es wurden keine Save-Formate und
keine Kampf- oder Effektberechnungen geändert.

## Prüfen

```powershell
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/lower_rarity_cards_test.tscn' -SuccessMarker 'LOWER_RARITY_CARDS_TESTS: PASS' -ImportAssets
```

Der vorhandene Runner kopiert das Projekt in ein separates Testverzeichnis und
leitet gespeicherte Daten vor dem Start dorthin um. Bestehende Spielstände werden
dabei nicht geöffnet oder verändert.

Validiert mit Godot 4.4.1:

| Prüfung | Ergebnis |
| --- | --- |
| Alle 28 Karten, IDs, Rarities, Bilder, Effekte, echte Collection, Decks, Netzwerk und Save/Load | `LOWER_RARITY_CARDS_TESTS: PASS` – 1.250 Prüfungen |
| Kartenübersetzungen und Darstellung in allen fünf Sprachen | 4.364 Prüfungen bestanden |
| Vorhandenes Journal mit dem erweiterten Pool | 390 Prüfungen bestanden |
| Vorhandene Fusion einschließlich neuer Reward-Pools | 114 Prüfungen bestanden |
| Vorhandene Sonderkarten | 39 Prüfungen bestanden |
| Vergleich der bisherigen Karteneinträge mit dem Snapshot vor der Erweiterung | Alle 86 unverändert |

Der Katalog umfasst damit 114 Karten. Die Prüfung bestätigt Schema, technische
Integration und nachvollziehbare Balance-Abstufungen; die Feinabstimmung der
Werte kann später anhand gespielter Matches in `data/cards.json` erfolgen.
