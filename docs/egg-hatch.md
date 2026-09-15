# Egg → Chick → Chicken

Wird die Karte `eg` (Egg) im Kampf tatsächlich zerstört, erscheint mit **25 %
Wahrscheinlichkeit** am selben Platz eine neue `chick`-Karte (Chick). Der Wurf
erfolgt für beide Seiten und jedes Ei einzeln, auch bei gleichzeitigen Toden.
Bei den übrigen 75 % gilt das normale Nachziehen; ohne Nachziehkarte bleibt
der Platz leer und das letzte Ei kann den Kampf verlieren.

Die Sammlung muss kein Chick enthalten. Das Schlüpfen verbraucht keine Karte
vom Nachziehstapel und fügt der Sammlung keine Karte hinzu. Das Chick startet
mit seinen normalen Katalogwerten und Effekten, ohne Schäden, Vergiftung oder
andere Zustände des Eis zu übernehmen. Es erhält eine eigene Kampfidentität.

Der gemeinsame Todesablauf behandelt normale Angriffe, Gegenangriffe, Dornen,
Vergiftung und Flächenschaden. Last Stand und Grave Return verhindern den Tod
vor dem Wurf. Ein überlebendes oder gestohlenes Ei schlüpft nicht und verbraucht
keinen Wurf. Stirbt das Chick später, gilt wieder das normale Nachziehen.

## Wachstum nach fünf Runden

Jedes lebende Chick auf dem Tisch, auch ein regulär gezogenes, wird nach fünf
vollständig überlebten Runden im selben Platz durch ein frisches `chicken`
ersetzt. Eine Runde umfasst einen Zug beider Seiten, insgesamt also zehn
vollständige Züge. Ein beim Eintreffen bereits laufender Zug zählt nicht mit.
Zu Zugbeginn merkt sich der Tisch die vorhandenen Chicks und zählt deren
Überleben am Zugende. Ein gestorbenes oder vom Tisch entferntes Chick zählt
nicht weiter. Im Nachziehstapel pausiert das Wachstum; Steel erhält das Alter.

Wachstum ist kein Tod und löst keine Kill-Effekte, Blut- oder Todesanimation
und keinen Ersatz-Zug vom Stapel aus. Das Chicken erhält eine neue
Kampfidentität und seine Grundwerte (3 Angriff, 10 Leben, Last Stand), ohne
Schäden, Buffs, Zustände, Upgrades oder Holo des Chicks. Auch diese Karte bleibt
nur im laufenden Kampf. Ein neuer Kampf beginnt ohne alten Wachstumsfortschritt.

## Mehrspieler

Im Mehrspieler-Modus würfelt ausschließlich der Host, genau einmal pro Tod.
Der Todesauftrag behält das Ergebnis bis zur Ersetzung; doppelte Todesmeldungen
und wiederholte Zustände würfeln nicht erneut. Ein separater Zufallsgenerator
trennt die Schlüpfchance von Kamera- und Bluteffekten.
Nur der Host erzeugt geschlüpfte Chicks und herangewachsene Chickens.
Das Alter `chick_survived_turns` reist im Kampfzustand,
auch wenn Steel die Karte in einen Nachziehstapel verschiebt. Ein
`spawn_kind` im übertragenen Slot-Zustand sorgt dafür, dass es bei Mitspielern
und Zuschauern direkt am Platz erscheint. Diese Animationsangabe bleibt außerhalb
der Kartendaten, damit eine später gestohlene und nachgezogene Karte wieder
normal vom Stapel kommt. Wiederholte Zustände spielen die Entwicklung nicht
erneut ab. Ein Match-Reset beendet auch laufende Wachstumsanimationen.
