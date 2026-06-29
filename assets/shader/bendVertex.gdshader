shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;

// 0.0 = flach, 1.0 = voll aufgebogen
uniform float bend_amount : hint_range(0.0, 1.0) = 0.0;

// Wie stark sich die Folie maximal aufbiegt (in Radiant), bei bend_amount = 1.0
uniform float max_bend_angle : hint_range(0.0, 3.14159) = 1.2;

// Zusaetzlicher "Knick"-Versatz nach oben, simuliert das Abheben der
// Folie vom Body, bevor sie sich komplett aufrollt.
uniform float lift_strength : hint_range(0.0, 1.0) = 0.3;

// Welche lokale Achse die "Anker"-Kante ist (0 = X, 1 = Y, 2 = Z) —
// hier gehen wir davon aus, dass die Biegung entlang lokaler X-Achse
// verlaeuft (Anker bei x = -0.5*size.x, freies Ende bei +0.5*size.x).
// Passe ggf. VERTEX.x auf VERTEX.y/.z um, falls deine Mesh-Achsen anders liegen.

varying float v_bend_t;

void vertex() {
	// Normalisierte Position entlang der Biege-Achse: 0 = Anker, 1 = freies Ende.
	// Annahme: Mesh reicht lokal von -0.5 bis +0.5 entlang X.
	float t = clamp(VERTEX.x + 0.5, 0.0, 1.0);
	v_bend_t = t;

	// Je weiter vom Anker entfernt, desto staerker biegt sich dieser Punkt.
	// Quadratisch statt linear, damit es nahe am Anker steif wirkt und zum
	// freien Ende hin "nachgibt" -- aehnlich wie echte duenne Folie.
	float local_bend = bend_amount * (t * t);
	float angle = local_bend * max_bend_angle;

	// Rotation um eine Achse parallel zur Anker-Kante (hier: lokale Z-Achse),
	// angewendet relativ zum Anker-Punkt (x = -0.5), nicht um den Mesh-Ursprung.
	float pivot_x = -0.5;
	float rel_x = VERTEX.x - pivot_x;

	float s = sin(angle);
	float c = cos(angle);

	// Rotation in der XY-Ebene um den Ankerpunkt (biegt nach "oben", +Y).
	float new_x = pivot_x + rel_x * c;
	float new_y = VERTEX.y + rel_x * s;

	VERTEX.x = new_x;
	VERTEX.y = new_y + lift_strength * local_bend * 0.1;

	// Normalen mitdrehen, damit Beleuchtung beim Biegen stimmt.
	NORMAL = normalize((mat3(
		vec3(c, s, 0.0),
		vec3(-s, c, 0.0),
		vec3(0.0, 0.0, 1.0)
	) * NORMAL));
}

void fragment() {
	ALBEDO = vec3(1.0);
	// Falls du eine Textur hast:
	// ALBEDO = texture(TEXTURE, UV).rgb;
}