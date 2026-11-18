# Pack-Oberflächen

Basic, Ultra und God verwenden unterschiedliche, bewusst sehr dezente
Höhenstrukturen unter einer glänzenden Kunststofflaminierung:

- Basic: feines Noise.
- Ultra: verzerrte, fließende Noise-Struktur.
- God: flache Mondkrater mit feinem Staub.

Nach visueller Rückmeldung wurde das Relief stark reduziert. Die Muster sollen
hauptsächlich in Lichtreflexen sichtbar werden. Farbmodulation beträgt höchstens
wenige Prozent; es gibt keine Emission und keine animierten Muster.

`scripts/packs/PackSurface.gd` enthält die drei Profile. `surface_relief` ist
0.00035 / 0.0006 / 0.0008, die Grundrauheit 0.33 / 0.32 / 0.31. Die gemeinsame
Kunststoffschicht verwendet Clearcoat 0.18 und Clearcoat-Rauheit 0.30.

Die drei vorberechneten 512×512-L8-Texturen mit Mipmaps liegen in
`assets/cards/pack/surfaces/`. `tools/pack_surfaces/bake_heightmaps.tscn` erzeugt
sie deterministisch mit Godot neu; im Spiel erfolgt keine Noise-Generierung.
Die Reliefberechnung benötigt einen zusätzlichen Texture-Zugriff pro Fragment.

Shopvorschau und gekaufte Packs verwenden dieselben Profile. Der Packkörper und
die aufreißbare Oberkante teilen physische Pack-Koordinaten; die Druckmotive
behalten ihre UVs und Pixeloptik. Die silberne Innenseite bleibt beim Aufreißen
erhalten. Materialien werden pro Instanz gesetzt; importierte GLBs bleiben
unverändert. Es entstehen keine zusätzlichen Meshes, Dreiecke oder Draw Calls.

## Validierung am 15.11.2026

- `pack_surface_test.tscn`: 54 Prüfungen im Forward+-Renderer bestanden,
  einschließlich Musterzuordnung, Shopvorschau, unveränderter Importmaterialien,
  wiederholter Anwendung und unbekannter IDs.
- `pack_foil_test.tscn`: 115 Prüfungen mit allen drei echten Packtypen bestanden,
  einschließlich Kauf, Teilabriss, Loslassen, Wiederaufnehmen, Fokusverlust,
  Belohnungen und Zurücksetzen. Keine Script-, Shader- oder Enginefehler.
- `pack_surface_context.tscn`: echte Hauptszene, links zum Shop gedreht und Ultra
  gekauft; mit unveränderter Raumbeleuchtung und Nachbearbeitung geprüft.
- Vorher/Nachher mit gleicher vorhandener Peel-Geometrie: jeweils 9 Draw Calls
  und 4002 gemeldete Renderprimitive für die drei Packs; ca. 15.99 ms pro Frame
  unter dem Frame-Limit. Das ist keine GPU-Leistungsgrenze oder Exportmessung.

Bildnachweise und Berichte: `docs/validation/pack-surfaces/`. Front, Rückseite,
schräger Blick, Teilabriss, Shop und Hauptszene wurden visuell geprüft.
Tests liefen mit umgeleiteten Spielständen und deaktivierter Steam-Verbindung
in einer isolierten Projektkopie. Bestehende Editor-/Spielprozesse blieben offen.
Exportierte Builds und Live-Steam wurden nicht geprüft.
