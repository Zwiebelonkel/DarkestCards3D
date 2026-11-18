# Betten im Jackpot-Raum

Die beiden bereits platzierten Betten `EmptyRoom/bed` und `EmptyRoom/bed2`
erhalten beim Hover eine gelbe Kontur. Ein Linksklick startet einen festen
Ablauf: hinlaufen, an der freien Längskante um 180 Grad drehen und sich auf die
Matratzenkante setzen. Im Sitzen blickt die Kamera gezielt auf die Mitte des
jeweils anderen Bettes, einschließlich der passenden leichten Blickneigung.

Escape lässt den Spieler aufstehen, von der Matratze in den Gang treten und
direkt zum ursprünglichen Standpunkt zurückgehen. Die Kamera dreht sich dabei
gleichmäßig in einer Richtung zur Schmiedemaschine. Am ursprünglichen Standpunkt
ist die Schmiede direkt bedienbar; die logische A/D-Seite folgt diesem Blickwinkel.
Ein früher Escape-Druck während des Hinwegs merkt
den Rückweg vor. Wiederholte Klicks oder Escape-Drucke starten keine zweite
Bewegung. Raumwechsel, andere Dialoge und Journal bleiben währenddessen gesperrt.

Der Hinweg führt erst durch die freie Gasse vor den Fußenden und dann entlang
der freien Bettseite. Der Rückweg nimmt den direkten Weg durch den Mittelgang,
ohne Zwischenstopps und zusätzliche Drehungen an den Ecken. Er verwendet
55 Prozent der normalen Laufdauer, das Aufstehen 65 Prozent der Sitzdauer.
Schritte und Kamera-Bobbing verwenden die vorhandene Laufbewegung von Main;
beim Rückweg ist das Wippen auf 35 Prozent reduziert. Im Sitzen und beim
Umdrehen entstehen keine neuen Schritte. Pause außerhalb der Sitzsequenz
entfernt die Hover-Kontur.

`scripts/props/BedSeating.gd` wird von Main eingerichtet. Bettpositionen,
Geometrie und Materialien bleiben als Autorenressourcen erhalten; nur lokale
Picking-Areas und temporäre Konturen werden ergänzt. Sitzposition und Laufweg
werden aus den tatsächlich geladenen Bettmaßen abgeleitet. Es werden keine
Karten, Spielwerte oder Sitzpositionen gespeichert.

## Validierung am 15.11.2026

- `bed_seating_test.tscn`: 65 Prüfungen im Forward+-Renderer bestanden. Beide
  echten Betten, Hover-Wechsel, vollständige Sitz-/Rückwege, Blick auf das andere
  Bett, Kamera-Rückstellung, Pause und frühes Escape wurden geprüft. Für beide
  Rückwege wurden die kürzere Dauer, die direkte Strecke und eine Kameradrehung
  ohne Richtungswechsel bestätigt.
- Auf allen gemessenen Hin- und Rückwegen bleibt mindestens 1.25 Einheiten Abstand zu
  beiden Bettgrundflächen. Die letzte Bewegung auf die Matratzenkante gehört
  zur anschließenden Sitzanimation.
- `room_travel_test.tscn`: 71 Prüfungen bestanden.
- `deck_fan_depth_test.tscn`: 29 Prüfungen bestanden.

Die Bettprüfung endet ohne Enginefehler oder Warnungen. Die vorhandenen Raum-
und Deckprüfungen melden ObjectDB-Warnungen beim Beenden, keine Script- oder
Shaderfehler. Alle Läufe verwendeten eine isolierte Kopie mit umgeleiteten
Spielständen. Bilder und Messbericht: `docs/validation/bed-seating/`.
