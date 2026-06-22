shader_type canvas_item;
render_mode blend_add;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

uniform float blur : hint_range(0.0, 8.0) = 4.0;
uniform float threshold : hint_range(0.0, 5.0) = 1.8;
uniform float threshold_smoothness : hint_range(0.01, 1.0) = 0.25;

uniform int flare_count : hint_range(1, 8) = 3;
uniform float flare_spacing : hint_range(-3.0, 3.0) = 1.0;
uniform float flare_distance : hint_range(0.0, 1.0) = 0.45;

uniform float intensity : hint_range(0.0, 5.0) = 0.35;
uniform float visibility : hint_range(0.0, 1.0) = 0.35;
uniform float saturation : hint_range(0.0, 8.0) = 1.5;

uniform float max_brightness : hint_range(0.0, 2.0) = 0.75;


vec3 apply_threshold(vec3 color) {
	float brightness = max(color.r, max(color.g, color.b));
	
	float mask = smoothstep(
		threshold - threshold_smoothness,
		threshold + threshold_smoothness,
		brightness
	);
	
	return color * mask;
}


vec3 adjust_saturation(vec3 color, float sat) {
	float gray = dot(color, vec3(0.299, 0.587, 0.114));
	return mix(vec3(gray), color, sat);
}


void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 center = vec2(0.5, 0.5);
	
	vec2 flare_vector = (center - uv) * flare_spacing;
	vec3 final_flare = vec3(0.0);
	
	for (int i = 0; i < 8; i++) {
		if (i >= flare_count) {
			break;
		}
		
		vec2 sample_uv = uv + flare_vector * float(i) * flare_distance;
		
		if (
			sample_uv.x < 0.0 || sample_uv.x > 1.0 ||
			sample_uv.y < 0.0 || sample_uv.y > 1.0
		) {
			continue;
		}
		
		float dist = distance(sample_uv, center);
		float weight = 1.0 - smoothstep(0.0, 0.75, dist);
		
		vec3 col = textureLod(screen_tex, sample_uv, blur).rgb;
		col = apply_threshold(col);
		
		final_flare += col * weight;
	}
	
	final_flare *= intensity;
	final_flare = adjust_saturation(final_flare, saturation);
	final_flare = clamp(final_flare, vec3(0.0), vec3(max_brightness));
	
	COLOR = vec4(final_flare * visibility, 1.0);
}