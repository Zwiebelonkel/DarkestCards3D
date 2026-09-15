shader_type spatial;
render_mode cull_disabled;

uniform sampler2D atlas : source_color, filter_nearest, repeat_enable;
uniform vec4 text_masks[8];
uniform float roughness_value = 0.8;

void fragment() {
	vec4 color = texture(atlas, UV);
	for (int index = 0; index < 8; index++) {
		vec4 rect = text_masks[index];
		if (UV.x >= rect.x && UV.y >= rect.y && UV.x <= rect.z && UV.y <= rect.w) {
			// Retain the atlas everywhere except the obsolete English printing.
			color.rgb = vec3(0.025, 0.009, 0.011);
		}
	}
	ALBEDO = color.rgb;
	ROUGHNESS = roughness_value;
}
