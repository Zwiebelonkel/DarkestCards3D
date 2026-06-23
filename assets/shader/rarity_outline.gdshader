shader_type spatial;
render_mode blend_add, cull_disabled, unshaded, depth_draw_never;

uniform vec4 rarity_color : source_color = vec4(0.2, 0.6, 1.0, 1.0);

uniform float thickness : hint_range(0.001, 0.3) = 0.055;
uniform float softness : hint_range(0.001, 0.3) = 0.045;
uniform float corner_radius : hint_range(0.0, 0.5) = 0.12;

uniform float glow_strength : hint_range(0.0, 10.0) = 3.0;
uniform float outer_glow : hint_range(0.0, 1.0) = 0.18;

uniform float speed : hint_range(0.0, 5.0) = 1.2;
uniform float energy_density : hint_range(1.0, 30.0) = 12.0;
uniform float jaggedness : hint_range(0.0, 1.0) = 0.65;
uniform float pulse_strength : hint_range(0.0, 1.0) = 0.25;

varying vec2 v_uv;

float hash(float n) {
	return fract(sin(n) * 43758.5453123);
}

float noise_1d(float x) {
	float i = floor(x);
	float f = fract(x);
	float a = hash(i);
	float b = hash(i + 1.0);
	float t = mix(smoothstep(0.0, 1.0, f), step(0.5, f), jaggedness);
	return mix(a, b, t);
}

float rounded_box_sdf(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, 0.0)) - r + min(max(q.x, q.y), 0.0);
}

void vertex() {
	v_uv = UV;
}

void fragment() {
	vec2 uv = v_uv;

	vec2 p = uv - vec2(0.5);
	vec2 half_size = vec2(0.5);

	float sdf = rounded_box_sdf(p, half_size, corner_radius);

	float dist_to_edge = abs(sdf);

	float inside = step(sdf, 0.0);

	float outline = 1.0 - smoothstep(thickness, thickness + softness, dist_to_edge);
	outline *= inside;

	float glow = 1.0 - smoothstep(thickness, thickness + outer_glow, dist_to_edge);
	glow *= inside;

	float edge_coord = 0.0;

	if (abs(p.x) > abs(p.y)) {
		edge_coord = uv.y + step(0.0, p.x);
	} else {
		edge_coord = uv.x + 2.0 + step(0.0, p.y);
	}

	float moving = edge_coord * energy_density - TIME * speed;
	float n = noise_1d(moving);
	float veins = smoothstep(0.55, 1.0, n);

	float pulse = 1.0 + sin(TIME * 3.0) * pulse_strength;

	float energy = outline + veins * outline * pulse;
	float alpha = clamp(energy + glow * 0.45, 0.0, 1.0);

	vec3 col = rarity_color.rgb * (energy * glow_strength + glow * glow_strength * 0.5);

	ALBEDO = col;
	EMISSION = col;
	ALPHA = alpha * rarity_color.a;
}