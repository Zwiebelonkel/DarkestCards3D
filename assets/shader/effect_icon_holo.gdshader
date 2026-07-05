shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled;

uniform sampler2D icon_texture : source_color;
uniform vec4 rarity_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

uniform float holo_strength = 0.65;
uniform float holo_speed = 1.8;
uniform float holo_width = 0.12;
uniform float alpha_cutoff = 0.08;

void fragment() {
	vec4 tex = texture(icon_texture, UV);

	if (tex.a < alpha_cutoff) {
		discard;
	}

	float diagonal = UV.x + UV.y;
	float wave = abs(fract(diagonal + TIME * holo_speed) - 0.5) * 2.0;
	float shine = smoothstep(holo_width, 0.0, wave);

	vec3 base_col = mix(vec3(1.0), rarity_color.rgb, 0.65);
	vec3 holo_col = mix(base_col, vec3(1.0), shine * holo_strength);

	ALBEDO = holo_col;
	EMISSION = holo_col * (0.8 + shine * 1.8);
	ALPHA = tex.a;
}