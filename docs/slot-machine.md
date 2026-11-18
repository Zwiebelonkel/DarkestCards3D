# Soul Slots

Die importierte Maschine steht im zweiten Raum direkt in Blickrichtung nach
der Türfahrt. Sie ist als eigene Szene `scenes/props/SlotMachine.tscn` aufgebaut;
das originale `slots.glb` bleibt unverändert.

Der Jackpot-Schriftzug flackert während des Spins in kurzen, unregelmäßigen
Hell-Dunkel-Impulsen. Sobald die letzte Rolle stoppt, leuchtet er wieder
gleichmäßig, auch wenn die Auszahlung erst erneut gespeichert werden muss.
Die lokalisierte Beschriftung und der Zufallsgenerator für Gewinne bleiben erhalten.

- Grüner **+**-Button und roter **−**-Button: 1, 2, 5, 10, 20 oder 50 Soul Coins wählen;
  danach geht es in Zehnerschritten weiter (60, 70, 80, …), ohne festes Einsatzmaximum.
  Beim Verringern gelten dieselben Stufen rückwärts.
- **BET**: Einsatz bestätigen. Der Button blinkt, solange die Bestätigung fehlt;
  nach dem Bestätigen blinkt stattdessen **SPIN**. Dabei werden noch keine Coins abgezogen.
- **SPIN**: Den bestätigten Einsatz einmal abbuchen und die drei Originalrollen drehen.
  Beide Hinweise blinken hart (0,4 Sekunden an, 0,4 Sekunden aus), auch beim Hover.
  Während eines Spins, bei Pause und beim Wegdrehen ist das Blinken aus.
- Die Rollen stoppen nacheinander. Es zählt das farbige Effektsymbol zwischen
  den beiden goldenen Pfeilen; drei gleiche Symbole gewinnen. Die Symbole sitzen
  direkt auf den dunklen Rollenflächen und drehen sich mit den Rollen.
- Ein bestätigter Einsatz bleibt für weitere Spins gewählt. Nach einer Änderung
  mit +/− muss er erneut mit BET bestätigt werden.

| Drei gleiche Symbole | Auszahlung |
| --- | ---: |
| Grünes Heilkreuz (Heilung) | Einsatz × 5 |
| Rotes Herz (Lebensraub) | Einsatz × 10 |
| Blauer Schild | Einsatz × 15 |
| Goldene Krallenspuren (Dreifachschlag) | Einsatz × 30 |
| Violetter Schädel (Fluch) | Einsatz × 50 |

Die Auszahlung enthält den Einsatz: Ein Einsatz von 2 SC mit drei roten Rollen
zieht zuerst 2 SC ab und zahlt anschließend 20 SC aus. Gemischte Farben zahlen
nichts aus. Jede der fünf Farben hat auf jeder Rolle unabhängig dieselbe
Chance; ein beliebiger Dreier tritt mit 4 % Wahrscheinlichkeit auf. Die
erwartete Auszahlung beträgt 88 % des Einsatzes.

Die Tabelle mit denselben Effektsymbolen, der Kontostand, der gewählte Einsatz und das letzte Ergebnis
stehen direkt an der Maschine. Während der Animation sind die Tasten gesperrt.
A/D und die Rückkehr durch die Tür bleiben möglich; ein bereits gestarteter
Spin läuft weiter. Pause hält auch die Animation an.

Zusätzlich zu den Rollen-Klicks läuft `rolling.mp3` räumlich an der Maschine
über den SFX-Bus. Der Sound startet nur bei einem angenommenen Spin und läuft
bei Bedarf in einer Schleife. Sobald die erste Rolle ihr Ergebnis zeigt,
sinken Tonhöhe (1,0 auf 0,4) und Lautstärke gleichmäßig bis zum letzten
Rollenstopp. Dann endet der Sound auch bei einem Auszahlungs-Speicherfehler.
Ein neuer Spin setzt Tonhöhe und Lautstärke zurück; Pause hält die Wiedergabe
und das Ausblenden gemeinsam mit der Rollenanimation an.

Die Rolling-Spur startet mit 0 dB am eigenen Player: Die Aufnahme selbst ist
bereits leise und wird zusätzlich räumlich sowie über SFX/Master gedämpft.
`tests/rolling_audio_audibility_test.tscn` prüft deshalb das tatsächlich gemischte
SFX-Signal bei ungefähr vier Metern Abstand, zusätzlich zum Wiedergabestatus.

Einsatz und festgelegte Auszahlung werden gemeinsam in der bestehenden
Währungsdatei gespeichert. Nach einem Neustart wird ein unterbrochener Spin
einmal abgeschlossen. Szenenwechsel verwerfen keine Gewinne, und wiederholte
Klicks lösen keine doppelte Abbuchung aus. Bei einem Speicherfehler kann die
Auszahlung über SPIN erneut versucht werden, ohne einen neuen Einsatz abzuziehen.

Die Werte, Farben und Effektsymbole stehen zentral in `scripts/props/SlotMachine.gd`.
`tests/slot_currency_test.tscn` prüft Speicherung und Wiederherstellung;
`tests/slot_machine_test.tscn` prüft echte Mausklicks, Rollenflächen, Gewinne und
Raumwechsel. Beide laufen mit dem vorhandenen isolierten Test-Runner, ohne
echte Spielstände zu verändern.
