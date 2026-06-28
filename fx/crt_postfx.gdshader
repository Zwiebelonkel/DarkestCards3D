shader_type canvas_item;
render_mode unshaded;

// CRT / VHS / Glitch Post-FX for Godot 4.4
// ColorRect-Version ohne UV / SCREEN_UV / FRAGCOORD / SCREEN_PIXEL_SIZE im Fragment.
// Das Script setzt viewport_size automatisch.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec2 viewport_size = vec2(600.0, 338.0);

uniform float effect_enabled = 1.0;

// CRT Curve
uniform float crt_curvature = 3.5;

// Scanlines
uniform float scanline_intensity = 0.55;
uniform float scanline_count = 240.0;
uniform float scanline_scroll_speed = 0.12;

// Chroma
uniform float chroma_aberration = 0.004;

// Glitch
uniform float glitch_intensity = 0.25;
uniform float glitch_speed = 6.0;
uniform float glitch_block_size = 18.0;

// Atmosphere
uniform float noise_intensity = 0.07;
uniform float flicker_intensity = 0.04;
uniform float phosphor_glow = 0.35;
uniform float vignette_strength = 1.1;
uniform vec4 tint_color : source_color = vec4(0.949, 1.0, 0.855, 1.0);


varying vec2 postfx_uv;

void vertex() {
	vec2 safe_size = max(viewport_size, vec2(1.0, 1.0));
	postfx_uv = VERTEX / safe_size;
}

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 get_pixel_size() {
	return 1.0 / max(viewport_size, vec2(1.0, 1.0));
}

vec2 curve_uv(vec2 uv) {
	vec2 centered = uv * 2.0 - 1.0;
	float curve_amount = crt_curvature * 0.015;
	centered += centered * dot(centered, centered) * curve_amount;
	return centered * 0.5 + 0.5;
}

float outside_screen(vec2 uv) {
	float left = step(uv.x, 0.0);
	float right = step(1.0, uv.x);
	float top = step(uv.y, 0.0);
	float bottom = step(1.0, uv.y);
	return clamp(left + right + top + bottom, 0.0, 1.0);
}

vec2 apply_glitch(vec2 uv) {
	float time_block = floor(TIME * glitch_speed);
	float block_line = floor(uv.y * glitch_block_size);
	float block_random = hash11(block_line + time_block * 17.0);

	float block_mask = step(1.0 - glitch_intensity * 0.35, block_random);
	float block_shift = (hash11(block_line * 9.17 + time_block) - 0.5) * 0.10 * glitch_intensity * block_mask;

	float tear_line = floor(uv.y * 80.0);
	float tear_random = hash11(tear_line + time_block * 31.0);
	float tear_mask = step(0.985 - glitch_intensity * 0.02, tear_random);
	float tear_shift = (hash11(tear_line * 4.7 + time_block * 2.0) - 0.5) * 0.18 * glitch_intensity * tear_mask;

	uv.x += block_shift + tear_shift;
	return uv;
}

vec3 sample_screen_rgb_split(vec2 uv) {
	vec2 red_uv = uv + vec2(chroma_aberration, 0.0);
	vec2 green_uv = uv;
	vec2 blue_uv = uv - vec2(chroma_aberration, 0.0);

	float r = texture(screen_texture, red_uv).r;
	float g = texture(screen_texture, green_uv).g;
	float b = texture(screen_texture, blue_uv).b;

	return vec3(r, g, b);
}

vec3 apply_phosphor_glow(vec3 color, vec2 uv) {
	vec2 pixel_size = get_pixel_size();
	float px = pixel_size.x;
	float py = pixel_size.y;

	vec3 blur = vec3(0.0);
	blur += texture(screen_texture, uv + vec2( px * 2.0, 0.0)).rgb;
	blur += texture(screen_texture, uv + vec2(-px * 2.0, 0.0)).rgb;
	blur += texture(screen_texture, uv + vec2(0.0,  py * 2.0)).rgb;
	blur += texture(screen_texture, uv + vec2(0.0, -py * 2.0)).rgb;
	blur *= 0.25;

	float highlight = smoothstep(0.45, 1.0, dot(color, vec3(0.299, 0.587, 0.114)));
	return color + blur * phosphor_glow * 0.45 * highlight;
}

vec3 apply_scanlines(vec3 color, vec2 uv) {
	float scroll = TIME * scanline_scroll_speed;

	float thick_line = sin((uv.y + scroll) * scanline_count * PI * 2.0);
	float thick_darkening = (0.5 + 0.5 * thick_line) * scanline_intensity * 0.35;

	float fine_line = sin((uv.y + scroll * 0.35) * scanline_count * PI * 6.0);
	float fine_darkening = (0.5 + 0.5 * fine_line) * scanline_intensity * 0.08;

	float phosphor_dot = sin(uv.x * scanline_count * PI * 2.0);
	float dot_darkening = (0.5 + 0.5 * phosphor_dot) * scanline_intensity * 0.06;

	color *= 1.0 - thick_darkening - fine_darkening - dot_darkening;
	return color;
}

vec3 apply_noise_and_flicker(vec3 color, vec2 uv) {
	vec2 pixel_coord = uv * viewport_size;
	float grain = hash21(pixel_coord + vec2(TIME * 95.17, TIME * 41.73));
	color += (grain - 0.5) * noise_intensity;

	float frame = floor(TIME * 24.0);
	float flicker = (hash11(frame) - 0.5) * flicker_intensity * 2.0;
	color *= 1.0 + flicker;

	return color;
}

vec3 apply_vignette_and_grade(vec3 color, vec2 uv) {
	float dist = distance(uv, vec2(0.5, 0.5));
	float vignette = 1.0 - smoothstep(0.28, 0.86, dist) * vignette_strength;
	color *= clamp(vignette, 0.0, 1.0);

	float gray = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(color, vec3(gray), 0.12);
	color *= mix(vec3(1.0, 1.0, 1.0), tint_color.rgb, 0.18);

	return color;
}

void fragment() {
	vec2 base_uv = clamp(postfx_uv, vec2(0.0, 0.0), vec2(1.0, 1.0));

if (effect_enabled < 0.5) {
	COLOR = texture(screen_texture, base_uv);
} else {
	vec2 uv = curve_uv(base_uv);
	float border = outside_screen(uv);

	uv = apply_glitch(uv);

	vec3 color = sample_screen_rgb_split(uv);
	color = apply_phosphor_glow(color, uv);
	color = apply_scanlines(color, base_uv);
	color = apply_noise_and_flicker(color, base_uv);
	color = apply_vignette_and_grade(color, base_uv);

	color = mix(color, vec3(0.0, 0.0, 0.0), border);
	COLOR = vec4(clamp(color, 0.0, 1.0), 1.0);
}

	vec2 uv = curve_uv(base_uv);
	float border = outside_screen(uv);

	uv = apply_glitch(uv);

	vec3 color = sample_screen_rgb_split(uv);
	color = apply_phosphor_glow(color, uv);
	color = apply_scanlines(color, base_uv);
	color = apply_noise_and_flicker(color, base_uv);
	color = apply_vignette_and_grade(color, base_uv);

	color = mix(color, vec3(0.0, 0.0, 0.0), border);
	COLOR = vec4(clamp(color, 0.0, 1.0), 1.0);
}
