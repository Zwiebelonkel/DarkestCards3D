# Prisoner in der Krypta

Der vorhandene `GraveyardRoom/Crypt/Prisoner` wird direkt vor dem Gitter
interaktiv. Seine platzierte Position, Ausrichtung, Skalierung und zwölf
Animationsframes bleiben erhalten. Hover wechselt zu `prisonerHover.png`,
ohne den aktuellen Frame oder dessen Laufzeit zurückzusetzen. Beim Verlassen
der Figur wird wieder die Idle-Animation verwendet.
Sprite und Augen-Leuchtmaterial verwenden kein Billboard. Die Klickfläche
übernimmt die feste Ausrichtung der Figur und dreht sich ebenfalls nicht
zur Kamera.

Linksklick öffnet einen Dialog mit fünf aufeinanderfolgenden Fenstern:

1. `*Lacht*`
2. `*Lacht*`
3. `*Furzt*`
4. `*Lacht*`
5. `*Scheisst sich ein*`

Die Sterne werden als Text angezeigt. Ein Klick während des Schreibens deckt
nur die aktuelle Zeile auf; der nächste Klick öffnet das folgende Fenster.
Nach dem fünften vollständigen Fenster schließt ein weiterer Klick den Dialog.
Jedes erneute Gespräch beginnt wieder mit dem ersten Fenster.

Der Controller erweitert den vorhandenen gemeinsamen NPC-Dialog und verwendet
dieselbe Sprachprobe und Silbenvariation wie der Jester. Der Pitch-Offset ist
`+3` statt `+6` Halbtönen. Es gibt keinen `sentenceEnd.mp3`-Player und keinen
Abschlusston, weder beim natürlichen Textende noch beim Überspringen.
Beim Öffnen des dritten und fünften Fensters wird zusätzlich `assets/sounds/SFX/fart.mp3`
einmal auf dem SFX-Bus abgespielt. Das Aufdecken derselben Zeile löst den Sound
nicht erneut aus. Schließen und Pause stoppen ihn zusammen mit der Stimme.

Das Gespräch hält die Nahansicht fest und sperrt Drehen, Journal sowie die
Rückwege zur Kreuzung. Esc schließt zunächst nur das Gespräch. Pause stoppt
die Stimme und schließt den Dialog. An der Kreuzung, in anderen Räumen und
beim Wegdrehen von der Krypta bleibt die Figur gesperrt. Gespräche ändern
weder Karten noch Währung oder Speicherstände.

## Klopapier gegen Weihwasser

### Einmalige Rückkehr zu Satan

Bei der ersten Rückkehr durch eine Raumtür in den Hauptraum nach dem Erhalt
von Weihwasser schwingt die Kamera in 2,8 Sekunden auf Satans Gesicht, wandert
höchstens 0,45 Einheiten (maximal acht Prozent der Entfernung) darauf zu und
verengt das Sichtfeld sanft auf 88 Prozent. Die Musik pausiert während der
gesamten Sequenz und läuft nach der Rückfahrt an derselben Stelle weiter.
Danach erscheinen vier Dialogteile:

1. „Wo warst du?“
2. „Du warst draußen, oder?“
3. „Mach es lieber nicht nochmal!“
4. „Ach egal, scheiß doch, mach was du willst. Fuck you.“

Beim Beginn des vierten Teils („Ach egal …“) wechselt Satan in seine
Lachanimation; beim Schließen kehrt er zur normalen Animation zurück.
Der Dialog nutzt die tiefe Satan-Stimme und ist auf Deutsch, Englisch,
Spanisch, Französisch und Polnisch verfügbar. Klicken deckt den Text auf
und schaltet anschließend weiter; Leertaste, Enter und Esc funktionieren
ebenso. Nach dem letzten Teil kehren Kameraposition und Sichtfeld in 2,4
Sekunden zur normalen Ansicht zurück. Der Blick zeigt von der benutzten
Eingangstür weg ins Rauminnere: vom Friedhof zum Spieltisch, vom Keller zum
Packshop. Auch die anschließenden A/D-Drehungen starten von dieser Seite.
Bewegung, Weltinteraktion und Pause bleiben während der gesamten Szene
gesperrt. `metadata.holy_water_return_dialogue_seen` in der Sammlung wird
vor Beginn atomar gespeichert und verhindert Wiederholungen nach Laden.
Ein fehlgeschlagener Speicherversuch verbraucht den Auslöser nicht.
Der Trainingsmodus löst die Szene nicht aus.

`tests/holy_water_return_test.tscn` prüft den echten Raumrückweg,
Kameraziel, Zoom, Dialogreihenfolge, Sprachwechsel, den abschließenden Blick
ins Rauminnere und den Wiederholungsschutz nach Laden. Die Variante
`basement_item_return_test.tscn` prüft ausdrücklich den Keller → Packshop.

### Übergabe in der Krypta

Direkt vor dem Gefangenen in der Krypten-Nahansicht kann die Kartenleiste am
unteren Bildschirmrand geöffnet werden. Ein Klick auf **Klopapier** übergibt
eine Kopie und vergibt einmalig die Spezialkarte **Weihwasser**. Die Karte wird
vor der Kamera eingeblendet und in der Spezialkarten-Sammlung unter
**Story-Karten / Story Cards** einsortiert (`card_group: story_cards`). Sie hat
keine Kampfwerte, Türfunktion oder Zufallsdrop-Chance.

Hub, entfernte Friedhofsansicht, Wegdrehen, Pause, offene Gespräche und andere
gesperrte Interaktionen erlauben keine Übergabe. Andere Türschlüssel können vor
dem Gefangenen nicht verwendet werden. Gespräche selbst bleiben unverändert.

`CollectionManager.exchange_prisoner_toilet_paper()` speichert Verbrauch und
Belohnung zusammen als atomaren Sammlungsschnappschuss. Bei einem Schreibfehler
bleibt das genaue Klopapier-Exemplar erhalten. Die Entdeckungshistorie beider
Karten bleibt bestehen: Weder ein erneutes Lösen des Pumpenrätsels noch weitere
Übergaben können Belohnungen duplizieren, auch nach Laden oder Kartenverlust.

Die native Pixelgrafik wird aus `holy_water.svg` nach `holy_water.res` gebacken.
Karte, Erklärung und Gruppenüberschrift sind in den fünf vorhandenen Sprachen
lokalisiert. Neue Story-Karten können über `card_group: story_cards` dieselbe
Gruppe verwenden.

`tests/prisoner_trade_test.tscn` besteht mit **25 Prüfungen** sowohl headless als
auch gerendert: echter Weg zur Krypta, echter Kartenleisten-Klick, Kontext- und
Dialog-Sperren, fehlgeschlagener Speicherversuch, Wiederholungsschutz, Laden und
die tatsächliche Gruppenzeile. Die bisherigen Dialog-, Kartenleisten- und
Sammlungsprüfungen bestehen mit **70 + 87 + 21** Prüfungen. Insgesamt sind es
**203 Prüfungen** ohne Skript- oder Shaderfehler. Einige vollständige Szenentests
melden weiterhin die bekannte ObjectDB-Warnung beim Beenden. Steam und Exporte
wurden hierfür nicht geprüft.

Bilder: `docs/validation/prisoner-trade/` (Kartenleiste, Belohnung und Story-Gruppe).

`tests/prisoner_dialogue_test.tscn` prüft die echte platzierte Figur über
Viewport-Eingaben, Animation, Reihenfolge, Stimme, Sprachfassungen,
Kameraschutz, Pause und unveränderte Profildateien. Die bestehenden
Krypta-Prüfungen prüfen außerdem, dass die Beacon-Rückkehr die aktuelle
Blickrichtung während des ganzen Wegs beibehält.
