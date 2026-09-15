# Black Market

Der Zugang unter `Main/ProgressionAreas/BlackMarket` führt per Türklick durch
zwei echte Türrahmen in `Main/BlackMarketRoom` (Raumindex 4). Der Raum benutzt
dieselbe Kamera, A/D-Drehung und Rückfahrt wie Keller und Friedhof. Die
vorhandene Karte `black_market_access` ist weiterhin erforderlich.

`scenes/rooms/BlackMarket.tscn` enthält eine bearbeitbare Hospitalhülle,
Verbindungsgang, Kiosk mit Schalter, animierten Dealer,
Regale und lokale Beleuchtung. `CameraAnchor` definiert den Standpunkt;
`ReturnDoor` bleibt auch nach Verlust der Zugangskarte benutzbar.

## Händlerdialog

Ein Klick auf den Dealer öffnet eine von zwölf zufälligen Zeilen aus
`DealerDialogueContent.gd`, ohne direkte Wiederholung. `DealerDialogue.gd`
verwendet den bestehenden Engel-Dialogablauf: Klick vervollständigt den Text,
der nächste Klick schließt ihn; Escape schließt sofort. Die Stimme spielt nur
während des Schreibens, 16 Halbtöne tiefer als die normale Stimme. Pause,
Raumwechsel und Szenenende stoppen sie. Ein Satzabschluss-Sound wird nicht
abgespielt. `localization/dealer.csv` enthält Deutsch, Englisch, Spanisch,
Französisch und Polnisch.

Während des Dialogs sind Drehung, Türen, Journal, Fortschrittsanzeige und
Tafelkäufe gesperrt. Danach funktionieren Tafel-Hover und Käufe wieder.
Die Dialogzufallszahlen verwenden einen eigenen Generator und verändern
keinen Spielstand und keine Belohnungen.

## Angebotstafel

`OfferBoard` verwendet `scripts/rooms/BlackMarketBoard.gd` und die gemeinsame
`ScreenCameraFocus`-Steuerung. Hover fährt die Kamera zur Tafel, Verlassen
stellt die Raumansicht wieder her. Vier echte Card3D-Vorschauen zeigen das
Angebot; Kaufbuttons darunter fügen die jeweilige Karte sofort der Sammlung
hinzu. Die Tafel zeigt Guthaben, Preise, eine kurze Kaufmeldung und die Zeit
bis zum nächsten Tageswechsel. Pause, Drehung und Türfahrt sperren Käufe.

Der lokale Kalendertag bestimmt die Angebote, auch über Neustarts hinweg.
Jedes Angebot kann pro Spielstand einmal am Tag gekauft werden. Der Pool
enthält zufällig erhältliche Kampfkarten von Common bis Exotic; Secret-Karten,
Events, Schlüssel und Fortschrittsfreischaltungen sind ausgeschlossen.
Die Seltenheitspreise in `CollectionManager.BLACK_MARKET_PRICES_CENTS` sind
12 / 22 / 40 / 75 / 140 / 260 / 500 Soul Coins. Der normale Händlerrabatt
wirkt hier nicht. Die Tagesauswahl beeinflusst keine Pack- oder Kampfwürfe.

`CollectionManager.get_black_market_offers()` liefert Tag und Angebote.
`purchase_black_market_offer(day, offer_id)` validiert Tag, Zugang, Bestand
und Guthaben erneut. Karte und Kaufbeleg werden gemeinsam gespeichert;
`GameCurrency` speichert zuvor einen rückerstattbaren Zahlungsbeleg. Beim
Neuladen werden unterbrochene Käufe abgeglichen. Doppelklicks und alte
Tagesangebote können keine zusätzlichen Abbuchungen auslösen.

## Prüfung

```powershell
./tests/run_black_market_backend_tests.ps1 -Godot 'C:/path/to/godot.exe'
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/black_market_room_test.tscn' -SuccessMarker 'BLACK_MARKET_ROOM_TESTS: PASS' -ImportAssets -Visual
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/dealer_dialogue_test.tscn' -SuccessMarker 'DEALER_DIALOGUE_TESTS: PASS' -ImportAssets -Visual
```

Die Tests verwenden isolierte Spielstände. Backendtests prüfen Tageswechsel,
Profiltrennung, Preis-/Poolregeln, doppelte und veraltete Käufe, Speicherfehler
und Wiederherstellung. Der Raumtest prüft echte Mausklicks, beide
Türschwellen, Kamera und Hover, Sichtbarkeit der Tafel, aktuelle Upgrade-Werte,
Käufe und Interaktionssperren. Zusätzliche Prüfungen betreffen bestehende
Raumwechsel und Progressionszugänge.

Verifiziert: 77 Raumprüfungen im Forward+-Renderer, 35 Backendprüfungen,
32 Progressionsprüfungen, 85 Keller-/Friedhofprüfungen, 71 bestehende
Raumreiseprüfungen und 27 Währungsprüfungen. Der globale Übersetzungs-Audit
meldet bestehende fehlende Kulissentexte in Keller/Friedhof und Platzhalter
der Spielstandauswahl; keine davon stammt aus den neuen Black-Market-Texten.

Vorschauen: [Kiosk](previews/black-market-kiosk.png) ·
[Angebotstafel](previews/black-market-board.png) ·
[Händlerdialog](previews/dealer-dialogue.png).

Händlerdialog geprüft: 31 Prüfungen Headless und 32 in Forward+, dazu
275 Engel-Dialogprüfungen und 69 Black-Market-Raumprüfungen als Regression.
