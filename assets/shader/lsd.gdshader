shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

uniform float intensity : hint_range(0.0, 2.0) = 0.75;
uniform float speed : hint_range(0.0, 10.0) = 2.5;
uniform float distortion_strength : hint_range(0.0, 0.1) = 0.025;
uniform float color_shift : hint_range(0.0, 0.05) = 0.012;
uniform float wave_zoom : hint_range(1.0, 40.0) = 14.0;
uniform float swirl_strength : hint_range(0.0, 10.0) = 2.5;
uniform float saturation_boost : hint_range(0.0, 4.0) = 1.8;
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.35;

vec3 rgb_to_hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

	float d = q.x - min(q.w, q.y);
	float e = 0.00001;

	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);

	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

float circle_wave(vec2 uv, float t) {
	vec2 center = uv - vec2(0.5);
	float dist = length(center);
	return sin(dist * wave_zoom * 8.0 - t * 4.0);
}

void fragment() {
	float t = TIME * speed;

	vec2 uv = SCREEN_UV;
	vec2 centered = uv - vec2(0.5);

	// Swirl / Dreh-Verzerrung
	float dist = length(centered);
	float angle = atan(centered.y, centered.x);
	angle += sin(dist * 8.0 - t) * 0.08 * swirl_strength * intensity;

	vec2 swirled = vec2(cos(angle), sin(angle)) * dist + vec2(0.5);

	// Wellen-Verzerrung
	float wave_x = sin((uv.y * wave_zoom) + t) * distortion_strength;
	float wave_y = cos((uv.x * wave_zoom) - t * 1.2) * distortion_strength;

	vec2 distorted_uv = swirled + vec2(wave_x, wave_y) * intensity;

	// Kreisförmige pulsierende Verzerrung
	float pulse = circle_wave(uv, t);
	distorted_uv += normalize(centered + 0.0001) * pulse * distortion_strength * 0.4 * intensity;

	// RGB Split / Chromatic Aberration
	vec2 red_uv = distorted_uv + vec2(color_shift, 0.0) * intensity;
	vec2 green_uv = distorted_uv;
	vec2 blue_uv = distorted_uv - vec2(color_shift, 0.0) * intensity;

	float r = texture(screen_texture, red_uv).r;
	float g = texture(screen_texture, green_uv).g;
	float b = texture(screen_texture, blue_uv).b;

	vec3 col = vec3(r, g, b);

	// Farbrotation
	vec3 hsv = rgb_to_hsv(col);
	hsv.x = fract(hsv.x + sin(t * 0.35 + dist * 8.0) * 0.18 * intensity);
	hsv.y = clamp(hsv.y * saturation_boost, 0.0, 1.0);
	col = hsv_to_rgb(hsv);

	// Neon-Rainbow-Overlay
	vec3 rainbow = vec3(
		0.5 + 0.5 * sin(t + uv.x * 8.0),
		0.5 + 0.5 * sin(t + uv.y * 8.0 + 2.0),
		0.5 + 0.5 * sin(t + uv.x * 6.0 + uv.y * 6.0 + 4.0)
	);

	col = mix(col, col * rainbow * 1.6, 0.35 * intensity);

	// Leichte Scanline / Flimmern
	float scanline = sin(uv.y * 900.0 + t * 20.0) * 0.025;
	col += scanline * intensity;

	// Vignette
	float vignette = smoothstep(0.85, 0.25, dist);
	col *= mix(1.0, vignette, vignette_strength);

	COLOR = vec4(col, 1.0);
}