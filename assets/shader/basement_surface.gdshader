shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.29, 0.23, 0.19, 1.0);
uniform vec4 mortar_color : source_color = vec4(0.12, 0.13, 0.12, 1.0);
uniform bool masonry = false;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.92;
// Only the graveyard's selected floor instances set these. Other surfaces stay unchanged.
instance uniform vec3 grave_opening_origin = vec3(0.0);
instance uniform vec3 grave_opening_right = vec3(1.0, 0.0, 0.0);
instance uniform vec3 grave_opening_forward = vec3(0.0, 0.0, -1.0);
instance uniform vec2 grave_opening_half_size = vec2(0.0);
instance uniform float grave_opening_amount = 0.0;
varying vec3 surface_position;
varying vec3 surface_normal;

float grain(vec3 point) {
	return fract(sin(dot(point, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void vertex() {
	surface_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	surface_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 point = surface_position;
	if (grave_opening_amount > 0.0) {
		vec3 offset = point - grave_opening_origin;
		if (abs(dot(offset, grave_opening_right)) < grave_opening_half_size.x * grave_opening_amount
			&& abs(dot(offset, grave_opening_forward)) < grave_opening_half_size.y) {
			discard;
		}
	}
	float broad_grain = grain(floor(point * 5.0));
	float fine_grain = grain(floor(point * 95.0));
	vec3 color = base_color.rgb * (0.84 + broad_grain * 0.22 + fine_grain * 0.09);
	if (masonry) {
		vec2 wall_uv = abs(surface_normal.x) > abs(surface_normal.z) ? point.zy : point.xy;
		float course = floor(wall_uv.y / 0.25);
		vec2 brick = vec2(wall_uv.x / 0.66 + mod(course, 2.0) * 0.5, wall_uv.y / 0.25);
		vec2 cell = fract(brick);
		float mortar = max(1.0 - smoothstep(0.022, 0.046, cell.x), 1.0 - smoothstep(0.04, 0.085, cell.y));
		color *= 0.82 + grain(vec3(floor(brick), 2.0)) * 0.32;
		color = mix(color, mortar_color.rgb * (0.86 + fine_grain * 0.18), mortar);
	}
	float damp_base = 1.0 - smoothstep(0.0, 0.9, point.y);
	ALBEDO = color * (1.0 - damp_base * 0.16);
	ROUGHNESS = roughness_amount;
	SPECULAR = 0.22;
}
