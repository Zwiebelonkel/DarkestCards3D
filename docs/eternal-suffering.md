# Ewiges Leiden und Draw on Death

`eternal_suffering` ist ausschließlich der Creditkarte (`credit_card`)
angeboren und ersetzt ihre bisherigen Grundeffekte. Packs, zufällige Effekte,
Instanzbelohnungen und gekaufte Effekte können es nicht vergeben. Online darf
nur die Creditkarte diesen angeborenen Effekt mitbringen.

Beim Kontakt ihres eigenen Angriffs verursacht die Creditkarte ihren normalen
Trefferschaden, überträgt den Zustand auf das überlebende gewählte Ziel und
stirbt sofort. Ein Schild oder ein Treffer ohne Schaden verhindert die
Übertragung nicht. Eigene Rüstung, Schilde und Überlebensfähigkeiten verhindern
die Selbstopferung nicht. Ein ausgesetzter oder blockierter Angriff überträgt
keinen Zustand.

Das Ziel erleidet zu Beginn seiner eigenen Züge 1, 3, 5, 7 usw. Schaden.
Rüstung und Ersttrefferschild reduzieren diesen Schaden nicht. Einmalige
Überlebenseffekte können den Tod hinauszögern, entfernen den Zustand aber nicht.
Es gibt keine Ablaufdauer. Erneute Anwendung setzt den Schadenswert nicht zurück.
Das Ziel bleibt beim eigenen Angriff am Leben und überträgt den Zustand nicht.

Stirbt die infizierte Karte, erhalten ihre lebenden direkten Nachbarn auf
derselben Tischseite einmalig normales Gift für drei eigene Züge. Das gilt für
jede Todesursache. Der Giftschaden entspricht dem Leidens-Schadenswert beim Tod:
Ein tödlicher 5er-Leidens-Tick vergiftet die Nachbarn für 5 Schaden, nicht 7.
Das neue Gift tickt erstmals im nächsten eigenen Zug, unabhängig von der
Slotreihenfolge. Es überträgt kein Ewiges Leiden und verbreitet sich beim Tod
eines so vergifteten Nachbarn nicht erneut. Ein überlebter tödlicher Treffer
oder ein bereits geheilter Zustand löst die Verteilung nicht aus.

Nur ein positiver Heilungseffekt eines direkt benachbarten Verbündeten mit
`neighbor_heal` entfernt Ewiges Leiden. Normale Heilung und Regeneration tun
das nicht. Nachbarheilungen werden vor periodischem Schaden ausgewertet,
unabhängig davon, ob der Heiler links oder rechts steht. Auch eine Heilung bei
vollen HP kann den Zustand entfernen. Das rote Symbol oben rechts verwendet
`assets/effects/eternalSuffering.png` und zeigt den nächsten Schadenswert.

Der Zustand und seine Steigerung bleiben bei Online-Updates und Steel erhalten.
Ein neues Match setzt ihn zurück.

Alle Statussymbole und ihre Zahlen werden vor dem Kartenbild und seinen
Shader-Pässen gezeichnet. Auch ein vorstehendes Kartenbild kann sie nicht verdecken.

## Draw on Death

`draw_on_death` ersetzt `draw_on_kill`. Beim tatsächlichen Tod der Effektkarte
zieht **ihr Besitzer genau eine Event-Karte** aus dem gemeinsamen Stapel.
Die Todesursache spielt keine Rolle, einschließlich Gift, Ewiges Leiden und
Selbstopferung. Überleben mit 1 HP oder Wiedergeburt löst keinen Kartenzug aus.
Das Töten anderer Karten zieht keine Karte mehr. Wiederholte Todesmeldungen
ziehen keine weitere Karte. Nur die Autorität vergibt die Belohnung.

Bestehende `draw_on_kill`- und alte `deck_burn`-Effekte werden beim Lesen in
`draw_on_death` umgewandelt und beim normalen Speichern dauerhaft übernommen.
Identität, Holo, Kartenlevel und andere Effekte bleiben erhalten. Das bestehende
Symbol wird weiterverwendet; Name und Regeln sind in allen fünf Sprachen geändert.

## Prüfung

`eternal_suffering_test.tscn` prüft den tatsächlichen Kampfablauf auf beiden
Tischseiten: Selbstopferung, Schilde, Steigerung, Heilung, Überlebensschutz,
Todesbelohnungen, Statusanzeigen, Rekonstruktion und die Erwerbsgrenzen.
Der gerenderte Lauf prüft zusätzlich die Darstellung und speichert Vorschauen.
`eternal_suffering_network_test.tscn` verwendet zwei lokale ENet-Peers für
Statusübertragung, Heilung und die private Event-Hand des richtigen Besitzers.
Live Steam und exportierte Builds wurden nicht getestet.

Nachweise und Vorschauen: `docs/validation/eternal-suffering/`.

Die Erweiterung vom 18.11.2026 besteht 173 lokale Kampfprüfungen, 178 Prüfungen
im gerenderten Lauf, die lokale ENet-Prüfung einschließlich der Todesvergiftung,
283 allgemeine Kampfprüfungen und 9095 Journal-/Übersetzungsprüfungen.
`status-badges-over-artwork.png` zeigt den gezielten Verdeckungstest:
Ein undurchsichtiges Bild liegt vor den Symbolen, Gift und Stun bleiben sichtbar.
Siehe `status-and-spread.log` für die Ergebnisse.
