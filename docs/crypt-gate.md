# Krypta-Gitter

Im Friedhof bewegt sich das Krypta-Gitter beim Darüberfahren mit der Maus um
drei Grad. Alle sieben Stäbe und beide Querstreben schwingen gemeinsam;
beim Verlassen des Gitters fahren sie weich in die geschlossene Stellung zurück.
Die Trefferfläche bleibt dabei im Türrahmen, damit der Hover stabil bleibt.

Linksklick führt mit der vorhandenen Kamera und den normalen Schrittgeräuschen
direkt vor das Gitter. Der nahe Standpunkt bleibt auch beim Wegbewegen der Maus
erhalten. A/D und die Drehpfeile drehen direkt am neuen Standpunkt, auch einmal
vollständig herum, ohne zum bisherigen Mittelpunkt zurückzuspringen.

Beim Blick zurück auf die Kreuzung erscheint unter dem Mauszeiger eine kleine
türkisfarbene Beacon-Markierung mit Bodenring und schwebendem Kristall. Verlässt
der Mauszeiger die Kreuzung, verschwindet die Markierung. Linksklick auf die
Kreuzung führt zum ursprünglichen Standpunkt zurück und behält die aktuelle
Blickrichtung bei, statt sich wieder zur Krypta zu drehen. Rechtsklick oder Esc
bleiben als zusätzliche Rückwege verfügbar.

Nur die Vorderansicht des aktiven Friedhofs erlaubt die Interaktion. Während
des Gehens sind weitere Klicks und Drehungen gesperrt. Pause, Journal, Dialoge
und Raumwechsel benutzen weiterhin die bestehenden Eingabesperren. Die
Interaktion verändert weder Karten noch Währung oder Spielfortschritt. Der
entfernte Jester und die Ausgangstür bleiben am Krypta-Standpunkt deaktiviert;
die normalen Interaktionen werden nach der Rückkehr zur Kreuzung freigegeben.

`Main.gd` hängt `CryptGate.gd` zur Laufzeit unter `GraveyardRoom/Crypt` ein;
die vorhandene Friedhofszene bleibt unverändert. Der Controller gruppiert die
sichtbaren Gitterteile unter einem Scharnier und prüft den Kamerastrahl gegen
eine feste Fläche im Durchgang.

`tests/crypt_gate_test.tscn` prüft Hover und echte Mausereignisse, den nahen
Standpunkt, beide Rückwege, A/D, Pause, Journal und die normale Rückkehr in den
Hub, freie Drehungen am Gitter sowie Beacon-Hover und Linksklick-Rückkehr.
Der Test muss wie die anderen Raumtests in einer Projektkopie mit
umgeleiteten Speicherpfaden und deaktivierter Begrüßung laufen, etwa über
`tests/run_collection_tests.ps1 -Scenes crypt_gate_test`.
