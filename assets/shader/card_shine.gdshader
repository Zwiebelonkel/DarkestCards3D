shader_type spatial;
render_mode blend_add, cull_back, depth_draw_never, unshaded;

// Position des Streifens entlang der Diagonale, 0 = ganz links/unten
// ausserhalb der Karte, 1 = ganz rechts/oben ausserhalb der Karte.
// Wird von Card3D.gd per Tween animiert (0 -> 1 alle paar Sekunden).
uniform float sweep_position : hint_range(-0.5, 1.5) = -0.5;

// Breite des Lichtstreifens in UV-Einheiten.
uniform float sweep_width : hint_range(0.01, 1.0) = 0.18;

// Wie schraeg der Streifen ueber die Karte laeuft (0 = senkrecht,
// hoehere Werte = staerker diagonal wie bei klassischen Foil-Karten).
uniform float sweep_skew : hint_range(0.0, 3.0) = 1.1;

// Farbe/Intensitaet des Glanzes.
uniform vec4 shine_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float shine_strength : hint_range(0.0, 5.0) = 1.6;

void fragment() {
	// Diagonale Koordinate: UV.x + UV.y * skew ergibt eine schraege
	// Linie konstanter "Diagonalposition" ueber die Kartenflaeche.
	float diag = UV.x + UV.y * sweep_skew;
	float diag_max = 1.0 + sweep_skew;
	float d = diag / diag_max;

	float dist = abs(d - sweep_position);
	float band = smoothstep(sweep_width, 0.0, dist);

	// Weicher, leicht prismatischer Verlauf innerhalb des Streifens,
	// statt eines stumpfen einfarbigen Balkens.
	float core = pow(band, 2.0);

	ALBEDO = shine_color.rgb;
	EMISSION = shine_color.rgb * core * shine_strength;
	ALPHA = core * shine_color.a;
}
