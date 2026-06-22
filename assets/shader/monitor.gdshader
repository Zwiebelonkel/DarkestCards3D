shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 background_color : source_color = vec4(0.0, 0.015, 0.006, 1.0);
uniform vec4 line_color : source_color = vec4(0.08, 1.0, 0.22, 1.0);

uniform float emission_strength = 2.8;
uniform float scroll_speed = 1.2;
uniform float line_width = 0.018;

uniform vec2 matrix_resolution = vec2(96.0, 54.0);
uniform float pixel_gap_strength = 0.45;
uniform float grid_strength = 0.16;
uniform float scanline_strength = 0.16;
uniform float flicker_strength = 0.06;

uniform float baseline = 0.50;
uniform float flash_amount = 0.0;
uniform bool flatline = false;


float pulse(float x, float p, float w, float h) {
	return h * exp(-pow((x - p) / w, 2.0));
}


float ecg_wave(float x) {
	float y = baseline;
	
	y += pulse(x, 0.16, 0.035, 0.055);
	y -= pulse(x, 0.34, 0.012, 0.12);
	y += pulse(x, 0.38, 0.007, 0.42);
	y -= pulse(x, 0.42, 0.014, 0.18);
	y += pulse(x, 0.62, 0.060, 0.11);
	
	return clamp(y, 0.08, 0.92);
}


void fragment() {
	vec2 uv = vec2(1.0 - UV.y, UV.x);
	
	// Pixel-Matrix
	vec2 cell = floor(uv * matrix_resolution);
	vec2 pixel_uv = (cell + 0.5) / matrix_resolution;
	vec2 in_cell = fract(uv * matrix_resolution) - 0.5;
	
	float dot_mask = 1.0 - smoothstep(0.22, 0.48, length(in_cell));
	float pixel_mask = mix(1.0 - pixel_gap_strength, 1.0, dot_mask);
	
	// ECG-Welle
	float phase = fract(pixel_uv.x + TIME * scroll_speed);
	float wave_y = flatline ? baseline : ecg_wave(phase);
	
	float dist_to_line = abs(pixel_uv.y - wave_y);
	float line = 1.0 - smoothstep(line_width, line_width * 2.4, dist_to_line);
	line *= dot_mask;
	
	// leichtes Raster
	float gx = min(fract(uv.x * 12.0), 1.0 - fract(uv.x * 12.0));
	float gy = min(fract(uv.y * 6.0), 1.0 - fract(uv.y * 6.0));
	float grid = 1.0 - smoothstep(0.0, 0.018, min(gx, gy));
	
	// Scanlines
	float scanline = 1.0 - scanline_strength * step(0.5, fract(uv.y * matrix_resolution.y * 0.5));
	
	// dezentes Flackern
	float flicker = 1.0 + sin(TIME * 38.0) * flicker_strength;
	
	vec3 color = background_color.rgb;
	
	color += line_color.rgb * grid * grid_strength;
	color += line_color.rgb * line * (1.35 + flash_amount * 1.4);
	
	color *= pixel_mask;
	color *= scanline;
	color *= flicker;
	
	ALBEDO = color;
	EMISSION = color * emission_strength;
}