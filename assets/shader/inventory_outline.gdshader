shader_type spatial;
render_mode unshaded, cull_front, depth_draw_always;

uniform vec4 outline_color : source_color = vec4(1.0, 0.85, 0.0, 1.0);
uniform float outline_size : hint_range(0.0, 0.1) = 0.025;
uniform bool world_space_size = false;

void vertex() {
	if (world_space_size) {
		vec3 view_normal = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
		VERTEX += inverse(mat3(MODELVIEW_MATRIX)) * view_normal * outline_size;
	} else {
		VERTEX += NORMAL * outline_size;
	}
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
