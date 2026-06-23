shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D texture_albedo : source_color, filter_nearest;

uniform float threshold : hint_range(0.0, 1.0) = 0.1;
uniform float effect_alpha_mult : hint_range(0.0, 1.0) = 0.55;
uniform float direction : hint_range(0.0, 1.0) = 0.5;

uniform float specular_amount : hint_range(0.0, 1.0) = 1.0;
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.75;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.35;
uniform float emission_energy : hint_range(0.0, 2.0) = 0.25;

uniform float speed : hint_range(0.0, 5.0) = 0.45;
uniform float foil_scale : hint_range(1.0, 40.0) = 14.0;
uniform float rainbow_strength : hint_range(0.0, 2.0) = 1.1;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	vec2 u = f * f * (3.0 - 2.0 * f);

	return mix(a, b, u.x) +
		(c - a) * u.y * (1.0 - u.x) +
		(d - b) * u.x * u.y;
}

vec3 rainbow(float t) {
	return 0.5 + 0.5 * cos(6.28318 * (vec3(0.0, 0.33, 0.67) + t));
}

void fragment() {
	vec2 uv = UV;
	vec4 albedo_tex = texture(texture_albedo, uv);

	ALBEDO = albedo_tex.rgb;
	ALPHA = albedo_tex.a;

	float dark_mask = 1.0 - smoothstep(
		threshold,
		threshold + 0.15,
		max(max(albedo_tex.r, albedo_tex.g), albedo_tex.b)
	);

	dark_mask *= step(0.3, albedo_tex.a);

	float n = noise2d(uv * foil_scale + TIME * speed);
	float diagonal = uv.y * direction + uv.x * (1.0 - direction);

	float bands = sin((diagonal + n * 0.25 + TIME * speed) * 20.0);
	bands = pow(abs(bands), 3.0);

	float fresnel = pow(
		1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0),
		2.2
	);

	float foil = clamp((bands * 0.65 + n * 0.25 + fresnel * 0.8) * dark_mask, 0.0, 1.0);

	vec3 foil_col = rainbow(diagonal + n + TIME * speed * 0.15) * rainbow_strength;

	ALBEDO = mix(ALBEDO, foil_col, foil * effect_alpha_mult);

	METALLIC = metallic_amount * foil;
	ROUGHNESS = mix(0.75, roughness_amount, foil);
	SPECULAR = specular_amount * foil;

	EMISSION = foil_col * foil * emission_energy;
}