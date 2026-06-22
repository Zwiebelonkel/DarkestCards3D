shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, unshaded;

// Grundfarbe der Rarity (kommt aus _get_rarity_color in Card3D.gd)
uniform vec4 rarity_color : source_color = vec4(0.55, 0.55, 0.55, 1.0);

// Generelle Staerke des Effekts. Bei "common" auf 0 stellen, damit
// einfache Karten ruhig/unauffaellig bleiben.
uniform float intensity : hint_range(0.0, 3.0) = 1.0;

// Wie schnell die Energie/Risse ueber die Kante wandern.
uniform float scroll_speed : hint_range(0.0, 5.0) = 1.0;

// Wie viele Riss-/Energie-Baender gleichzeitig sichtbar sind.
uniform float band_density : hint_range(1.0, 12.0) = 4.0;

// Wie unregelmaessig/scharf die Risse aussehen (0 = weiche Wellen,
// 1 = scharfkantige Blitz-Risse).
uniform float jaggedness : hint_range(0.0, 1.0) = 0.3;

// Pulsieren zusaetzlich zur Wanderbewegung (0 = kein Pulsieren).
uniform float pulse_strength : hint_range(0.0, 1.0) = 0.25;
uniform float pulse_speed : hint_range(0.0, 10.0) = 2.0;

// Basis-Emission, damit auch ohne Energie-Baender ein leichtes
// Eigenleuchten in der Rarity-Farbe da ist.
uniform float base_glow : hint_range(0.0, 1.0) = 0.35;

// Multiplikator fuer die Gesamthelligkeit der Emission. Bei importierten
// GLB-Meshes mit unbekanntem UV-Layout verlassen wir uns NICHT auf UV,
// sondern auf die lokale Vertex-Position (siehe v_local_pos) — das
// funktioniert unabhaengig vom UV-Mapping des Outline-Modells.
uniform float emission_boost : hint_range(1.0, 20.0) = 6.0;

varying vec3 v_local_pos;
varying vec3 v_normal_view;

float hash(float n) {
	return fract(sin(n) * 43758.5453123);
}

float jagged_noise(float x) {
	float i = floor(x);
	float f = fract(x);
	float a = hash(i);
	float b = hash(i + 1.0);
	// step() statt smoothstep() fuer scharfkantigere "Risse" je hoeher
	// jaggedness ist.
	float t = mix(smoothstep(0.0, 1.0, f), step(0.5, f), jaggedness);
	return mix(a, b, t);
}

void vertex() {
	// VERTEX ist hier die lokale Modell-Position (vor jeglicher Welt-
	// Transform), das ist robust unabhaengig davon, ob das importierte
	// GLB sinnvolle/normalisierte UVs hat oder nicht.
	v_local_pos = VERTEX;
	v_normal_view = NORMAL;
}

void fragment() {
	// Wandernde Energie-Baender entlang der lokalen Y-Achse (Hoehe der
	// Karte), mit leichtem Versatz pro X fuer einen diagonalen
	// "Riss"-Look statt stumpf-horizontaler Streifen. Die lokale
	// Position ist in Modell-Einheiten (hier ungefaehr -0.5 .. 0.5),
	// daher mit einem Faktor auf eine sinnvolle Wellenlaenge skaliert.
	float t = TIME * scroll_speed;
	float wave_coord = v_local_pos.y * band_density - t + v_local_pos.x * 1.5;
	float n = jagged_noise(wave_coord);

	// Scharfe Energie-Adern: nur die "Spitzen" des Noise leuchten,
	// der Rest bleibt dunkel -> wirkt wie wandernde Risse/Blitze.
	float vein = smoothstep(0.55, 1.0, n);

	// Zusaetzliches feineres Detail-Rauschen fuer mehr "heftige" Optik.
	float fine = jagged_noise(wave_coord * 3.3 + 7.0);
	float fine_vein = smoothstep(0.7, 1.0, fine) * 0.6;

	float pulse = 1.0 + sin(TIME * pulse_speed) * pulse_strength;

	float energy = (vein + fine_vein) * intensity * pulse;

	// Fresnel-artiger Kantenglanz zusaetzlich zur Energie, damit der
	// Rahmen auch ohne aktive Adern nicht komplett flach wirkt.
	float fresnel = pow(1.0 - clamp(abs(dot(normalize(v_normal_view), vec3(0.0, 0.0, 1.0))), 0.0, 1.0), 2.0);

	vec3 base = rarity_color.rgb * base_glow;
	vec3 glow = rarity_color.rgb * energy;
	vec3 edge = rarity_color.rgb * fresnel * 0.5 * intensity;

	ALBEDO = rarity_color.rgb;
	EMISSION = (base + glow + edge) * emission_boost;
	ALPHA = rarity_color.a;
}
