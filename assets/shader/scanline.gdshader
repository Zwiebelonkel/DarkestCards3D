shader_type canvas_item;

uniform float line_spacing : hint_range(1.0, 8.0) = 2.0;
uniform float darkness : hint_range(0.0, 1.0) = 0.25;

void fragment() {
	float line = mod(floor(FRAGCOORD.y), line_spacing);
	float factor = line < 1.0 ? (1.0 - darkness) : 1.0;
	COLOR = vec4(vec3(0.0), darkness * (1.0 - factor));
}
