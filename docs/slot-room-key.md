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

In der freien Ansicht des Hauptraums klappt am unteren Bildschirmrand eine Schlüsselablage
hoch, entsprechend der Level-Anzeige am oberen Rand. Sie zeigt alle eigenen,
noch unbenutzten Zugangsschlüssel. Im Hauptraum dreht ein Klick den Blick zur
passenden Tür, die anschließend aufschwingt. Der Spieler bleibt davor stehen
und kann sie anklicken, um den Raum zu betreten. In den Nebenräumen lässt sich
die Schlüsselablage weder öffnen noch benutzen.

Der Besitz allein öffnet keinen Zugang. Alle vier Türen bleiben gesperrt,
bis der passende Schlüssel über die Ablage benutzt und die Freischaltung
erfolgreich gespeichert wurde. Ein Türklick kann die Benutzung nicht ersetzen.

Nach erfolgreichem Speichern verschwindet der benutzte Schlüssel aus der Ablage.
Besitz und Karteninstanz bleiben in der Sonderkartensammlung erhalten. Die normale
Sammlung zeigt keine Zugangsschlüssel mehr. Ein kompletter Spielreset entfernt
Karten und Freischaltungen.

Sobald alle Zugangsschlüssel benutzt sind, verschwindet die gesamte Ablage
einschließlich Scharnier. Sie lässt sich dann auch am Bildschirmrand nicht
mehr öffnen. Nach einem Spielreset steht sie wieder zur Verfügung.

Die Ablage verwendet `metadata.slot_room_unlocked` und `metadata.area_access`
auch für ältere Spielstände: Bereits geöffnete Zugänge gelten als benutzt,
ein lediglich besessener Schlüssel bleibt in der Ablage. Sie ist während Kämpfen,
Dialogen, Detailansichten, Pause und Kamerafahrten gesperrt.

Die Kameradrehung kann über `Main.door_key_look_duration` angepasst werden.
Der Status liegt in `collection.metadata.slot_room_unlocked`; die Karten-ID
ist `slot_room_key`.
