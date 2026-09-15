# Keller und Friedhof

Keller und Friedhof stehen direkt in `scenes/main/Main.tscn` als
`BasementRoom` und `GraveyardRoom`. Beide gehören zur gemeinsamen 3D-Welt und
verwenden dieselbe Main-Kamera wie Hub und Slotraum. Die Kamera fliegt beim
Türklick sichtbar durch die geöffneten `HospitalDoor`-Türrahmen und den
Verbindungsgang zum festen Mittelpunkt des Zielraums. Der Rückweg führt durch
dieselben Türen zurück zur vorherigen Hub-Position und Blickrichtung.

Am festen Standpunkt dreht A/D den Blick wie im Slotraum um 90°. Die sichtbare
Rückkehrtür lässt sich nach dem Drehen anklicken. Escape öffnet das reguläre
Pausemenü. Die Räume haben keine eigene Kamera, kein eigenes HUD und keinen
separaten Viewport. Es gibt keine Wegpunkt- oder W/S-Steuerung und keine
eigenständige F6-Besichtigung.

## Raumbausteine und Gestaltung

Die wiederverwendbaren Szenen enthalten direkt im Godot-Editor bearbeitbare
Geometrie, Materialien und lokale Beleuchtung:

- `scenes/rooms/Basement.tscn`: dieselbe texturierte `HospitalRoomShell` wie im
  Slotraum, ergänzt um Heizkessel, Rohre, Lager und Pumpen. Ein geschlossener
  Treppengang mit Podesten, Geländern und Lampen verbindet die unterschiedlichen
  Bodenhöhen von Hub und Keller.
- `scenes/rooms/Graveyard.tscn`: Grabreihen, Eisenzaun, kahle Bäume, Laternen und
  Gruft mit gedämpften, abgenutzten Materialien. Eine offene Hospitalfassade und
  ein beleuchteter Gang verbinden den Friedhof mit dem Hub.

Beide Wurzelknoten bleiben in der gemeinsamen Welt. Der Keller verwendet
`BasementDiscovery.gd` für seine Kisten und den versteckten Schlüssel.
`CameraAnchor` legt den festen
Kamerastandpunkt samt Blickrichtung fest; Main verwendet dessen Position und
Rotation mit seinem vorhandenen Kameraoffset. `ReturnDoor` ist eine echte
Instanz von `scenes/props/HospitalDoor.tscn` mit schwenkendem Türblatt. Die
Durchgänge bleiben geometrisch offen und müssen zum jeweiligen Hub-Zugang
passen. Raumhüllen und Böden dürfen benachbarte Öffnungen nicht verdecken.

`scripts/main/Main.gd` verwaltet Hin- und Rückflug, Drehung und Interaktionen.
Die Zugänge unter `ProgressionAreas` ordnen über `room_index` den Friedhof
(`2`) und Keller (`3`) zu. Während eines Türflugs sind weitere Interaktionen
gesperrt; anschließend gelten die normalen Main-Steuerungen. Die Szenen bleiben
in Main instanziert.

Die Zugänge und Rückwege tragen keine Raumnamen, Zugangstexte oder
Wegweiserbeschriftungen. Auch das HUD und das Journal geben keine Raum- oder
Fundort-Tipps. Dekorative Maschinen- und Grabinschriften bleiben Teil der Kulisse.

## Hospital-Raumhülle mit echten Öffnungen

`scripts/tools/build_connected_hospital_shell.py` erzeugt
`scenes/rooms/ConnectedHospitalRoomShell.glb` aus der vorhandenen
`scenes/rooms/HospitalRoomShell.glb`. Aufruf vom Projektverzeichnis:

```powershell
py -3 scripts/tools/build_connected_hospital_shell.py
```

Der Generator teilt die Dreiecke an den beiden zusätzlichen Hub-Türöffnungen
und entfernt die Flächen innerhalb der Ausschnitte. Neue Randpunkte übernehmen
linear interpolierte Vertexattribute einschließlich UV-Koordinaten; Normalen
werden normalisiert. Materialzuweisungen, Texturen und deren bestehende
UV-Abbildung bleiben erhalten. Die Ausgangsdatei und die vom Slotraum verwendete
Raumhülle werden nicht verändert.

`ConnectedHospitalRoomShell.tscn` bindet das erzeugte GLB für den Hub ein. Die
Öffnungsmaße und Positionen im Generator entsprechen den Türen in Main. Werden
diese versetzt oder skaliert, müssen die Ausschnitte entsprechend angepasst,
neu erzeugt und in Godot importiert werden.

## Zugang und Rückkehr

`basement_key` und `graveyard_key` schalten weiterhin ihre jeweiligen Zugänge
frei. Die Karten werden beim Besuch nicht verbraucht; der besuchte Zugang wird
über die bestehende Sammlung gespeichert. Die Rückkehrtür bleibt bedienbar,
auch wenn die zugehörige Karte während des Aufenthalts verloren geht oder die
Sammlung neu geladen wird. Eine erneute Einreise prüft wieder den gültigen Zugang.

## Kisten und Friedhofsschlüssel

Alle 14 Holzkisten im Keller lassen sich mit der linken Maustaste wegschleudern.
`BasementCrate.gd` verwendet dafür das Geometriepicking und die anfängliche
Wurfgeschwindigkeit von `LocalTableProp.gd`, mit einem eigenen Zufallsgenerator.
Anschließend übernimmt ein `RigidBody3D` mit kontinuierlicher Kollisionserkennung
die Bewegung. `BasementDiscovery.gd` erzeugt aus der tatsächlichen Raumhülle
und den festen Regalflächen einen unskalierten Kollisionskörper. Die Kisten
prallen an Wänden ab und landen auf Boden oder Regalen.

Nach standardmäßig vier Sekunden beginnt der vorhandene, auf Godot 4 angepasste
`assets/shader/dissolve.gdshader`, alle Holz- und Metallteile gemeinsam aufzulösen.
Die Auflösung dauert 1,2 Sekunden; beide Zeiten sind an der Kiste einstellbar.
Danach werden Physikkörper und Kollision entfernt. Die Kisten sind nur während
des aktiven Kellerbesuchs bedienbar;
Drehung, Türfahrt, Pause und offene Menüs sperren ihre Pickflächen.

Unter `Storage/FloorCrate` liegt eine echte, zunächst verdeckte `Card3D` mit
`graveyard_key`. Beim Wegwerfen wird sie wie der Messerschlüssel automatisch
der Sammlung hinzugefügt, kurz angehoben und mit dem Sonderkarten-Effekt
gezeigt. Ein zusätzlicher Sammelklick ist nicht erforderlich. Der Schlüssel
ist über `random_reward: false` von Packs und Zufallsbelohnungen ausgeschlossen.
Bereits vorhandene Schlüssel und gespeicherte Friedhofszugänge bleiben gültig;
erneutes Betreten oder Laden erzeugt keine zweite Karte.

## Feuerstelle im Friedhof

`GraveyardBrazier.tscn` steht als Feuerstelle neben dem Hauptweg im Friedhof.
Die Flammen verwenden `assets/shader/fire.gdshader` mit einer transparenten
Silhouette und einer Rauschtextur. Die Shader-Billboard-Ausrichtung erhält die
Skalierung des Friedhofs in Main. `BrazierFire.gd` variiert die warme lokale
Beleuchtung ohne den globalen Zufallsgenerator zu verändern.

## Prüfung

`tests/exploration_rooms_test.tscn` prüft die dauerhaft in Main instanzierten
Räume, gemeinsame Kamera und Welt, echte Mausklicks auf Hin- und Rücktüren,
beide Türschwellen während der Fahrt, die Ankerposition, A/D-Drehung, Pause und
Rückkehr nach Kartenverlust. `tests/progression_areas_test.tscn` prüft getrennte
Freischaltungen und den verbundenen Black-Market-Raum sowie das Fehlen eigener
Viewports und Overlays in den verbundenen Räumen.

Der [Black Market](black-market.md) ist als Raumindex `4` mit Kiosk, Jester und
täglich wechselnder Angebotstafel angebunden. Auch sein westlicher Hub-Zugang
hat eine echte Öffnung in `ConnectedHospitalRoomShell`.

`tests/basement_discovery_test.tscn` prüft zusätzlich Kistenpicking, Fund,
Interaktionssperren und den gespeicherten, einmaligen Schlüsselbesitz.
`tests/basement_crate_physics_test.tscn` prüft zusätzlich Wand- und Bodenkontakt,
die verzögerte Auflösung aller Teile, Pause und das Entfernen der Physikkörper.

Beide laufen über `tests/run_match_feature_tests.ps1` mit `-ImportAssets`, dem
jeweiligen `-TestScene` und `-SuccessMarker`; der Runner verwendet isolierte
Spielstände. Bei der visuellen Prüfung in Main auch auf freie Sicht durch beide
Türrahmen und auf Boden- und Deckenanschlüsse entlang des Kellerabstiegs achten.

Vorschauen: [Keller](previews/basement.png) · [Friedhof](previews/graveyard.png) ·
[Kistenwurf](previews/basement-crate-throw.png) · [Schlüsselfund](previews/basement-discovery.png) ·
[Kiste nach Wandkontakt](previews/basement-crate-landed.png) ·
[Kistenauflösung](previews/basement-crate-dissolve.png) · [Feuerstelle](previews/graveyard-fire.png).
