# Event-Karten

Alle sechs Event-Kartentypen stehen jedem Spieler von Anfang an zur Verfügung.
Sie sind keine Sammelkarten und können nicht aus Kartenpacks oder als
Sammlungsbelohnung gezogen werden. Im Journal zeigt der eigene Reiter
**Event-Karten** direkt nach **Sonderkarten** alle Events mit ihren Regeln.
Die Collection enthält keine Event-Plätze oder NEW-Labels; auch das Austeilen
und Anzeigen der Event-Hand schreibt keine Entdeckungsdaten in den Spielstand.

Der gemeinsame Event-Stapel wird intern verwaltet und enthält 24 zufällig
gemischte Karten. Auf dem Tisch erscheint kein zusätzlicher Stapel oder
Event-Zähler. Die Tischansicht nutzt die ursprüngliche Kameraposition.
Zu Beginn jedes Matches erhält jeder Spieler drei zufällige Event-Karten aus
diesem Stapel. Danach bleiben 18 der 24 Karten im gemeinsamen Ziehstapel.
Die Startkarten sind bereits im ersten eigenen Zug vor dem Angriff spielbar.
Das gilt gegen die KI und im Online-PvP für beide Spieler; Zuschauer erhalten
keine eigene Hand. Jedes neue Match verteilt die Startkarten erneut.
Ein Kill durch eine Kampfkarte mit `draw_on_kill` (beispielsweise Mailman)
zieht eine Event-Karte auf die Hand ihres Besitzers. Normales Nachziehen gibt
keine Event-Karten. Auch tödliche Gegenangriffe,
Dornen und Flächentreffer können den Effekt auslösen; pro getöteter Karte
wird höchstens einmal gezogen. Ein gleichzeitiger Tod verhindert den Draw nicht.

Die Kartenhand zeigt am unteren Bildschirmrand nur die oberen Kartenränder.
Hover hebt eine Karte an. **Switch aktiviert sich direkt mit einem Klick,
ohne Zielauswahl.** Gezielte Events werden zuerst angeklickt und anschließend
durch Klick auf eine passende Tischkarte ausgespielt.
Rechtsklick oder Escape bricht die Auswahl ab. Große Hände lassen sich blättern.

Pro eigenem Zug darf optional **eine Event-Karte vor dem Angriff** ausgespielt
werden. Das Event verbraucht den Angriff nicht. Mit Abschluss des Angriffs
endet der Zug; dabei gezogene Events warten auf den nächsten eigenen Zug.
Die KI erhält ebenfalls drei Startkarten und befolgt dieselben Regeln.
Event-Hände gehören ausschließlich zum laufenden Match und werden nicht in
der dauerhaften Sammlung oder im gespeicherten Kampfdeck abgelegt.
Sind alle eigenen Tischkarten blockiert,
kann der Spieler nach einem optionalen Event über „Zug beenden“ passen.

| Event | Anzahl | Wirkung |
| --- | ---: | --- |
| Switch | 6 | Tauscht je eine zufällige Karte der beiden Kampf-Ziehstapel. Beide Stapel müssen noch Karten enthalten. |
| Block | 5 | Blockiert eine gewählte gegnerische Tischkarte bis zum Ende ihrer nächsten zwei eigenen Züge. Sie kann nicht angreifen oder kontern, bleibt aber angreifbar. Passive Effekte bleiben aktiv. |
| Steel | 1 | Mischt eine gewählte gegnerische Tischkarte zufällig in den eigenen Kampf-Ziehstapel. Der Gegner zieht sofort Ersatz, sofern sein Stapel noch Karten enthält. |
| Stärke ×1,2 | 7 | Multipliziert Angriff, maximale und aktuelle Lebenspunkte einer eigenen Tischkarte mit 1,2. |
| Stärke ×1,5 | 3 | Multipliziert diese Werte mit 1,5. |
| Stärke ×2 | 2 | Verdoppelt diese Werte. |

Verstärkungen werden auf ganze Werte aufgerundet und gelten für die laufende
Karteninstanz im Match. Steel bewahrt Schaden, Verstärkungen, Gift, Block und
bereits verbrauchte einmalige Effekte. Sammlung und gespeicherte Decks werden
durch Events nicht verändert. Ein nicht ausführbares Event bleibt auf der Hand.

Gespielte Events landen auf einem Ablagestapel. Ist der Event-Ziehstapel beim
nächsten erlaubten Ziehen leer, wird nur die Ablage neu gemischt. Karten auf
einer Hand bleiben dort. Sind auch keine abgelegten Events vorhanden, wird
keine Karte gezogen.

Online verwaltet der Host Stapel, Zufall, Ziele und Zugregeln. Der Gast erhält
nur seine eigene Event-Hand. Gegner und Zuschauer sehen die öffentliche
Ausspielanimation. Verdeckte Handkarten und Ziehreihenfolgen bleiben verborgen.

Die Verteilung und Beschreibungen stehen in `scripts/events/EventDeck.gd`.
