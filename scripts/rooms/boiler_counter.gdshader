shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

uniform sampler2D digit_strip : source_color, filter_linear_mipmap, repeat_disable;
instance uniform float roll_steps = 0.0;

void fragment() {
	float edge = abs(UV.y * 2.0 - 1.0);
	// A curved print surface and shaded aperture lips give each strip drum depth.
	float curve = sqrt(1.0 - edge * edge * 0.28);
	float x = (UV.x - 0.5) / curve + 0.5;
	float row = fract((roll_steps + UV.y) / 10.0);
	float glyph = texture(digit_strip, vec2(clamp(x, 0.0, 1.0), row)).a;
	float shade = 1.0 - pow(edge, 3.0) * 0.88;
	vec3 drum = vec3(0.030, 0.034, 0.029);
	vec3 ink = vec3(0.84, 0.78, 0.59);
	ALBEDO = mix(drum, ink, glyph) * shade;
}
