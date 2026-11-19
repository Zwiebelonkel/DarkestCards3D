shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float effect_mix : hint_range(0.0, 1.0) = 0.0;

float grain(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 center = SCREEN_UV - vec2(0.5);
	float breath = sin(TIME * 1.8);
	vec2 uv = SCREEN_UV + center * breath * 0.008 * effect_mix;
	uv += vec2(sin(uv.y * 9.0 + TIME * 0.7), cos(uv.x * 8.0 - TIME * 0.6)) * 0.003 * effect_mix;
	uv = clamp(uv, vec2(0.002), vec2(0.998));
	vec3 source = texture(screen_texture, SCREEN_UV).rgb;
	vec3 col = texture(screen_texture, uv).rgb;
	// Soft amber/rose halation instead of the weed swirl or cocaine's sharp RGB split.
	vec2 spread = SCREEN_PIXEL_SIZE * (5.0 + 2.0 * breath);
	vec3 halo = (texture(screen_texture, clamp(uv + vec2(spread.x, 0.0), vec2(0.002), vec2(0.998))).rgb
		+ texture(screen_texture, clamp(uv - vec2(spread.x, 0.0), vec2(0.002), vec2(0.998))).rgb
		+ texture(screen_texture, clamp(uv + vec2(0.0, spread.y), vec2(0.002), vec2(0.998))).rgb
		+ texture(screen_texture, clamp(uv - vec2(0.0, spread.y), vec2(0.002), vec2(0.998))).rgb) * 0.25;
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, 1.28);
	col += halo * vec3(0.22, 0.10, 0.17);
	float warmth = 0.5 + 0.5 * sin(TIME * 0.45 + center.x * 3.0 + center.y * 2.0);
	col *= mix(vec3(1.15, 0.92, 1.08), vec3(1.10, 1.02, 0.88), warmth);
	float noise = grain(floor(SCREEN_UV / SCREEN_PIXEL_SIZE) + floor(TIME * 24.0));
	col += (noise - 0.5) * 0.055;
	float edge = smoothstep(0.2, 0.72, length(center));
	col += edge * vec3(0.055, 0.012, 0.07) * (0.8 + 0.2 * breath);
	COLOR = vec4(mix(source, clamp(col, vec3(0.0), vec3(1.0)), effect_mix), 1.0);
}
