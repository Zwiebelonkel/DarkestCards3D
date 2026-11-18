# Karte in der Detailansicht drehen

In der normalen Sammlung und an der Sonderkartenwand lässt sich die geöffnete
Detailkarte mit gedrückter linker Maustaste frei drehen. Der erste Druck muss
die Karte treffen. Anschließend funktioniert das Ziehen auch außerhalb ihrer
Fläche. Horizontale und vertikale Bewegung drehen um die Kameraachsen, ohne
Winkelbegrenzung; auch die Rückseite lässt sich erneut greifen.

Nach dem Loslassen bleibt die Ausrichtung stehen. Ein Klick daneben oder
**Escape** schließt die Ansicht und lässt die Karte zurückfliegen.
**„Deck ansehen“** schließt ebenfalls per Escape oder Klick daneben.
Escape hat dabei Vorrang vor Pause und Hauptmenü. Während eines Einflugs wird
der Rückflug vorgemerkt; wiederholte Tastendrücke während des Rückflugs werden
abgefangen. Aktive Dreh-/Ziehgesten werden beendet, ohne Deckkarten zu entfernen.
Kartenwechsel und erneutes Öffnen beginnen mit der
normalen Ausrichtung, beim Schließen wird der ursprüngliche Transform
wiederhergestellt. Pause, Fensterfokusverlust und Eingabesperren beenden das
Ziehen. Der „Zum Deck hinzufügen“-Button bleibt unabhängig klickbar, auch wenn
er die Karte überlappt. Die Ausrichtung wird nicht gespeichert.

`scripts/card/CardDetailRotation.gd` teilt Quaternion-Rotation und geometrische
Trefferprüfung zwischen `CollectionScreen.gd` und `UpgradeWallCollection.gd`.
Der Helfer verändert weder Position noch Skalierung. Die Sammlung nutzt vor
dem Start zusätzlich ihre echte vorderste Physics-Trefferprüfung; die
Sonderkartenwand verwendet ihre bestehende GUI-Eingabefläche.

## Lokale Prüfung am 15.11.2026

- `collection_escape_test.tscn`: 25 Prüfungen bestanden, einschließlich der
  echten Hauptszene und der eigenständigen Sammlung, leerem und gefülltem Deck,
  Escape während Einflug, Kartenwechsel und Ziehen, wiederholtem Escape,
  unverändertem Deckinhalt sowie normalem Pause-Verhalten nach dem Schließen.
  Bestehende ObjectDB-Warnung beim Beenden, keine Script- oder Shaderfehler.
- `card_detail_rotation_test.tscn`: 34 Prüfungen im Forward+-Renderer bestanden,
  inklusive echter Eingabewege, 180-/360-Grad-Drehung, Greifen der Rückseite,
  Loslassen außerhalb, Ausrichtungsbeibehaltung, Fokusverlust, Pause,
  Kartenwechsel, Rückflug und überlappendem Deck-Button. Keine Enginefehler.
- `collection_interaction_test.tscn`: 29 Prüfungen bestanden; bestehende
  ObjectDB-Warnung beim Beenden, keine Script- oder Shaderfehler.
- `upgrade_wall_collection_test.tscn`: 21 Prüfungen bestanden.
- `wall_collection_focus_test.tscn`: 46 Prüfungen in der echten Hauptszene mit
  Raumwechsel, Fokus, Detailflug und Rückkehr bestanden; keine Enginefehler.

Alle Läufe verwendeten eine isolierte Projektkopie mit umgeleiteten
Spielständen. Die vier Bilder unter `docs/validation/card-detail-rotation/`
zeigen Vorderseite, schräge Drehung und Rückseiten beider Sammlungen.
