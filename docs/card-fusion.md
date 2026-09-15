# Kartenschmiede

Im Automatenraum steht links neben der Slotmaschine, gegenüber der Upgrade-Wand,
eine Schmiedewerkbank mit Amboss und Glutofen. Beim Hover fährt die gemeinsame
Raumkamera näher heran. Karten, Ablageplätze, Beschriftungen und Bedienelemente
sind echte 3D-Objekte.

Die Rückwand zeigt eigene Kartenexemplare mit zwölf Karten pro Seite;
Sonderkarten erscheinen nicht in der Auswahl.
Die Pfeile wechseln Seite oder Seltenheit; das Mausrad blättert ebenfalls.
Ein Linksklick wählt eine Karte für einen der fünf Plätze aus. Ein weiterer Klick
auf die Karte oder ihren Ablageplatz entfernt sie. Rechtsklick verändert weder
die Auswahl noch die Ansicht. Die Werkbank zeigt keine vergrößerte Kartenvorschau,
keinen Untertitel und keine zusätzlichen Hinweistexte unter den Bedienelementen.

Fünf Karten derselben Seltenheit lassen sich mit **Fusionieren** gegen eine
zufällige Kampfkarte der direkt folgenden Seltenheit eintauschen. Unterschiedliche
Kartentypen dürfen kombiniert werden. Es fallen keine Soul Coins an.

Gewöhnlich → Ungewöhnlich → Selten → Episch → Legendär → Mythisch → Exotisch.

Die fünf gewählten Exemplare werden verbraucht. Die neue Karte wird wie ein neuer
Kartenfund auf Stufe 1 erzeugt, einschließlich neuer Effekt- und Holo-Würfe.
Bestehende Upgrades des Kartentyps gelten weiterhin. Die Anzeige verwendet
dieselben Werte und Effekte wie die Karten im Kampfdeck.

Sonderkarten sind geschützt und werden in der Schmiede ausgeblendet.
Exemplare im Kampfdeck sowie Ereignis- und Geheimniskarten sind ebenfalls geschützt.
Sie bleiben mit einer Kennzeichnung sichtbar und können nicht ausgewählt werden.
Exotische Karten haben keine weitere Fusionsstufe. Nicht zufällig erhältliche
Geheimniskarten sind auch als Ergebnis ausgeschlossen.

Kartenverbrauch und Belohnung werden gemeinsam gespeichert, bevor die
Schmiedeanimation startet. Bei einem Speicherfehler bleiben die Eingaben erhalten;
beim Verlassen der Szene nach dem Speichern bleibt die Belohnung in der Sammlung.
Während der Animation sind Drehen und Raumwechsel gesperrt. **Weiter** beendet
die Präsentation der bereits gespeicherten Belohnung.

Die Szene `scenes/props/FusionWorkbench.tscn` wird als `EmptyRoom/FusionWorkbench`
eingesetzt. `FusionWorkbench.gd` steuert die Karten und die Bedienung,
`FusionWorkbenchModel.gd` erzeugt das Werkbankmodell. Die Fusionsregeln und die
gemeinsame Speicherung liegen in `CollectionManager.gd`. `fusion_completed`
aktualisiert auch die Kartensammlung im Hauptraum.
