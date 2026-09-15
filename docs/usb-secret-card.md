# Secret-Karten mit einem 3D-Raum im Bildfeld

Die Karten `usb_stick`, `cigarettes` und `moewenmilch` sind spielbare Secret-Karten
mit jeweils 32 Angriff und 32 Verteidigung. Erfolgreiches Umwerfen der jeweiligen
Tischobjekte zählt pro Spielstand: USB-Stick 50-mal, Zigaretten 80-mal und
Möwenmilch 150-mal. Beim Erreichen der Grenze zeigt eine kurze Kartenanimation
den Fund; danach lässt sie sich
in der Sammlung wie andere Karten betrachten, mit der Maus kippen und ins Deck
nehmen. Der Fund ist pro Spielstand einmalig, auch nach Verbrauch der Karte.
Packs enthalten diese Karten nicht. Der Jester vergibt nach Abschluss seiner
Opfergaben eine der drei Karten; auch diese Belohnung vermerkt den Fund und
verhindert eine spätere doppelte Entdeckungsbelohnung am Tisch. Developer und
Missing Texture sind wieder exotisch.

Der Zähler wird nach jedem Wurf gespeichert. Derselbe fliegende Gegenstand
zählt nur einmal; neue Gegenstände in anderen Räumen und nach Neustarts zählen
zum selben Fortschritt. Vorhandene Karten und frühere Funde bleiben erhalten.
Die Sammlung ergänzt neue Secrets direkt nach dem Eingabeereignis, auch bei
offener Detailansicht. Das SECRET-Schild erscheint erst nach dem ersten Fund.

## Darstellung

`artwork_scene` verweist auf einen eigenen Tresorraum; das normale Bildfeld
`image` bleibt leer. Alle Räume verwenden die vorhandenen Originalmodelle und
Materialien:

| Karte | Szene | Originalmodell |
| --- | --- | --- |
| USB-Stick | `scenes/cards/UsbSecretRoom.tscn` | `assets/environments/props/usb/scene.gltf` |
| Zigaretten | `scenes/cards/CigarettesSecretRoom.tscn` | `assets/environments/props/cigarettes/cigs.glb` |
| Möwenmilch | `scenes/cards/SeagullMilkSecretRoom.tscn` | `assets/environments/props/beer/energy.glb` |

Zigaretten stehen im rot beleuchteten Raum, Möwenmilch im grünen Raum.
`PropSecretRoom.gd` stellt diese Modelle anhand ihrer gedrehten Import-Bounds
auf den Sockel, ohne gemeinsam genutzte Materialien zu verändern.
Alle drei Gegenstände drehen sich dauerhaft um ihre eigene senkrechte Achse
mit 12 Grad pro Sekunde (eine volle Drehung in 30 Sekunden). Nur das Objekt
dreht sich; Raum und Sockel bleiben fest. Die Geschwindigkeit lässt sich über
`rotation_speed_degrees` im jeweiligen Raumskript einstellen.

`CardDiorama.gd` rendert ihn in eine eigene 560 × 340 Pixel große SubViewport
mit unabhängiger World3D und Kamera. Die Position der tatsächlichen Kamera
relativ zum Bildfeld bestimmt eine asymmetrische Perspektivprojektion.
Das Bildfeld bildet dabei die vordere Begrenzung des Raums: Beim Drehen der
Karte erscheinen andere Seiten des Gegenstands und andere Teile der Wände.
Der Raum hat weder Eingabeobjekte noch einen aktiven Audio-Listener.

Verdeckte Rückseiten, ausgeblendete oder außerhalb des Bildschirms liegende
Karten setzen das Rendern aus. Erneutes `setup()` derselben Karte verwendet
den vorhandenen Raum weiter. Beim Wechsel zu normalem Kartenbild oder beim
Entfernen der Karte wird er freigegeben. Die bestehenden Holo-, Blut- und
Auflösungseffekte arbeiten mit derselben Viewport-Textur.

## Speicherung und Prüfung

`CollectionManager.discover_prop_secret(card_id, random)` speichert den Zähler
unter `metadata.prop_secret_throws`. Am Ziel speichert es die genaue Instanz
und den Fund gemeinsam, bevor es eine Änderung meldet. Der lokale Zufallsgenerator
des Tischobjekts erzeugt die Instanz und den möglichen Holo-Zustand, ohne die
Zufallsfolge eines laufenden Kampfes zu verändern. Bei einem Schreibfehler
bleiben Zähler, Besitz, Fundhistorie und dieser Zufallszustand unverändert.

`tests/usb_secret_card_test.tscn` prüft die echte Card3D im Forward+-Renderer
einschließlich Perspektiven, Sichtbarkeit, Wiederverwendung und Materialien.
`tests/usb_secret_backend_test.tscn` prüft Erwerb, Speicherung und Spielstände.
`tests/usb_secret_discovery_test.tscn` prüft für alle drei Originalmodelle echte
Eingaben, wiederholte Funde und die Fundanimation.
Tests laufen mit dem isolierten Projekt und umgeleiteten Speicherdaten.

Vorschauen: [frontal](previews/usb-secret-front.png),
[links](previews/usb-secret-left.png), [rechts](previews/usb-secret-right.png).
