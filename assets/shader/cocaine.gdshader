shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float effect_mix : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 center = SCREEN_UV - vec2(0.5);
	float t = TIME;
	float pulse = sin(t * 5.0) * 0.012 + sin(t * 9.3) * 0.004;
	vec2 uv = vec2(0.5) + center * (1.0 - pulse * effect_mix);
	uv.x += sin(uv.y * 30.0 + t * 7.0) * 0.0025 * effect_mix;
	vec2 split = center * (0.014 + 0.005 * sin(t * 3.0)) * effect_mix;
	vec3 source = texture(screen_texture, SCREEN_UV).rgb;
	vec3 col = vec3(texture(screen_texture, uv + split).r,
		texture(screen_texture, uv).g, texture(screen_texture, uv - split).b);
	vec3 edge = col - (texture(screen_texture, uv + SCREEN_PIXEL_SIZE * 2.0).rgb
		+ texture(screen_texture, uv - SCREEN_PIXEL_SIZE * 2.0).rgb) * 0.5;
	col = (col - 0.5) * 1.16 + 0.5 + edge * 1.1;
	float bright = dot(max(col, vec3(0.0)), vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(bright) * vec3(0.72, 1.22, 1.4), 0.22);
	vec3 neon = mix(vec3(0.12, 0.8, 1.0), vec3(1.0, 0.15, 0.55),
		0.5 + 0.5 * sin(t * 1.8 + center.x * 7.0 - center.y * 6.0));
	col += neon * length(edge) * 0.4;
	COLOR = vec4(mix(source, clamp(col, vec3(0.0), vec3(1.0)), effect_mix), 1.0);
}
