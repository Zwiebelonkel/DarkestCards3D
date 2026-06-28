shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

uniform vec4 rarity_color : source_color = vec4(1.0, 0.2, 0.2, 1.0);

uniform float glow_strength : hint_range(0.0, 3.0) = 1.0;
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.9;

uniform float pulse_speed : hint_range(0.0, 10.0) = 2.0;
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.25;

uniform float edge_power : hint_range(0.5, 6.0) = 2.2;

uniform float flicker_strength : hint_range(0.0, 1.0) = 0.0;
uniform float flicker_speed : hint_range(0.0, 60.0) = 18.0;

uniform float aberration_strength : hint_range(0.0, 0.02) = 0.0;

uniform float distortion_strength : hint_range(0.0, 0.05) = 0.0;
uniform float distortion_speed : hint_range(0.0, 10.0) = 3.0;

float flicker_noise(float t) {
	float n = sin(t * 12.9898) * 0.5;
	n += sin(t * 27.233 + 1.7) * 0.3;
	n += sin(t * 53.71 + 3.1) * 0.2;
	return n;
}

void fragment() {
	vec2 uv = SCREEN_UV;

	vec2 centered = uv - vec2(0.5);
	float dist = length(centered);

	float vignette = smoothstep(0.15, 0.85, dist);
	vignette = pow(vignette, edge_power);

	vec2 distort_offset = vec2(
		sin(uv.y * 18.0 + TIME * distortion_speed),
		cos(uv.x * 16.0 + TIME * distortion_speed * 0.8)
	) * distortion_strength * vignette;

	vec2 distorted_uv = uv + distort_offset;

	vec2 aberration_dir = normalize(centered + vec2(0.0001));
	float aberration_amount = aberration_strength * vignette;

	vec4 screen_col;
	screen_col.r = texture(screen_texture, distorted_uv + aberration_dir * aberration_amount).r;
	screen_col.g = texture(screen_texture, distorted_uv).g;
	screen_col.b = texture(screen_texture, distorted_uv - aberration_dir * aberration_amount).b;
	screen_col.a = texture(screen_texture, distorted_uv).a;

	float pulse = 1.0 + sin(TIME * pulse_speed) * pulse_amount;
	float flicker = 1.0 + flicker_noise(TIME * flicker_speed) * flicker_strength;

	vec3 glow = rarity_color.rgb
		* vignette
		* vignette_strength
		* glow_strength
		* pulse
		* flicker;

	COLOR = vec4(screen_col.rgb + glow, screen_col.a);
}