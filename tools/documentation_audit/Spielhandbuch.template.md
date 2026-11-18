# Darkest Cards 3D

## Spieldokumentation

Stand 15 November 2026

Dieses Dokument beschreibt den gegenwärtigen Projektstand von Darkest Cards 3D als zusammenhängendes Spielhandbuch und als Nachschlagewerk für die Weiterentwicklung. Es erklärt den Weg vom ersten Spielstart über Kartenbeschaffung und Deckbau bis zu Kämpfen, dauerhaftem Fortschritt und den Nebenräumen. Die vollständigen Kartenlisten und ein Prüfbericht stehen im Anhang.

Die Dokumentation enthält bewusst alle Geheimnisse und Entscheidungen. Sie ist damit auch eine Entwicklerreferenz und keine spoilerfreie Anleitung. Maßgeblich sind die eingebundenen Szenen, die tatsächlich ausgeführten Skripte und die aktuellen Kartendaten. Frühere Einzeldokumente werden bei abweichenden Werten nicht als aktuelle Spielregel übernommen.

## 1 Spielidee und vollständiger Spielkreislauf

Darkest Cards 3D verbindet ein rundenbasiertes Sammelkartenspiel mit einem düsteren, räumlichen Hub. Der Spieler steht an festen Kamerapositionen in einer Hospitalumgebung. Automaten, Karten, Bücher, Türen und Figuren bilden die Bedienoberfläche direkt in der 3D-Welt. Es gibt keine frei steuerbare Spielfigur mit gewöhnlicher WASD-Fortbewegung.

Der zentrale Kreislauf lautet: Soul Coins verdienen, Packs kaufen und öffnen, Karten sammeln, ein Kampfdeck zusammenstellen, Karten verbessern und Storykämpfe oder Mehrspielerpartien bestreiten. Permanente Sonderkarten erweitern Einkommen, Startaufstellung, Fusionsmöglichkeiten und Raumzugänge. Nebenräume bieten weitere Bezugsquellen für Karten und Geld sowie Figuren, Dialoge und Geheimnisse. [Q01, Q02, Q03]

Der aktuelle Katalog enthält **118 Sammelkartentypen**: **93 Kampfkarten** und **25 Sonderkarten**. Sechs zusätzliche Eventtypen gehören ausschließlich zu laufenden Partien. Kampfkarten besitzen Angriff und Lebenspunkte; das Datenfeld `defense` meint Lebenspunkte und keinen gesonderten Rüstungswert. Ein Deck kann höchstens 20 Kampfkarten enthalten. Jede Seite hat fünf Tischplätze.

### 1.1 Ein sinnvoller erster Durchlauf

1. Im Hauptmenü einen der drei Spielstände wählen und auf Spielen klicken. Ein neuer Spielstand beginnt mit Level 1, 0 XP und 20 Soul Coins.
2. Satans Begrüßung abwarten oder die einzelnen Textabschnitte weiterklicken. Die Einführung weist auf Packshop und Sammlung hin.
3. Im Hauptraum zum Packshop drehen. Ohne Rabatt kosten vier Basic Packs zusammen 20 Soul Coins und enthalten insgesamt 20 Karten; darunter können auch Sonderkarten sein.
4. Packs tatsächlich öffnen und die Karten einsammeln. Erst die Übernahme in die Sammlung macht die gezogenen Exemplare dauerhaft verfügbar.
5. In der Sammlung Kampfkarten ins Deck aufnehmen. Ein nicht leeres Deck ist für reguläre lokale Kämpfe erforderlich; genau 20 Karten sind keine allgemeine Startvoraussetzung.
6. Am Spieltisch Story wählen und Level 1 beginnen. Für Training müssen fünf unterschiedliche Deckexemplare auswählbar sein.
7. Belohnungen in Packs oder Kartentyp-Upgrades investieren. Gefundene Zugangskarten über die Schlüsselablage benutzen und danach die betreffende Tür anklicken.

Sonderkarten werden nicht als zusätzliche Kämpfer aufs Feld gelegt. Ihre Wirkung entsteht durch gültigen Besitz beziehungsweise durch die ausdrücklich erforderliche Benutzung eines Schlüssels.

## 2 Bedienung und Kameraführung

| Eingabe oder Element | Funktion |
| --- | --- |
| A und D | Blickrichtung schrittweise um 90 Grad wechseln, sofern keine Interaktion die Kamera festhält. |
| Drehpfeile | Dieselbe Navigation mit der Maus; in den Einstellungen abschaltbar. |
| Linksklick | Schaltflächen, Figuren, Türen und Karten bedienen; im Kampf eigene Karte und danach ein Ziel wählen. |
| Rechte Maustaste | Kontextabhängig Auswahl abbrechen, eine Startkartenbelegung lösen oder aus einer Nahansicht zurückkehren. |
| J | Das physische Journal öffnen oder schließen, wenn die aktuelle Spielsituation dies erlaubt. |
| Escape | Zuerst aktive Auswahl, Dialog oder Journal schließen; sonst das Pausemenü öffnen. Einzelne Schließanimationen laufen noch kurz zu Ende. |
| Mausrad | Listen, Buchseiten, Schmiedeauswahl oder andere gerade fokussierte Ansichten blättern. |
| Oberer Bildschirmrand | Fortschrittsanzeige mit Guthaben, Level und gegebenenfalls Clicker aufklappen. |
| Unterer Bildschirmrand im freien Hub | Schlüsselablage für eigene, noch unbenutzte Zugangskarten öffnen. |
| Ziehen mit der Maus | Packfolie abziehen, Startkarten platzieren, Kesselventil drehen oder Karten in dafür vorgesehenen Ansichten bewegen. |

Im Hauptspiel teilen sich Hub und Nebenräume dieselbe Kamera. Türen lösen eine geführte Fahrt durch den Verbindungsgang aus; beim Zurückkehren werden vorherige Position und Blickrichtung wiederhergestellt. Der Spieler muss keine unsichtbaren Laufwege mit W und S zurücklegen. Hover kann vor Automaten und Werkbänken automatisch eine nähere Kameraansicht aktivieren. [Q01, Q04]

Dialoge, Kamerafahrten, Kartenenthüllungen und andere modale Ansichten sperren jeweils konkurrierende Eingaben. Ein Klick zum Schließen eines Dialogs soll nicht zugleich das Objekt dahinter auslösen. Offline pausiert das Pausemenü den SceneTree. Während einer Online-Sitzung ist das gewöhnliche Pausemenü ein Overlay; die gemeinsame Partie läuft weiter. Die besondere Katzenentscheidung behandelt auch dieses Overlay als Unterbrechung. [Q04, Q05]

## 3 Hauptmenü und Speicherplätze

Das Hauptmenü zeigt drei getrennte Spielplätze mit Fortschrittsvorschau. Das Markieren eines Platzes ist zunächst eine Auswahl; Spielen übernimmt den Platz und führt über einen eigenen Ladebildschirm in den Hub. Einstellungen und Beenden sind direkt erreichbar. Das Zurücksetzen verlangt eine Bestätigung für den ausgewählten Platz. [Q06]

Jeder Platz speichert seine Sammlung, das Kampfdeck und dessen Startauswahl, Kartentyp-Upgrades, Guthaben, Level, Storyfortschritt, Raumfreischaltungen, Geheimfunde, Opfergaben und Katzenentscheidung getrennt. Der Reset eines Platzes ist kein Reset aller drei Plätze. Globale Einstellungen bleiben getrennt vom Profil gespeichert.

Technisch liegen die Profildateien unter `user://saves/slot_1` bis `slot_3`. Die vier Profildateien heißen `collection.json`, `battle_deck.cfg`, `card_upgrades.cfg` und `currency.cfg`. `save_slots.cfg` verwaltet die Auswahl; `settings.cfg` enthält globale Einstellungen. Alte Einzelspielstände werden in Platz 1 übernommen, ohne vorhandene Zielstände zu ersetzen. Das Speichern verwendet an vielen Stellen temporäre Dateien mit anschließendem Umbenennen. Für aufwendigere Käufe und Belohnungen existieren zusätzliche Transaktionsbelege. [Q06, Q07]

Eine laufende Partie ist kein gespeicherter Fortsetzungskampf. Die Profilfortschritte bleiben erhalten; Kartenhand, Kampfschaden, Eventhand und Zugzustand gehören zur aktuellen Sitzung und werden für eine neue Partie neu aufgebaut.

## 4 Welt und Räume

| Bereich | Zugang | Enthaltene Mechaniken |
| --- | --- | --- |
| Hauptraum | Nach Spielen im Hauptmenü | Spieltisch mit Satan, Packshop, Sammlung mit Engel, Upgradeautomat, Journal, Fortschrittsanzeige und Schlüsselablage. |
| Automatenraum | Schlüsselkarte finden und benutzen | Soul Slots, Kartenschmiede, Wand der Sonderkarten und Texteingabe für ein Geheimnis. |
| Keller | Basement Key aus gültiger Kartenbelohnung erhalten und benutzen | Bewegliche Kisten, Friedhofsschlüssel, Katzenentscheidung, Kesselventil und Pumpenschalter. |
| Friedhof | Graveyard Key im Keller finden und benutzen | Jester, zwei Opfergräber, Kryptagitter, Nahansicht, Gefangener und Rückkehrmarkierung. |
| Black Market | Black Market Access erhalten und benutzen | Vier tägliche Kaufangebote und ein Händler mit Dialogen. |

Die Tür zum Automatenraum liegt im Hub; weitere Türen führen neben den jeweiligen Stationen zu Keller, Friedhof und Black Market. Das genaue Anklicken erfolgt an den sichtbaren Türen. Nach einem freigeschalteten Zugang bleibt die Rückkehrtür auch dann nutzbar, wenn Kartenbestand oder Freischaltungsanzeige während des Besuchs neu geladen werden. Ein neuer Eintritt prüft den gültigen Zugang erneut. [Q01, Q04, Q08]

## 5 Kartentypen und Kartenexemplare

### 5.1 Drei unterschiedliche Kategorien

**Kampfkarten** bilden die beiden Decks und kämpfen auf dem Tisch. Mehrere Exemplare desselben Typs sind zulässig, sofern sie tatsächlich besessen werden. Einige Kampfkarten haben angeborene Effekte oder besondere Regeln wie das Ei.

**Sonderkarten** wirken dauerhaft auf das Profil. Sie haben im Katalog 0 Angriff und 0 Lebenspunkte und dürfen nicht ins Kampfdeck, nicht in die gewöhnlichen Kampfwert-Upgrades und nicht in die Schmiede. Zu ihnen gehören Clicker, Fortschrittsboni, Starthandkarten und Zugänge.

**Eventkarten** werden zu Beginn und während eines Matches aus einem eigenen logischen Stapel gezogen. Sie sind von Anfang an freigeschaltet, werden weder gesammelt noch aus Packs gezogen und zählen nicht zu den 118 Sammelkartentypen. [Q02, Q09]

### 5.2 Identität und gemeinsame Upgrades

Ein Kartentyp hat eine feste ID, Grundwerte, Seltenheit und Grundeffekte. Eine erhaltene Kopie hat zusätzlich eine eigene Instanz-ID und zum Beispiel einen Holo-Zustand. Im gespeicherten Deck werden konkrete Kopien gebunden. Später erhaltene Holo-Karten dürfen eine bereits gewählte Kopie nicht heimlich ersetzen.

Angriff, Lebenspunkte und gekaufte Effekte werden dagegen **pro Kartentyp** verbessert. Ein Upgrade von Harald betrifft die eigenen Harald-Kopien, nicht nur eine gerade ausgewählte Kopie. Das sichtbare Feld `level` einer Instanz ist kein ausgebautes allgemeines Evolutionssystem. Die besondere Entwicklung von Chick zu Chicken wird im Kampf gesondert behandelt. [Q02, Q10]

### 5.3 Seltenheiten und Holo

Die Reihenfolge lautet Gewöhnlich, Ungewöhnlich, Selten, Episch, Legendär, Mythisch, Exotisch und Secret. Holo ist eine unabhängige Eigenschaft einer Kopie und keine neunte Seltenheit. Der reguläre Instanz-Erzeugungspfad würfelt mit einer Chance von **1 Prozent** einen Holo-Zustand. Bereits gespeicherte Kopien ohne Holo-Merkmal bleiben normal.

Secret-Karten haben einen eigenen, etwa zehn Sekunden langen Farbwechsel am vorderen Rand. Holo, Seltenheitsdarstellung und Sonderkarteneffekt können nebeneinander bestehen. Die Grundwerte im Kartenkatalog am Ende dieses Dokuments enthalten weder Upgrades noch vorübergehende Kampfeffekte. [Q02, Q11]

## 6 Sammlung und Deckbau

Die physische Sammlung fasst gleiche Kartentypen zusammen und zeigt deren Anzahl. Die Detailansicht erlaubt das Lesen von Werten und Effekten sowie die Zuordnung zum Kampfdeck. Holo-Kopien werden bei einer zunächst noch nicht fest gebundenen Zuordnung bevorzugt; anschließend bleibt die konkrete Deckidentität gespeichert. Der Deckfächer stellt die eigene Auswahl dar. Deck leeren und zufälliges Deck sind eigenständige Bedienaktionen. [Q10, Q12]

Das Kampfdeck darf höchstens 20 Karten enthalten. Eine Kopie kann darin nur einmal verwendet werden; mehrere echte Kopien desselben Typs sind möglich. Sonder- und Eventkarten sind ausgeschlossen. Der verfügbare Kartenbesitz ist die Obergrenze. Ein leeres Deck verhindert den normalen lokalen Kampfstart.

Neu entdeckte Kartentypen bekommen einen NEW-Hinweis. Der erste gültige Hover bestätigt die Kenntnis und entfernt den Hinweis auch in der jeweils anderen Sammlungsansicht. Entdeckungshistorie und bestätigte Ansicht sind Profilzustände. Eine einmal entdeckte Karte bleibt im Journal bekannt, auch wenn die letzte Kopie durch Fusion oder Opfergabe verloren geht. Zugangsschlüssel werden nicht wie normale Kampfkarten in der Hauptsammlung bedient; ihre Benutzung erfolgt über die Schlüsselablage. [Q12]

### 6.1 Fünf gezielt belegbare Startplätze

Starthand I bis V schalten nacheinander einen bis fünf gezielt belegbare Tischplätze frei. Ohne diese Karten wird die Anfangsaufstellung zufällig aus dem Deck befüllt. Freie Startplätze bedeuten also keine generell leere Anfangshand.

Eine Deckkarte wird auf einen freigeschalteten Startplatz gezogen. Sie bleibt Teil der maximal 20 Deckkarten. Wird eine neue Karte auf einen belegten Platz gezogen, kehrt die bisherige Auswahl in den Fächer zurück. Zwei belegte Startplätze tauschen ihre Karten. Rechtsklick oder Zurückziehen löst nur die Startbelegung. Freie Zwischenräume und konkrete Platznummern bleiben erhalten.

Beim Matchstart werden festgelegte Kopien auf ihre Tischplätze gelegt; übrige Plätze werden zufällig aus dem verbleibenden Deck aufgefüllt. Fehlen insgesamt Karten, bleiben nicht auffüllbare Plätze leer. Eine bewusst auf Platz 5 gesetzte Karte wird deshalb nicht auf Platz 1 verschoben. Voraussetzungen der Starthandstufen gelten als zusammenhängende Reihe. [Q10, Q13]

## 7 Kampfregeln und Zugablauf

### 7.1 Aufbau und Siegbedingung

Beide Seiten erhalten bis zu fünf Kampfkarten auf dem Tisch und drei Eventkarten. Verbleibende Kampfkarten bilden ihre getrennten Nachziehstapel. Es gibt keine zusätzliche Spieler-Lebensleiste und keinen Manaaufwand. Lokal beginnt der Spieler; im Onlineaufbau ist zunächst die Host-Seite am Zug.

Eine Seite verliert, wenn sie weder eine Tischkarte noch eine Karte im Nachziehstapel besitzt. Sind beide Seiten gleichzeitig vollständig leer, entsteht ein Unentschieden. Der bloße Verbrauch des Nachziehstapels ist noch keine Niederlage, solange Tischkarten übrig sind. Kampftode entfernen keine Kopien aus der dauerhaften Sammlung. [Q03]

Die aktuelle KI versucht vor dem Angriff ein zulässiges Event zu spielen und wählt dann zufällig eine eigene angreifende Karte sowie ein zufälliges lebendes Gegenziel. Storylevel und ältere Schwierigkeitseinstellungen verändern Kartendaten beziehungsweise Auswahlgewichte; die grundsätzlichen Zug- und Gegenangriffsregeln gelten für beide Seiten gleich.

### 7.2 Ein eigener Zug

1. Zu Beginn des Besitzerzuges werden Regeneration, Nachbarheilung und vorhandenes Gift für die Tischkarten verarbeitet. Dabei können Karten sterben und ersetzt werden.
2. Der aktive Spieler darf optional eine Eventkarte ausspielen. Das ist nur vor dem Angriff und höchstens einmal pro Zug erlaubt.
3. Der Spieler wählt eine eigene angreifende Karte und eine gegnerische Tischkarte als Ziel.
4. Beim tatsächlichen Animationskontakt werden Treffer, Abwehr, Gegenangriff und zugehörige Effekte aufgelöst. Mehrfachtreffer gehören zu derselben Angriffsaktion.
5. Tote Tischkarten geben ihre Plätze frei. Falls eine Reservekarte verfügbar ist, wird früh Ersatz gezogen; die wegfliegende Todeskarte kann noch sichtbar sein.
6. Weitere durch Kills ausgelöste Aktionen werden abgeschlossen. Danach wechselt der Zug zur anderen Seite.

Sind alle eigenen Tischkarten durch Event-Block handlungsunfähig, kann nach einem optionalen Event mit Zug beenden gepasst werden. Das ist keine zusätzliche freie Runde für einen beliebigen bereits handelnden Spieler. [Q03, Q09]

### 7.3 Schaden und Gegenangriff

Der normale Treffer zieht Angriff vom aktuellen Leben des Ziels ab. Rüstung reduziert gewöhnlichen Schaden mit Rundung auf eine ganze Zahl. Ein Ersttrefferschild kann einen positiven gewöhnlichen Treffer vollständig abfangen. Bodyguard verteilt dafür geeigneten Schaden auf ein benachbartes Schutzexemplar; Details stehen im Effektkatalog.

Der gewählte Verteidiger gibt bei einem normalen ersten Treffer einen Gegenschlag mit seinem einfachen Angriffswert ab, sofern der Angreifer noch lebt und der Verteidiger nicht durch Event-Block gesperrt ist. **Auch ein durch diesen Treffer tödlich getroffenes Ziel kann noch kontern**; der Gegenangriff wird vor dem endgültigen Entfernen abgewickelt. Double Strike und Triple Strike erlauben deshalb nicht mehrere Gegenschläge innerhalb derselben Aktion. Betäubung betrifft den nächsten eigenen Angriffsversuch, Event-Block verhindert dagegen zusätzlich das Kontern.

Die Schadensanzeige stellt den tatsächlich verlorenen Lebenswert dar. Overkill wird nicht als zusätzlicher realer HP-Verlust behandelt. Heilung ist auf das aktuelle Lebensmaximum begrenzt. Zeitweilige Verstärkungen, Gift, Schaden, verbrauchte Schutzladungen und Fluch gehören zur Karteninstanz dieser Partie und verändern die gespeicherten Grundwerte nicht. [Q03, Q14]

### 7.4 Wichtige Wechselwirkungen

Mehrfachtreffer treffen keine frisch nachgezogenen Ersatzkarten derselben Aktion. Lava hält die Identitäten der ursprünglich angegriffenen Gegner fest. Dornen können nach jedem verbundenen Treffer wirken; nur das gewählte Hauptziel kontert. Cleave wird als gesonderter Nachbarsplash behandelt und löst keine weiteren gewöhnlichen On-Hit-Effekte aus. Lava und Cleave addieren keinen zweiten identischen Flächenangriff.

Draw On Kill kann durch direkte Kills, Gegenschläge, Dornen und geeignete Flächentreffer eine Eventkarte liefern. Ein erst später eintretender Gifttod liefert keine solche Karte. Einmalige Todesrettungen können den Kill und damit dessen Belohnung verhindern. Chain Attack sucht nach einem bestätigten Kill ein weiteres lebendes Ziel; dafür muss der Angreifer selbst noch leben. [Q03, Q14]

## 8 Vollständiger Kampfeffektkatalog

Es gibt 22 unterschiedliche Effekttypen. Armor ist im Zufallskatalog in drei Stärkevarianten vertreten, weshalb die Effektdatei 24 Einträge enthält. Einzelne angeborene Karteneffekte haben abweichende Werte; diese stehen zusätzlich beim jeweiligen Kartentyp im Anhang. Maximal zwei aktive Effekte werden pro Karte berücksichtigt. [Q02, Q14, Q15]

{{EFFECT_CATALOG}}

Die genannten Prozentsätze sind die regulären Katalogvarianten. Beispiele für angeborene Abweichungen sind Armor 10 oder 35 Prozent und schwächere Gift- oder Heilwerte. Parameter werden von der Kampfauflösung gelesen; eine Beschreibung ist kein Ersatz für die tatsächlichen Kartendaten. Der alte Effekt Deck Burn ist nicht mehr eigenständig aktiv. Ältere gespeicherte Vergaben werden zu Draw On Kill migriert.

## 9 Ei und Kükenentwicklung

Wird **Egg** wirklich zerstört, besteht eine Chance von 25 Prozent, dass an seinem bisherigen Platz ein **Chick** mit frischen Grundwerten und Grundeffekten entsteht. Bei erfolgreichem Schlüpfen wird keine Reservekarte verbraucht und keine Sammlungskarte vergeben. Bei erfolglosem Wurf wird gewöhnlich Ersatz gezogen. Last Stand oder Grave Return können den tatsächlichen Tod und damit das Schlüpfen verhindern. Ein mit Steel gestohlenes lebendes Ei schlüpft nicht allein durch den Besitzerwechsel. [Q16]

Jedes Chick kann zu **Chicken** wachsen, auch ein regulär aus dem Deck gezogenes Küken. Erforderlich sind fünf vollständig auf dem Tisch überlebte Runden, also zehn gewertete Züge beider Seiten. Ein bereits laufender Zug bei seiner Ankunft zählt nicht. Im Nachziehstapel pausiert das Wachstum; Steel erhält den bisherigen Fortschritt.

Bei der Verwandlung ersetzt Chicken das Küken am selben Platz mit frischen Grundwerten und Grundeffekten. Holo, Upgrades und vorherige Kampfstati werden dafür nicht übernommen. Das ist weder ein Kill noch ein neuer Sammlungsfund; es löst keinen Ersatzdraw und keinen Killbonus aus. Es existiert kein entsprechendes allgemeines Evolutionssystem für alle anderen Karten. [Q03, Q16]

## 10 Eventkarten

Der gemeinsame Eventstapel enthält 24 gemischte Karten. Zu Beginn erhalten beide Spieler jeweils drei; damit bleiben 18 im Ziehstapel. Event-Hände gehören nur zum laufenden Match. Auf dem Tisch ist kein zusätzlicher sichtbarer Eventstapel nötig. [Q09]

| Event | Kopien | Auswahl und Wirkung |
| --- | --- | --- |
| Switch | 6 | Direkt anklicken. Tauscht je eine zufällige Karte aus beiden Kampf-Nachziehstapeln. Beide Stapel müssen noch eine Karte besitzen. |
| Block | 5 | Gegnerische Tischkarte wählen. Sie kann bis zum Ende ihrer nächsten zwei Besitzerzüge weder angreifen noch kontern; passive Effekte bleiben aktiv. |
| Steel | 1 | Gegnerische Tischkarte wählen. Die Karte wird in den eigenen Nachziehstapel gemischt. Der bisherige Besitzer zieht nach Möglichkeit sofort Ersatz. |
| Stärke mal 1,2 | 7 | Eigene Tischkarte wählen. Angriff, maximales und aktuelles Leben werden mit 1,2 multipliziert und aufgerundet. |
| Stärke mal 1,5 | 3 | Dieselben Werte einer eigenen Tischkarte mit 1,5 multiplizieren und aufrunden. |
| Stärke mal 2 | 2 | Dieselben Werte einer eigenen Tischkarte verdoppeln. |

Ein nicht ausführbares Event bleibt auf der Hand. Rechtsklick oder Escape beendet die Zielauswahl. Steel behält Schaden, Gift, Event-Block, Verstärkungen und bereits verbrauchte einmalige Effekte bei. Es ändert nicht die dauerhafte Sammlung oder den gespeicherten Besitzer der Karte.

Gespielte Events gehen in die Ablage. Ist der Ziehstapel bei einem erlaubten Nachziehen leer, wird ausschließlich die Ablage neu gemischt. Handkarten werden nicht dafür eingezogen. Ist auch die Ablage leer, kommt keine Karte hinzu. Draw On Kill zieht Events; das gewöhnliche Ersetzen einer toten Kampfkarte zieht keine Events. Große Eventhände lassen sich blättern. Auch die KI bekommt Startkarten und spielt höchstens ein zulässiges Event vor ihrem Angriff.

## 11 Story und Trainingsmodus

### 11.1 Story mit 100 Leveln

Die physische Auswahltafel zeigt einen Pfad aus 100 Leveln. Anfangs ist nur Level 1 freigeschaltet. Ein Sieg in Level N schaltet N plus 1 frei. Bereits abgeschlossene Level können erneut gespielt werden und zahlen dieselben Grundbelohnungen. Niederlagen und Unentschieden geben im Storymodus weder XP noch Coins. Fortschritt und Belohnung werden gemeinsam gespeichert; ein fehlgeschlagenes Speichern soll keinen nur halb abgeschlossenen Sieg hinterlassen. [Q17]

Gegnerkarten haben auf Level N **N Angriff** und **2 mal N plus 1 Lebenspunkte**. Damit liegt die Gesamtstärke pro Karte bei 3 mal N plus 1. Beispiele: Level 1 ergibt 1 Angriff und 3 Leben, Level 50 ergibt 50 und 101, Level 100 ergibt 100 und 201. Spieler-Upgrades werden auf diese Gegnervorlagen nicht angewendet; ihre echten angeborenen Effekte bleiben vorhanden. Der Common-Ausgangspool lässt für den sanften Einstieg nur Karten mit einer ursprünglichen Gesamtstärke bis 10 zu.

Die Seltenheitsmischung entwickelt sich zwischen festen Meilensteinen. Gleichmäßig verteilte Auswahlpunkte ergeben für eine gegebene Deckgröße eine wiederholbare Mischung; vor dem Austeilen wird der Stapel trotzdem gemischt. Secrets, Events und Sonderkarten gehören nicht zum Story-Gegnerpool.

| Level | Common | Uncommon | Rare | Epic | Legendary | Mythic | Exotic |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 100 % | 0 % | 0 % | 0 % | 0 % | 0 % | 0 % |
| 20 | 55 % | 35 % | 10 % | 0 % | 0 % | 0 % | 0 % |
| 40 | 20 % | 35 % | 30 % | 15 % | 0 % | 0 % | 0 % |
| 60 | 5 % | 15 % | 30 % | 30 % | 20 % | 0 % | 0 % |
| 80 | 0 % | 5 % | 15 % | 30 % | 30 % | 15 % | 5 % |
| 100 | 0 % | 0 % | 5 % | 15 % | 30 % | 30 % | 20 % |

Ein Storysieg in Level N zahlt vor permanenten Boni **10 mal N plus 40 XP** und **N plus 4 Soul Coins**. Level 1 zahlt 50 XP und 5 Coins, Level 100 zahlt 1040 XP und 104 Coins. Ein dabei ausgelöstes Level-up liefert seinen eigenen zusätzlichen Coinbonus.

### 11.2 Training

Für die eigene Seite werden fünf unterschiedliche Exemplare aus dem gespeicherten Kampfdeck gewählt. Die Identitäten, Holo-Zustände und im Deck wirksamen Upgrades bleiben erhalten. Für die andere Seite lassen sich fünf echte Kampfkarten oder frei konfigurierte Trainingskarten festlegen. Trainingswerte sind ganzzahlig: Angriff 0 bis 1000000, Leben 1 bis 1000000. Echte Gegnerkarten verwenden ihre nativen Katalogwerte und Effekte.

Beide Seiten starten genau mit diesen fünf Kampfkarten und ohne weitere reguläre Reserve. Effekte und Events funktionieren weiterhin, soweit sie mit diesem Zustand ausführbar sind. Trainingskarten zeigen echte Schadenszahlen auch bei sonst abgeschalteter Anzeige. Ein Protokoll auf dem Tisch hält die letzten fünf Treffer fest, einschließlich Nullschaden und Gift.

Training neu starten stellt die gewählte Konfiguration wieder her. Training verlassen führt direkt zurück zur Auswahl. Training bezahlt keine XP, Coins, Karten oder Storyfortschritte. Auch manuelle und automatische Clickereinnahmen werden während Einrichtung und Kampf unterdrückt; die vergangene Trainingszeit wird später nicht nachvergütet. [Q17]

### 11.3 Weitere Schwierigkeitseinstellungen im Code

Easy, Normal, Hard und Insane samt Gegnergewichtungen und Ergebnisfaktoren sind noch implementiert. Der reguläre lokale Hauptbutton führt im aktuellen Menü jedoch zur Storyauswahl. Die folgende Belohnungslogik ist deshalb eine vorhandene zusätzliche beziehungsweise ältere Spielroute und keine zusätzliche Stufe jedes Storylevels.

| Schwierigkeit | Faktor | Sieg Coins und XP | Remis Coins und XP | Niederlage Coins und XP |
| --- | --- | --- | --- | --- |
| Easy | 0,5 | 5 und 50 | 2,5 und 25 | 1 und 13 |
| Normal | 1 | 10 und 100 | 5 und 50 | 2 und 25 |
| Hard | 1,5 | 15 und 150 | 7,5 und 75 | 3 und 38 |
| Insane | 3 | 30 und 300 | 15 und 150 | 6 und 75 |

XP werden hier vor permanenten Boni auf ganze Punkte gerundet. Onlinepartien verwenden Normal. Zuschauer bekommen keine Matchbelohnung. Einmalige Auszahlungswachen verhindern reguläre Doppelbelohnungen desselben Ergebnisses. [Q03, Q07]

## 12 Soul Coins und Spielerlevel

Soul Coins bezahlen Packs, Kartentyp-Upgrades, den Black Market und Slot-Einsätze. Das Guthaben wird intern in ganzen Hundertstel-Coins geführt. Die Anzeige kann Nachkommastellen darstellen. Kleine Einkommens- und XP-Bonusreste werden aufbewahrt, statt bei jedem Vorgang verlorenzugehen. [Q07]

Auf Spielerlevel L werden **50 mal L plus 50 XP** für den nächsten Aufstieg benötigt. Das bedeutet 100 XP von Level 1 auf 2, 150 von 2 auf 3 und 200 von 3 auf 4. Überschüssige XP bleiben übrig; eine große Belohnung kann mehrere Level gleichzeitig auslösen.

Beim Erreichen von Level Z ab Level 2 gibt es **10 mal Z plus 5 Soul Coins**. Level 2 zahlt 25, Level 3 zahlt 35 und Level 4 zahlt 45. Ein permanenter SoulCoin-Bonus erhöht auch diesen Bonus. Ein Schwierigkeitsfaktor vervielfacht den Levelbonus nicht nochmals.

### 12.1 Aktives und passives Clickereinkommen

Die Sonderkarte Clicker schaltet den manuellen Button der Fortschrittsanzeige frei. Clicker Upgrade allein schaltet ihn nicht frei. Der Grundbetrag pro Klick lautet:

**0,02 SC plus 0,01 SC pro Clicker Upgrade plus 0,05 SC pro Golden Clicker.**

Anschließend wirkt der gültige SoulCoin-Multiplikator einmal. Zwei Clicker Upgrades und ein Golden Clicker ergeben vor dem Multiplikator 0,09 SC je Klick. Die normale Clicker-Freischaltung ist einmalig; Clicker Upgrade und Golden Clicker sind stapelbar.

Auto Clicker ergänzt bei gültiger Freischaltung 0,02 SC pro laufender Spielsekunde vor dem SoulCoin-Bonus. Es wird in Sekundenabschnitten gebündelt abgerechnet. Dafür gibt es keine Offlinezeitstempel und keine Einnahmen für geschlossene Spielzeit. Ein pausierter Offline-SceneTree stoppt die Zeit; ein gewöhnliches Online-Pauseoverlay hält das laufende Spiel nicht an. Die gerettete Katze kann unabhängig davon einen automatischen manuellen Klick pro Animationszyklus beisteuern. [Q07, Q18]

### 12.2 Dauerhafte Bonusreihen

SoulCoin- und XP-Boosts der Stufen I bis IV liefern jeweils 2, 5, 10 und 15 Prozent. Es zählt die höchste gültig freigeschaltete Stufe, nicht die Summe aller Stufen. Höhere Karten ohne ihre Voraussetzungen aktivieren den Bonus nicht.

Dealer License reduziert Preise im normalen Shop-Pool um 10 Prozent. Dieser normale Rabatt gilt auch für die dort angeschlossenen Upgradekäufe und wird einmal auf den Grundpreis angewendet. Er gilt nicht für den Black Market. Fusion Upgrades senken die Eingabezahl von fünf auf vier und danach auf drei Karten. Lucky Coin erhöht die gesamte Rare-und-höher-Wahrscheinlichkeit relativ um 5 Prozent; aus 20 Prozent werden beispielsweise 21 Prozent, nicht 25 Prozent. Innerhalb des Legendary-Pools hat Lucky Coin selbst nur das relative Kartengewicht 0,02 statt des gewöhnlichen Gewichts 1. [Q18]

## 13 Packs und Kartenbelohnungen

### 13.1 Kauf und Öffnung

| Pack | Grundpreis | Karten | Mindestlevel |
| --- | --- | --- | --- |
| Basic | 5 SC | 5 | 1 |
| Ultra | 20 SC | 7 | 1 |
| God | 35 SC | 10 | 10 |

Dealer License verändert den tatsächlichen Kaufpreis über den normalen Shoprabatt. God bleibt im Angebot sichtbar, lässt sich vor Level 10 aber nicht kaufen. Ab Level 2 kann eine Kaufmenge gewählt werden. Das verfügbare Guthaben und der Gesamtpreis begrenzen den Kauf; 41 Coins reichen beispielsweise für acht Basic Packs ohne Rabatt. [Q19]

Ein Kauf reserviert und bezahlt die gewählte Menge einmal. Die Packs werden nacheinander präsentiert. Die obere Folie wird mit der Maus gegriffen und seitlich abgezogen. Loslassen hält den bisherigen Rissfortschritt fest; erneutes Greifen setzt ihn fort. Nach dem Öffnen werden die Karten enthüllt und anschließend eingesammelt. Karten und noch nicht übernommene Uniques werden bereits innerhalb eines Packs berücksichtigt, damit eine einzigartige Freischaltung nicht mehrfach erscheint.

Beim Verlassen oder Wiederherstellen eines unterbrochenen Kaufs werden noch nicht an den Spieler ausgehändigte Warteschlangen-Packs zurückerstattet. Ein bereits ausgegebenes Pack bleibt berechnet. Die eigentliche Kartenübernahme wird in der Sammlung gespeichert. Der Lade- und Wiederherstellungspfad verhindert reguläre doppelte Rückerstattungen. [Q07, Q19]

### 13.2 Aktuelle Seltenheitschancen

Die folgenden effektiven Grundchancen gelten vor Lucky Coin und ohne aktiv eingeschränkten Seltenheitsfilter. Da derzeit keine Secret-Karte für normale Zufallsbelohnungen zugelassen ist, wird deren konfigurierte Masse auf die verfügbaren normalen Seltenheiten normalisiert. Welche Sonderkarten bereits besessen werden oder welche Voraussetzungen gelten, kann den verbleibenden Pool weiter verändern.

{{PACK_ODDS}}

Die kleinen Secret-Gewichte in den Packdefinitionen sind eine Vorbereitung für künftig zufällig zulässige Secrets. Sie machen die aktuellen Entdeckungs- und Codekarten nicht zu Packdrops. Auch ein Secret-only-Cheat schaltet deren `random_reward: false` nicht aus.

### 13.3 Effekte bei neuen Exemplaren

Der zentrale Instanzpfad speichert neben Holo auch einen Zufallswurf für zusätzliche Effekte. Die Effektanzahl wird zunächst aus 0, 1 oder 2 gewählt; doppelte Effekttypen innerhalb dieses Wurfs werden ausgelassen. Gewichte pro Effektkatalogeintrag sind Common 60, Rare 24, Epic 10, Legendary 4 und Exotic 2. Das sind relative Gewichte pro Eintrag, keine direkten Seltenheits-Prozentangaben. Lava ist nur als angeborener Effekt zugelassen und wird aus zusätzlichen Zufallseffekten herausgefiltert.

Für die tatsächlich dargestellten und im gespeicherten Kampfdeck verwendeten Effekte muss der derzeitige Aufbereitungspfad beachtet werden: Dieser setzt Basis- und Kartentyp-Upgrades zusammen. Die separat gespeicherten Instanz-Zufallseffekte werden dort nicht automatisch ergänzt. Diese Implementierungsabweichung ist im Prüfbericht ausdrücklich als Quellcodebefund aufgeführt. [Q02, Q10, Q15]

## 14 Kartentyp-Upgrades

Der Upgradeautomat erlaubt die Auswahl eigener Kampfkartentypen. Ein Deckfilter beschränkt die Liste bei Bedarf auf das gespeicherte Deck. Vorschau und Effektübersicht verwenden die aktuellen Typwerte. Ein Angriffskauf erhöht Angriff um 1, ein Lebenskauf erhöht Leben um 1. Sonderkarten sind ausgeschlossen. [Q20]

Angriffs- und Lebenskäufe teilen sich **einen Zähler je Kartentyp**. Ohne Rabatt kostet der erste Kauf 5 SC, der zweite 10, der dritte 15 und so weiter. Nach einem Angriffskauf kostet deshalb auch der nächste Lebenskauf dieses Typs 10. Ein anderer Kartentyp behält seine eigene Preisstufe.

Effektwürfe haben einen getrennten Zähler. Sie kosten 12, 24, 36 SC und so weiter, solange bezahlte Würfe einen Effekt liefern. Ein bezahlter Wurf ohne Effekt setzt den nächsten Preis auf 12 zurück. Es muss noch ein freier Effektplatz vorhanden sein. Der Automat nimmt den ersten Effekt aus dem gewürfelten Ergebnis; bei einem leeren Ergebnis wird kein Effekt hinzugefügt. Entfernen von Effekten verändert diese Preisfolge nicht.

Es gibt maximal zwei aktive Effekte einschließlich der verbleibenden angeborenen Effekte. Die Oberfläche kann konkrete entfernbare Grund- und Upgradeeffekte auflisten. Entfernen ist ohne gesonderte Coinabbuchung implementiert und wirkt auf den eigenen Kartentyp. Lava bleibt geschützt und wird nicht als zusätzliches Pack- oder Upgradeergebnis vergeben. Der Pisse-Eimer mit der ID `piss` zahlt das Fünffache: Statkäufe 25, 50, 75 und Effektwürfe 60, 120, 180 SC vor Rabatt. [Q02, Q20]

## 15 Kartenschmiede und automatische Fusion

Die Werkbank steht im Automatenraum. Hover zieht die gemeinsame Kamera näher heran. Die Rückwand zeigt konkrete eigene Exemplare, zwölf pro Seite. Pfeile und Mausrad wechseln die Ansicht. Linksklick belegt oder löst einen Eingabeplatz. Eine Fusion benötigt Karten derselben Seltenheit; unterschiedliche Kartennamen sind erlaubt. Sie kostet keine Soul Coins. [Q21]

Standardmäßig werden fünf Eingabekarten verbraucht und eine zufällige Kampfkarte der direkt nächsten Seltenheit erzeugt. Fusion Upgrade I reduziert auf vier, Fusion Upgrade II auf drei. Die Reihe endet bei Exotisch. Sonderkarten, Events, Secrets und im Kampfdeck gebundene Kopien sind geschützt. Freie Holo-Kopien sind nicht allgemein geschützt und können verbraucht werden.

Das Ergebnis ist ein neu erzeugtes Exemplar mit neuer Identität sowie neuen Holo- und Effektwürfen. Bestehende Typ-Upgrades gelten anschließend weiterhin. Verbrauch und Ergebnis werden zusammen gespeichert, bevor die Präsentation startet. Scheitert dieser Speicherabschluss, bleiben die Eingaben erhalten.

Auto Fuse verarbeitet alle zulässigen freien Exemplare, nicht nur die aktuelle Seite oder die manuelle Auswahl. Der Durchlauf beginnt bei Common und kann neue Ergebnisse für die nächste Seltenheit weiterverwenden. Unvollständige Gruppen bleiben übrig. Alle Schritte werden als gemeinsamer Sammlungsabschluss übernommen; Animation und Weiter-Button zeigen anschließend das bereits gespeicherte Ergebnis. [Q21]

## 16 Zugangskarten und Geheimfunde

### 16.1 Vier Zugänge

| Zugangskarte | Fund beziehungsweise Erwerb | Benutzung |
| --- | --- | --- |
| Schlüsselkarte zum Automatenraum | Das Messer vom Spieltisch werfen. Der erste Fund wird direkt gutgeschrieben. | Im Hub über die Schlüsselablage benutzen, danach die offene Tür anklicken. |
| Basement Key | Gültiger normaler Kartenbelohnungspool auf Legendary. | Dieselbe Ablage öffnet den Kellerzugang. |
| Graveyard Key | Die Kisten im Keller wegwerfen und den unter der vorgesehenen Kiste verborgenen Schlüssel aufdecken. | Über die Ablage den Friedhofzugang freischalten. |
| Black Market Access | Gültiger normaler Kartenbelohnungspool auf Legendary. | Über die Ablage den Marktzugang freischalten. |

Besitz allein ist keine Türfreischaltung. Erst erfolgreiches Benutzen speichert den Zugang. Die Karte bleibt als Sonderkarte erhalten und verschwindet aus der Liste unbenutzter Schlüssel. Sind alle Zugänge freigeschaltet, verschwindet die gesamte Ablage. Während Kampf, Dialogen, Pause und Kamerafahrten ist sie gesperrt. [Q08, Q22]

### 16.2 Alle vier Secret-Karten

| Secret | Grundwerte | Direkter Geheimweg |
| --- | --- | --- |
| USB-Stick | 32 Angriff und 32 Leben | Insgesamt 50 gültige Würfe des USB-Objekts. |
| Zigaretten | 32 und 32 | Insgesamt 80 gültige Würfe der Zigaretten. |
| Möwenmilch | 32 und 32 | Insgesamt 150 gültige Würfe der Dose. |
| DMAN | 20 und 20 | Im Automatenraum `dman` am Textpanel eingeben und mit Enter bestätigen. |

Die Wurfzähler werden pro Spielstand gespeichert. Mehrfaches Klicken auf dasselbe bereits geworfene Objekt zählt nicht mehrfach. Ein Raumwechsel oder Neustart setzt den Fortschritt nicht zurück. Die jeweilige Entdeckungsbelohnung ist einmalig, auch wenn eine Karte später verbraucht wurde.

Der Codevergleich für DMAN ignoriert Großschreibung und umgebende Leerzeichen. Escape oder ein Klick neben das Feld löst den Tastaturfokus. Während der Eingabe dürfen A, D und J keine Weltnavigation auslösen. Die Entdeckung wird vor ihrer Kartenanimation gespeichert.

Die ersten drei Secrets zeigen einen echten kleinen 3D-Raum im Bildfeld. DMAN verwendet ein gewöhnliches Bild. Developer und Missing Texture sind aktuell Exotisch und gehören nicht zu dieser Secretgruppe. Packs können keine dieser vier Entdeckungskarten ausgeben. Eine weitere Bezugsquelle für eines der ersten drei Secrets ist die abgeschlossene Jester-Opfergabe. [Q11, Q22]

## 17 Automatenraum und Soul Slots

Die Slotmaschine hat drei unabhängig gewürfelte Rollen mit fünf gleich wahrscheinlichen Symbolen. Einsatzstufen sind 1, 2, 5, 10, 20 und 50 SC. Plus und Minus ändern die Auswahl. BET bestätigt den Einsatz ohne Abbuchung. SPIN bucht einmal ab und startet die Rollen. Nach einer Einsatzänderung ist eine neue Bestätigung erforderlich. Drei gleiche Symbole gewinnen; gemischte Ergebnisse zahlen nichts. [Q23]

| Drei gleiche Symbole | Aktueller Auszahlungsfaktor |
| --- | --- |
| Heilung in Grün | 5 mal Einsatz |
| Lebensraub in Rot | 10 mal Einsatz |
| Schild in Blau | 15 mal Einsatz |
| Dreifachschlag in Gold | 35 mal Einsatz |
| Fluch in Violett | 55 mal Einsatz |

**Diese Tabelle folgt dem aktuellen Skript.** Die ältere Einzelbeschreibung nennt für die letzten beiden Symbole noch 30 und 50. Der aktuelle Gesamtwert ergibt bei unabhängigen, gleichverteilten Rollen eine Dreierchance von 5 durch 125, also **4 Prozent**, und eine mittlere Bruttoauszahlung von 120 durch 125, also **96 Prozent des Einsatzes**. Die erwartete Nettodifferenz ist damit minus 4 Prozent des Einsatzes. Das sind aus den implementierten Regeln berechnete Langzeitwerte, keine Gewinnzusage für einzelne Spins.

Die Auszahlung enthält den Einsatz. Bei 2 SC und drei roten Symbolen werden erst 2 SC abgezogen und danach 20 SC gutgeschrieben; der Nettogewinn ist 18 SC. Gewöhnliche Einkommensboosts verändern bereits festgelegte Slot-Auszahlungen nicht.

Während eines Spins sind neue Maschineneingaben gesperrt. Blickwechsel und Rückreise dürfen den laufenden Spin bestehen lassen. Offline-Pause hält auch die Animation an. Einsatz und Ergebnis werden vor der Präsentation als ausstehender Spin gespeichert; Laden schließt ihn genau einmal ab. Ein Auszahlungsfehler ermöglicht einen Wiederholungsversuch ohne einen zweiten Einsatz. Rollenklackern, Rolling-Sound und Gewinnpräsentation begleiten die physische Maschine. [Q07, Q23]

## 18 Black Market

Die Angebotstafel zeigt vier Kampfangebote, Guthaben, Preise und die Zeit bis zum Tageswechsel. Der lokale Kalendertag bestimmt die Auswahl. Ein Angebot kann pro Spielstand und Tag einmal gekauft werden. Ein Neustart innerhalb desselben Tages erzeugt keine neue kostenlose Auswahl. Der normale Dealer-Rabatt gilt hier nicht. [Q24]

| Seltenheit | Preis je angebotener Karte |
| --- | --- |
| Common | 12 SC |
| Uncommon | 22 SC |
| Rare | 40 SC |
| Epic | 75 SC |
| Legendary | 140 SC |
| Mythic | 260 SC |
| Exotic | 500 SC |

Zulässig sind zufällig erhältliche Kampfkarten von Common bis Exotic. Secrets, Events, Schlüssel und permanente Fortschrittsfreischaltungen sind nicht im Marktpool. Ein Kauf fügt die konkrete Belohnung direkt der Sammlung hinzu. Tagesbezug, Zugang, Kaufbeleg und Guthaben werden am Abschluss erneut geprüft. Ein unterbrochener Kauf wird über Zahlungs- und Sammlungsbelege abgeglichen; dadurch sollen Doppelklicks oder alte Tagesangebote keine zweite Abbuchung verursachen.

Der Händler hat zwölf kurze, zufällig ausgewählte Dialoge ohne unmittelbare Wiederholung. Während eines Gesprächs sind Einkaufen, Journal, Drehen und Türfahrt gesperrt. Text wird schrittweise angezeigt. Klick vervollständigt den laufenden Satz; ein weiterer Klick schließt ihn mit der aktuellen Panelanimation. Der Dialog zahlt keine Belohnung aus. [Q24, Q25]

## 19 Keller

### 19.1 Kisten und Friedhofsschlüssel

Die Kisten lassen sich anklicken und wegwerfen. Sie haben eigene physische Bewegungen und reagieren auf die tatsächliche Raumhülle, den Boden und die Regale. Unter der vorgesehenen Bodenkiste liegt der Graveyard Key. Sobald der Fund ausgelöst wird, wird die Sonderkarte automatisch gespeichert. Der Geheimfund darf weder durch erneutes Betreten noch durch weitere Würfe doppelt vergeben werden. [Q22]

### 19.2 Katze und dauerhafte Entscheidung

Beim ersten passenden Kellerbesuch und Blick nach rechts läuft die Katze vor den Spieler. Engel, Satan und die Pistole stellen zwei Möglichkeiten dar. Die Entscheidung gilt einmalig pro Spielstand.

**Satan wählen:** Die Katze wird erschossen und dauerhaft entfernt. Es gibt einmalig exakt **1000 SC**, unabhängig von Einkommensboosts. Entscheidung und Auszahlung werden gemeinsam gespeichert. Ein Speicherfehler soll die Wahl offen lassen und keinen Schuss auslösen.

**Engel wählen:** Es gibt keine sofortige Auszahlung. Die Katze bleibt zunächst mit ihrer Schonungsanimation. Nach dem Verlassen des Kellers zieht sie zum Clicker, sobald die Clicker-Freischaltung vorhanden ist. Ein später gefundener Clicker genügt ebenfalls. Eine erschossene Katze hilft nie am Clicker. [Q26]

Die Clickerkatze spielt drei Bilder mit drei Bildern pro Sekunde. Beim Erreichen des dritten Bildes wird einmal der aktuelle manuelle Klickwert gutgeschrieben, einschließlich Clicker-Upgrades, Golden Clicker und SoulCoin-Bonus. Sie braucht keine Auto-Clicker-Karte. Der zentrale Wallet-Timer verhindert doppeltes Einkommen durch mehrere Anzeigen. Eine eingeklappte Fortschrittsanzeige stoppt die Hilfe nicht. Es gibt keine Offlineauszahlung und keinen gespeicherten halben Animationszyklus.

### 19.3 Kessel und Pumpenschrank

Das rote Kesselventil wird mit gedrückter Maus gedreht. Zeiger und Ziffernanzeige folgen dem Druckwert im Bereich 0 bis 6. Der Ausgangswert ist 2,8. Diese Interaktion ist ein lokales Spielobjekt; sie bezahlt nichts, öffnet keine weitere Tür und ist kein verknüpftes Rätsel.

Der Pumpenschrank hat drei unabhängige Kippschalter. Oben zeigt die zugehörige Lampe Gelb, unten Grün. Jeder Schalter steuert nur seine eigene Stellung und Lampe. Der Zustand bleibt während der geladenen Szene erhalten, wird aber nicht als dauerhafter Profilfortschritt gespeichert. Es gibt aktuell keine Kombination, die aus diesen drei Schaltern eine geheime Belohnung macht. [Q27]

## 20 Friedhof und Figuren

### 20.1 Jester und Opfergräber

Der Jester steht an einer gemeinsam fokussierten Station mit den benannten Gräbern für **Chick** und **Harald**. Sein Gespräch besteht aus vier nacheinander dargestellten Sätzen. Ein Klick vervollständigt nur den aktuellen Satz; der nächste zeigt den folgenden. Erst nach dem vierten fertigen Satz schließt ein weiterer Klick. Die Stimme begleitet das Schreiben, einzelne Satzenden besitzen ihren eigenen Ton. [Q28]

Ein Klick auf eines der beiden Opfergräber zeigt eine passende eigene Kartenkopie. Ein Klick in das Textpanel bestätigt die Opfergabe; ein Klick außerhalb bricht ab. Ein normales freies Exemplar wird vor Holo bevorzugt. Im Deck gebundene und damit auch als Startkarte verwendete Exemplare sind geschützt und müssen vorher aus dem Deck genommen werden.

Die erste Opfergabe bleibt gespeichert. Nach beiden unterschiedlichen Opfergaben gibt es einmal pro Spielstand eine zufällige Secret-Kampfkarte aus USB-Stick, Zigaretten und Möwenmilch. DMAN gehört nicht dazu. Verbrauch, Fortschritt und konkret erzeugte Belohnung werden zusammen übernommen. Die Entdeckungshistorie des gewonnenen Secrets wird ebenfalls gesetzt; dessen späterer direkter Objektfund kann deshalb nicht noch einmal dieselbe Erstentdeckungsbelohnung geben. [Q28]

### 20.2 Kryptagitter und Nahansicht

Hover lässt das Gitter leicht schwingen. Ein Linksklick fährt die bestehende Kamera direkt vor die Krypta. Dieser nahe Standpunkt bleibt auch nach Wegbewegen des Mauszeigers bestehen. A und D drehen dort den Blick, ohne zurück zum alten Mittelpunkt zu springen.

Beim Blick zurück auf die Kreuzung kann am Mauszeiger eine türkisfarbene Beacon-Markierung erscheinen. Ein Klick darauf fährt zur Kreuzung zurück und bewahrt die aktuelle Blickrichtung. Rechtsklick oder Escape dienen als weitere Rückwege, soweit kein vorrangiger Dialog aktiv ist. Das Herangehen an das Gitter ist keine dauerhafte Raum- oder Kartenfreischaltung. [Q29]

### 20.3 Gefangener

Vor dem Gitter ist der platzierte Gefangene interaktiv. Seine zwölf Animationsframes laufen in einer festen Ausrichtung; er dreht sich nicht als Billboard mit der Kamera. Hover schaltet phasentreu auf das helle Hoverbild um.

Das Gespräch zeigt nacheinander die beiden wörtlichen Zeilen `*Lacht*` und `*Scheisst sich ein*`. Klicks decken zunächst die aktuelle Zeile auf und wechseln danach zur nächsten. Beim Eintritt in die zweite Zeile wird einmal ein Furzgeräusch abgespielt. Es gibt keinen zusätzlichen Satzabschlusston. Escape schließt zuerst das Gespräch. Währenddessen sind Rückkehr, Journal und Drehen gesperrt. Die Begegnung vergibt keine Coins oder Karten. [Q25, Q29]

### 20.4 Engel in der Sammlung

Der Engel bietet 20 hoffnungsvolle Einzelsätze. Eine Unterhaltung wählt einen Satz mit eigenem Zufallsgenerator und vermeidet die direkte Wiederholung. Die Stimme spielt während des Schreibens. Klick vervollständigt, ein weiterer Klick schließt. Die Kamera zoomt dafür nicht auf die Figur. Eine Sprachumschaltung erhält die Identität des gewählten Satzes. Das Gespräch verändert weder Zufallsfolgen von Packs und Kampf noch Fortschritt oder Besitz. [Q25]

## 21 Satan und Inszenierung

### 21.1 Einführung und normale Reaktionen

Ein frischer beziehungsweise zurückgesetzter Spielplatz hat eine einmalige Begrüßung. Satan spricht den lokalen Spielernamen an und führt in Packkauf, Sammlung und Deckbau ein. Die Kamera beginnt bei den Augen und fährt ungefähr zwölf Sekunden zur normalen Sicht zurück. Die Einführung wird erst nach ihrem Abschluss als erledigt gespeichert. Andere Kamera- und Spieleingaben sind währenddessen gesperrt. [Q30]

Im freien Hub reagiert Satan auf Hover und auf gewöhnliche Klicks. Ein Klick stößt ihn kurz zurück. Zwei schnelle gültige Klicks innerhalb des gemeinsamen Zeitfensters starten den zusätzlichen Partikelstrahl über den Tisch; dabei lacht Satan schneller. Der Strahl ist ein kosmetischer Effekt ohne Geld-, Karten- oder Kampfwirkung. Er endet nach rund 2,2 Sekunden Emission oder beim Wechsel in einen anderen maßgeblichen Interaktionskontext. [Q31]

### 21.2 Jumpscare und Aufwachen

Vier Linksklicks innerhalb von 1,5 Sekunden im freien Hub lösen den Jumpscare aus. Rechtsklicks und bloßes Loslassen zählen nicht. Satan erscheint etwa 1,05 Sekunden direkt vor der Kamera, begleitet von Schütteln, Ton und Stroboskoplicht. Danach liegt die Sicht nahe dem Boden, hält kurz und richtet sich über etwa 3,2 Sekunden wieder auf. Nach abgeschlossener Erholung gilt eine achtsekündige Abklingzeit.

Während Schreck, Liegen und Aufstehen sind Weltbedienung, Journal, Fortschrittsanzeige, Schlüssel und Pause gesperrt. Die vorhandenen Bildschirmfilter bleiben aktiv. Ein Blutrand beginnt beim Aufwachen und blendet etwa neun Sekunden aus. Der Effekt ist während Einführung, Kampf, anderer Räume, Dialoge und Onlinekontexte nicht frei auslösbar. Eingehende Lobbys können die Präsentation abbrechen und die Kamera wiederherstellen. [Q31]

### 21.3 Ende einer Partie

Ein Sieg oder eine Niederlage kann beim Verlassen eine eigene Waffen- und Satansequenz abspielen. Beim Sieg benutzt der Spieler die Pistole, Satan wird zurückgestoßen und kehrt später wieder. Bei einer Niederlage übernimmt Satan die entsprechende Präsentation. Ein lokaler Exit kann nach dem dafür vorgesehenen Moment übersprungen werden. Online wird das Ende zwischen den Teilnehmern abgestimmt, bevor die Sitzung geschlossen wird. Diese Präsentationen sind von der bereits berechneten Ergebnisbelohnung getrennt. [Q03, Q32]

### 21.4 Leuchtende Charakterbereiche

Satan, Engel, Black-Market-Händler, Jester und Gefangener verwenden farbige Emissionskarten. Alle sichtbaren nicht schwarzen Bildbereiche leuchten in ihrer jeweiligen Farbe; schwarzer Körper und transparenter Hintergrund bekommen keine eigene Emission. Hover-, Lach- und Todesbilder wechseln gemeinsam mit ihrer Emissionskarte. Im Hauptmenü besitzt Satan eine eigene stärkere Einstellung, damit die roten Bereiche durch die dortigen Bildschirmfilter erkennbar bleiben. [Q33]

## 22 Journal und Fortschrittsanzeige

J öffnet ein physisches Buch mit Kapiteln für Kampfkarten, Sonderkarten, Events, Effekte, Mechaniken, Profil und Collection. Reiter, Indexeinträge, Seitenpfeile und Mausrad bedienen das Buch. Die Collection-Seiten haben feste Plätze für den Katalog; unbekannte Karten werden als Platzhalter gezeigt. Hover hebt eine sichtbare Karte zur Lesekamera. Nach Verlust der letzten Kopie kann eine entdeckte Karte weiterhin als bekannt erscheinen. [Q34]

Das Profil fasst unter anderem Level, XP, Coins, Deckgröße, Gesamtangriff, maximales Leben, Gesamtstärke, Effekte, Holo-Kopien und Sammlungsumfang zusammen. **Stärke meint Angriff plus maximale Lebenspunkte** einschließlich der dafür berücksichtigten Upgrades. Effekte werden separat gezählt und sind kein verborgenes zusätzliches Stärkemaß.

Lesen soll weder Karten würfeln noch das Profil verändern. Eine Ausnahme ist die ausdrücklich gewünschte Kenntnisbestätigung beim ersten Hover einer neuen Karte. Das Journal verrät im Spiel nicht sämtliche Raum- und Geheimfundwege, die dieses Entwicklerdokument offen erklärt. Beim Lesen wird die Kamerabeleuchtung für bessere Lesbarkeit angepasst und anschließend zurückgestellt; die Bildschirmfilter bleiben in ihrem vorgesehenen Zustand.

Die Fortschrittsanzeige am oberen Rand zeigt Wallet und Level. Bei gültigem Besitz enthält sie den Clicker und gegebenenfalls die Katze. Sie ist keine zweite Einkommensquelle zusätzlich zum zentralen Timer. Kontext- und Kamerasperren verhindern, dass sie während unpassender Aktionen Weltklicks abfängt. [Q07, Q34]

## 23 Mehrspieler und Zuschauer

Die aktuelle Netzwerkschicht verwendet Steam-Lobbys und GodotSteam. Eine Lobby erlaubt **zwei Kämpfer und bis zu zwei Zuschauer**, also maximal vier Mitglieder. Ein Teilnehmer wählt seine Rolle; der Host startet die vorbereitete Partie. Lobbyliste, Aktualisieren, Beitreten und Einladungen sind über die Mehrspieleroberfläche angebunden. [Q32]

Der Host entscheidet über gültige Angriffe, Events, Zufallsergebnisse und Zustandsschritte. Gäste senden Anfragen statt lokale Treffer endgültig festzulegen. Sequenznummern und Bestätigungen helfen, Animationen, Treffer und Ersatzkarten in der richtigen Reihenfolge abzubilden. Eventhände sind privat: Der Gast bekommt seine eigene Hand, nicht die gegnerische verdeckte Hand oder Ziehreihenfolge. Zuschauer bekommen öffentliche Präsentationen und kein eigenes Deck zum Eingreifen.

Ein online übertragenes Deck darf höchstens 20 gültige Kampfkarten enthalten. Übertragene Werte werden gegen Katalogdaten begrenzt; im aktuellen Sanitizer liegt die zulässige Bonusobergrenze pro Wert bei 100. Ein lokal weit darüber verbessertes Exemplar ist deshalb nicht automatisch in gleicher Stärke im Online-Payload enthalten. Die verwendete Protokollversion ist 6. Ältere inkompatible Lobbys sind keine verlässlich passenden Spielpartner.

Zuschauer erhalten keine Matchbelohnungen und keine aktive Eventhand. Das Online-Pausemenü hält die andere Seite nicht an. Beim Verlassen und bei Matchende gibt es eigene Abschlussschritte, die noch laufende Darstellungen und verspätete Pakete berücksichtigen. Ein externer Steam-Ausfall kann damit nicht durch lokale Tests ausgeschlossen werden.

### 23.1 Satan Voice und Mikrofontest

Optional kann die Sprache des Gegners über die Satan-Voice-Funktion wiedergegeben und visualisiert werden. Die Aufnahme wird nur im passenden aktiven Onlinekampf mit verbundenem Gegner und aktivierter Einstellung angefordert. Zuschauer sind nicht eigene aktive Sprecher dieser Kämpferfunktion. Der Mikrofontest in den Einstellungen kann die lokale Aufnahme übernehmen; der Live-Test zeigt Ruhe, Sprechen und laute Eingabe an und lässt die Satanvorschau darauf reagieren.

Es gibt Einstellungen für Stimmhöhe, Wiedergabelautstärke und Mikrofonverstärkung. Satan Voice ist standardmäßig ausgeschaltet. Der Mikrofontest beginnt nicht ungefragt beim bloßen Öffnen der Einstellungen. Die vollständige Funktion hängt von Steam, dem Aufnahmegerät und dem tatsächlichen Audiopfad ab und benötigt deshalb einen gesonderten realen Mehrspielertest. [Q35]

## 24 Einstellungen und Entwicklungsfunktionen

Die Oberfläche bietet FPS-Limit, Sprache, Vollbild, 3D-Auflösungsskalierung, Schadenszahlen, Drehpfeile und Lautstärken für Master, Musik, SFX und Satan Voice. Die regulären Standardwerte sind Deutsch, Vollbild, 60 FPS, 3D-Skalierung 1,0 und 30 Prozent für die Lautstärken. Bereits gespeicherte globale Einstellungen haben Vorrang vor diesen Vorgaben. Die fünf Sprachfassungen sind Deutsch, Englisch, Spanisch, Französisch und Polnisch. [Q05, Q36]

Der aufklappbare Cheats-Bereich kann ein Spielerlevel inklusive normalem Levelbonus hinzufügen, 50 Basis-Soul-Coins gutschreiben und Starthand I bis V freischalten. Reguläre Einkommensmultiplikatoren können die tatsächlich hinzugefügten Coins beeinflussen. Außerdem lässt sich festlegen, welche Seltenheiten bei zufälligen Kartenbelohnungen zugelassen sind. Mindestens eine muss aktiv bleiben. Voraussetzungen, einzigartige Freischaltungen und explizit nicht zufällig erhältliche Geheimkarten werden dadurch nicht einfach aufgehoben.

Im Projekt existiert auch ein Piskel-Importwerkzeug für Spritebilder. Der entsprechende Hauptmenübutton ist im aktuellen regulären Menü ausgeblendet. Ein eigener ProfileScreen und mehrere ältere Systemklassen enthalten nur Platzhalter. Insbesondere ist aus dem vorhandenen AchievementManager-Platzhalter kein fertiges Erfolgssystem abzuleiten. Das eigentliche Kampfverhalten liegt überwiegend in GameTable und den verwendeten Helfern, nicht in den gleichnamig klingenden leeren MatchState-, TurnManager- oder BotPlayer-Dateien. [Q37]

## 25 Prüfbericht und bekannte Abweichungen

### 25.1 Umfang der aktuellen Prüfung

Für diese Dokumentation wurden die Kartendaten, die eingebundenen Haupt- und Raumszenen, die tatsächlichen Kampf-, Wirtschafts-, Speicher-, UI- und Netzwerkpfade sowie die vorhandenen Featurebeschreibungen gegengeprüft. Die Tests laufen in gesonderten Projektkopien mit umgeleiteten Profil- und Einstellungspfaden und einem Ersatz für den externen Steamtransport. Der Testbericht unterscheidet bestandene Suiten, fehlgeschlagene Suiten, Zeitüberschreitungen und nicht mit diesem Runner ausgeführte Spezialfälle.

{{AUDIT_SUMMARY}}

Das Ergebnis einer Testsuite ist nicht automatisch ein Beweis für die gesamte sichtbare Spielsituation. Ein Headless-Test rendert keine Pixel. Eine lokale ENet-Prüfung ersetzt keine Sitzung mit mehreren realen Steamkonten. Eine fehlgeschlagene Sofortprüfung kann außerdem an einer inzwischen eingeführten Schließanimation liegen. Diese Unterschiede werden im folgenden Befundteil nicht zu einem pauschalen Bestehen oder Durchfallen des gesamten Spiels zusammengefasst.

### 25.2 Konkrete Quellcodebefunde

| Bereich | Aktueller Befund und Bedeutung |
| --- | --- |
| Slot-Auszahlung | SlotMachine nutzt 5, 10, 15, 35 und 55. Die alte Einzelbeschreibung mit 30 und 50 sowie 88 Prozent Bruttoerwartung ist veraltet; dieses Dokument verwendet 96 Prozent. |
| Alte Packdaten | data/packs.json nennt alte Packtypen und Preise. Der aktuelle Shop verwendet PackDefinition mit Basic 5, Ultra 20 und God 35 SC. PackManager und PackRewardGenerator sind Platzhalter. |
| Dialogschließen | AngelDialogue hält den Modalzustand bis zum Ende einer 0,24-Sekunden-Ausblendung. Mehrere ältere Tests prüfen unmittelbar nach Escape oder dem Schließklick bereits einen vollständig geschlossenen Dialog und erzeugen Folgefehler. Ein solcher Fehler wird als Timingabweichung geführt, bis eine Prüfung nach Animationsende erfolgt ist. |
| Zufällige Instanz-Effekte | Roll Card Instance speichert solche Effekte. DeckManager fügt im aktuellen Deckpfad aber Typ-Grundeffekte und gekaufte Typ-Effekte zusammen und übernimmt aus der Kopie nur Metadaten. Die gespeicherten Zufallseffekte der Kopie werden dabei nicht mit übergeben. Das ist eine zu klärende Regelabweichung, keine zugesicherte zusätzliche Kampfverbesserung. |
| Gewöhnliche Upgradekäufe | Coinabbuchung und Kartentyp-Upgrades werden in getrennten Dateischritten gespeichert. Die für Packbatches, Markt und Fusion vorhandene gemeinsame Wiederherstellungslogik ist hier nicht als gleichwertige Kauftransaktion ausgeführt. Verhalten bei gezielt provozierten Schreibfehlern bleibt ein gesonderter Prüfpunkt. |
| Platzhalter und alte Beschreibungen | Leere Systemklassen und ältere Featuretexte sind keine verlässliche Funktionszusage. Beispielsweise ist die frühere Aussage über einen fehlenden Bodyguard-Kampfpfad durch die aktuelle Implementierung überholt. |

### 25.3 Noch erforderliche reale Abnahme

Für eine vollständige Releaseabnahme fehlen weiterhin reale Steam-Sitzungen mit zwei Kämpfern und zwei Zuschauern, Einladungen über Steam, Mikrofon- und Stimmwiedergabe auf echten Geräten sowie die Ausführung eines exportierten Builds auf dem Zielsystem. Kopflose Tests bestätigen keine endgültige Lesbarkeit, Bildwirkung oder Hörbarkeit jeder Ansicht. Diese Dokumentation ist deshalb eine detaillierte Beschreibung und ein nachweisbarer Projektcheck, aber keine pauschale Releasefreigabe.

### 25.4 Fehlgeschlagene und gesonderte Prüfungen

{{AUDIT_FINDINGS}}

## Anhang A Vollständiger Kampfkartenkatalog

Alle 93 Kampfkartentypen stehen in den folgenden Tabellen mit ihrer Katalogseltenheit, den Grundwerten und ihren angeborenen Effekten. Eine fehlende Kategorie in einem älteren Datensatz wird vom Spiel als Kampfkarte behandelt. Werte werden unmittelbar aus dem aktuellen Kartenkatalog übernommen. Als Erwerbsangabe bedeutet Zufall eine grundsätzlich zulässige zufällige Belohnung; konkrete Packchancen, Voraussetzungen und Sonderwege gelten zusätzlich.

Die Tabelle führt die vollständigen angeborenen Katalogeinträge auf. Im Kampf gelten weiterhin höchstens zwei aktive Effekte. So enthält die Kreditkarte drei Einträge; ihr dritter Eintrag Swap Stats wird hinter Shield First Hit und Grave Return nicht als zusätzlicher dritter Effekt aktiv.

{{COMBAT_CATALOG}}

## Anhang B Vollständiger Sonderkartenkatalog

Alle 25 Sonderkartentypen wirken außerhalb des Kampfdecks. Einzigartige Freischaltungen können regulär nur einmal erhalten werden; die beiden ausdrücklich stapelbaren Clickerverbesserungen sind davon ausgenommen. Zugehörige Voraussetzungen werden für Erwerb und Wirkung geprüft.

{{SPECIAL_CATALOG}}

## Anhang C Quellen und Zuständigkeiten

Die folgenden Stellen sind die maßgeblichen lokalen Projektquellen. Funktionsnamen erleichtern das Wiederfinden, auch wenn sich Zeilennummern später verschieben. Die Prüfprotokolle beziehen sich auf den dokumentierten Stand; spätere Änderungen können Regeln und Ergebnisse verändern.

{{SOURCE_INDEX}}

## Anhang D Vollständige Testübersicht

Die Übersicht nennt die tatsächlich ausgeführten beziehungsweise vom automatischen Sammellauf erfassten Szenensuiten. Nicht ausgeführt bedeutet keine negative Aussage zur Spielmechanik, sondern einen nicht durch diesen Lauf geprüften Fall. Bei bestandenen Suiten können absichtlich ausgelöste Speicherfehlermeldungen oder bestehende Shutdown-Warnungen im Protokoll stehen. Ergebnisse und Rohprotokolle sind zusätzlich im Ordner `docs/game-documentation/audit` abgelegt.

{{TEST_CATALOG}}
