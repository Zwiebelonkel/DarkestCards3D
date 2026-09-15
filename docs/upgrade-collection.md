# Upgrade-Sammlung

Die normale Kartensammlung zeigt Kampfkarten und die Schlüsselkarte. Clicker,
Clicker-Upgrades und Starthand I–V hängen als eigene Sammlung an der Wand des
zweiten Raums. Die Wand zeigt nur bereits gefundene Karten, pro Kartentyp einmal
mit der vorhandenen Anzahl. Neue Funde und ein Spielreset aktualisieren sie.

Nach dem Betreten des Automatenraums zur Wand drehen. Beim Hover über die
Sammlung fährt die Kamera wie beim Packshop näher heran; auch die freien Stellen
zwischen den Karten zählen dazu. Verlässt der Mauszeiger die Wand, fährt sie
wieder zurück. Beim Anklicken fliegt die Karte von ihrem Platz an der Wand in
die große Detailansicht. Ein weiterer Klick oder die **Esc**-Taste lässt sie an
ihren Platz zurückfliegen. Es gibt keinen Zurück-/Escape-Button in der Ansicht.
Während beider Flüge bleibt die Kamera auf der Sammlung und die übrige Eingabe
gesperrt. Pause legt die Karte sofort zurück und sperrt die Eingabe bis zum Fortsetzen.
Die Schlüsselkarte bleibt in der normalen Sammlung mit ihrer Aktion **Zur Tür**.

Die Trennung betrifft die Anzeige. Bereits erhaltene Freischaltungen,
Clicker-Boni, Kartenmengen und Holo-Kopien bleiben erhalten und wirken wie zuvor.

Die eigenständige Szene `scenes/props/UpgradeWallCollection.tscn` wird von Main
als `EmptyRoom/UpgradeCollection` eingesetzt. Sie sitzt an der +Z-Wand des
Raums; `view_side = 3` entspricht dieser Blickrichtung im gemeinsamen Kamerasystem.
Ihre `FocusArea` nutzt denselben `ScreenCameraFocus` wie die Shop-Bildschirme.
`CardData.is_upgrade_collection_card()` legt die gemeinsame Abgrenzung beider
Sammlungen fest.

Alle Einstellungsregler und Checkbox-Symbole erhalten eine weiße Kontur von
einem Pixel. Der wiederverwendbare Helfer `SettingsControlOutlines` übernimmt
auch Hover- und deaktivierte Zustände. Die Stimmregler nutzen dieselben
Abstände und die verfügbare Panelbreite, damit ihre Spuren vollständig sichtbar sind.
