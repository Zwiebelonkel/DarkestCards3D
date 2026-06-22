shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D screen_texture : source_color;

uniform float emission_energy = 1.25;

uniform bool enable_pixelate = true;
uniform float pixel_size = 2.0;

uniform bool enable_scanlines = true;
uniform float scanline_strength = 0.16;
uniform float scanline_count = 180.0;

uniform bool enable_vhs_wobble = true;
uniform float wobble_strength = 0.004;
uniform float wobble_speed = 2.0;

uniform bool enable_tracking_noise = true;
uniform float tracking_strength = 0.012;
uniform float tracking_speed = 5.0;

uniform bool enable_chromatic_aberration = true;
uniform float chromatic_strength = 0.0025;

uniform bool enable_grain = true;
uniform float grain_strength = 0.08;

uniform float contrast = 1.12;
uniform float saturation = 0.82;
uniform float brightness = 0.96;

uniform vec3 tint_color = vec3(0.86, 0.9, 1.0);
uniform float tint_strength = 0.08;


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


vec3 apply_saturation(vec3 color, float sat) {
	float gray = dot(color, vec3(0.299, 0.587, 0.114));
	return mix(vec3(gray), color, sat);
}


void fragment() {
	vec2 uv = UV;

	if (enable_pixelate) {
		vec2 virtual_resolution = VIEWPORT_SIZE / max(pixel_size, 1.0);
		uv = floor(uv * virtual_resolution) / virtual_resolution;
	}

	if (enable_vhs_wobble) {
		float line_noise = sin((uv.y * 58.0) + (TIME * wobble_speed * 4.0));
		float slow_wave = sin((uv.y * 9.0) + (TIME * wobble_speed));
		uv.x += (line_noise * 0.35 + slow_wave * 0.65) * wobble_strength;
	}

	if (enable_tracking_noise) {
		float tracking_line = step(0.985, hash21(vec2(floor(uv.y * 90.0), floor(TIME * tracking_speed))));
		uv.x += tracking_line * tracking_strength * sin(TIME * 20.0);
	}

	vec3 col;

	if (enable_chromatic_aberration) {
		float edge = abs(uv.x - 0.5) * 2.0;
		float amount = chromatic_strength * (0.5 + edge);

		float r = texture(screen_texture, uv + vec2(amount, 0.0)).r;
		float g = texture(screen_texture, uv).g;
		float b = texture(screen_texture, uv - vec2(amount, 0.0)).b;
		col = vec3(r, g, b);
	} else {
		col = texture(screen_texture, uv).rgb;
	}

	if (enable_scanlines) {
		float scan = sin(uv.y * scanline_count * 3.14159);
		float scan_dark = 1.0 - (scanline_strength * (0.5 + 0.5 * scan));
		col *= scan_dark;
	}

	if (enable_grain) {
		float grain = hash21(UV * VIEWPORT_SIZE + vec2(TIME * 90.0, TIME * 37.0));
		col += (grain - 0.5) * grain_strength;
	}

	col = (col - 0.5) * contrast + 0.5;
	col = apply_saturation(col, saturation);
	col = mix(col, col * tint_color, tint_strength);
	col *= brightness;
	col = clamp(col, vec3(0.0), vec3(1.0));

	ALBEDO = col;
	EMISSION = col * emission_energy;
	ROUGHNESS = 0.7;
}
