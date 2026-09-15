# Schlüssel zum Automatenraum

Die Automatentür beginnt verschlossen. Wer das Messer vom Tisch wirft, erhält
einmalig die **Schlüsselkarte** in seiner Sammlung. Es erscheinen dabei weder
eine Meldung noch eine Kartenenthüllung. Die Karte gehört nicht zu den Pack-
oder Zufallsbelohnungen und kann weder ins Kampfdeck noch verbessert werden.

Bis zum ersten Fund liegt die Karte mit dem normalen Kartenrücken nach oben
unter der Klinge. Sobald sie freigeschaltet ist, verschwindet sie vom Messer,
auch von bereits geladenen weiteren Messern. Nach Raumwechseln und Neustarts
bleiben die Messer ohne Karte. Fundhistorie und gespeicherte Türfreischaltung
verhindern eine erneute Anzeige auch ohne verbliebene Kartenkopie.
Ihr goldenes Schlüsselmotiv verwendet ein grobes Pixelraster.

In ihrer Detailansicht ersetzt **Zur Tür** den Deck-Button. Die Karte fährt
zurück, der Blick dreht sich zur Tür, und erst dann schwingt diese auf. Der
Spieler bleibt davor stehen und kann sie anschließend anklicken, um zum
Automaten zu gehen. Der Rückweg bleibt verfügbar. Die Karte bleibt erhalten,
und der freigeschaltete Zugang wird mit der Sammlung gespeichert. Ein kompletter
Spielreset entfernt Karte und Freischaltung.

Die Sammlung aus dem Hauptmenü übergibt dieselbe Aktion an Main. Dort endet
zuerst der Aufwach-Blur, damit die anschließende Türöffnung sichtbar ist.

Die Kameradrehung kann über `Main.door_key_look_duration` angepasst werden.
Der Status liegt in `collection.metadata.slot_room_unlocked`; die Karten-ID
ist `slot_room_key`.
