shader_type canvas_item;
render_mode unshaded;

uniform vec4 blood_color : source_color = vec4(0.64, 0.008, 0.018, 0.42);
uniform float border_width : hint_range(0.02, 0.35) = 0.1;
uniform float feather : hint_range(0.005, 0.15) = 0.065;
uniform float irregularity : hint_range(0.0, 0.2) = 0.02;
uniform float corner_radius : hint_range(0.02, 0.3) = 0.16;
uniform float fade_progress : hint_range(0.0, 1.0) = 1.0;
uniform float pattern_seed = 0.0;

// Hashes ohne sin(): reine ALU-Operationen, schneller und stabil auf Mobile/Web
// (der sin()-Hash verliert bei großen Eingaben/Seeds Präzision).
float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float hash21(vec2 p) {
	vec3 p3 = fract(p.xyx * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 hash31(float p) {
	vec3 p3 = fract(vec3(p) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xxy + p3.yzz) * p3.zyx);
}

// 1D-Value-Noise: halb so viele Hashes wie 2D (die Klumpen hängen pro Kante
// ohnehin nur von einer Koordinate ab).
float noise1(float x) {
	float cell = floor(x);
	float t = fract(x);
	t = t * t * (3.0 - 2.0 * t);
	return mix(hash11(cell), hash11(cell + 1.0), t);
}

float noise2(vec2 p) {
	vec2 cell = floor(p);
	vec2 t = fract(p);
	t = t * t * (3.0 - 2.0 * t);
	return mix(mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), t.x),
		mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0)), t.x), t.y);
}

void fragment() {
	// Per Script gesetzte Werte werden nicht durch hint_range geklammert;
	// ein Overshoot im Tween würde sonst pow() mit negativer Basis (NaN) füttern.
	float fade = clamp(fade_progress, 0.0, 1.0);
	float opacity = blood_color.a * pow(1.0 - fade, 1.35);

	// Komplett ausgeblendet: sofort raus, kein Noise, kein Blending.
	if (opacity < 0.002) {
		discard;
	}

	// Abstand zu allen vier Kanten, gemessen an der kürzeren Bildschirmseite.
	vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 aspect = screen_size / min(screen_size.x, screen_size.y);
	vec2 point = UV * aspect;
	float retreat = smoothstep(0.0, 1.0, fade);

	float mottling = noise2(point * 19.0 + pattern_seed) * 0.65
		+ noise2(point * 47.0 + pattern_seed) * 0.35;

	// Durchgehender Rand um eine abgerundete, freie Bildmitte.
	// Beim Ausblenden wächst die freie Fläche über den Bildschirm hinaus.
	float inset = mix(border_width, -feather - corner_radius, retreat);
	vec2 half_extent = aspect * 0.5 - vec2(inset);
	float radius = min(corner_radius, min(half_extent.x, half_extent.y));
	vec2 q = abs(point - aspect * 0.5) - half_extent + vec2(radius);
	float distance_to_clear_area = length(max(q, vec2(0.0)))
		+ min(max(q.x, q.y), 0.0) - radius;
	float wobble = (noise2(point * 4.0 + pattern_seed) - 0.5) * irregularity;
	float mask = smoothstep(-feather, feather, distance_to_clear_area + wobble);

	// Unsichtbare Pixel verwerfen (spart Blending im großen, leeren Bildschirmbereich).
	float alpha = mask * opacity;
	if (alpha < 0.002) {
		discard;
	}

	vec3 tint = blood_color.rgb * (0.85 + 0.22 * mottling);
	COLOR = vec4(tint, alpha);
}
