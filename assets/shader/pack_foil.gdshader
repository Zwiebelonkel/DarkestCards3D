shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap;
uniform bool has_albedo_texture = true;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform float metallic_value = 1.0;
uniform float roughness_value = 0.42;
uniform vec3 metric_scale = vec3(1.0);
uniform float source_min_x = -2.0;
uniform float source_width = 2.0;
uniform vec3 cross_center = vec3(0.0);
uniform float band_height = 0.4;
uniform float peel_progress = 0.0;
uniform float peel_lift = 0.0;
uniform float ripple_energy = 0.0;
uniform float ripple_phase = 0.0;

#include "res://assets/shader/pack_surface.gdshaderinc"

varying vec3 source_point;
varying float detached_weight;
varying float reverse_surface;

// Integral of a unit-length tangent: a fold, a straight pulled span, then a
// softer curl at the gripped edge. Both joins preserve position and tangent.
vec3 arc_at(float distance, float width) {
	float free_length = width * peel_progress;
	float bend_length = min(free_length, width * 0.14 + free_length * 0.18);
	float angle = min(0.7 + clamp(peel_lift, 0.0, 1.05) * 2.0, free_length / max(0.001, band_height * 0.68));
	float curve = angle / max(bend_length, 0.0001);
	float theta = min(distance, bend_length) * curve;
	float x = -sin(theta) / max(curve, 0.0001);
	float up = (1.0 - cos(theta)) / max(curve, 0.0001);
	float curl_start = max(bend_length, free_length * 0.78);
	float straight = max(0.0, min(distance, curl_start) - bend_length);
	x -= cos(angle) * straight;
	up += sin(angle) * straight;
	if (distance > curl_start) {
		float curl_angle = 0.2 + clamp(peel_lift, 0.0, 1.0) * 0.32 + ripple_energy * 0.08;
		float curl_curve = curl_angle / max(free_length - curl_start, 0.0001);
		theta = angle + (distance - curl_start) * curl_curve;
		x -= (sin(theta) - sin(angle)) / curl_curve;
		up += (cos(angle) - cos(theta)) / curl_curve;
	} else if (distance > bend_length) {
		theta = angle;
	}
	return vec3(x, up, theta);
}

vec3 rotate_axis(vec3 point, vec3 axis, float angle) {
	return point * cos(angle) + cross(axis, point) * sin(angle) + axis * dot(axis, point) * (1.0 - cos(angle));
}

void vertex() {
	surface_world_scale = length(MODEL_MATRIX[0].xyz) / max(metric_scale.x, 0.0001);
	source_point = VERTEX * metric_scale;
	detached_weight = 0.0;
	reverse_surface = (NORMAL.z < -0.1 || NORMAL.y < -0.5) ? 1.0 : 0.0;
	float width = source_width * metric_scale.x;
	float boundary = (source_min_x + source_width * peel_progress) * metric_scale.x;
	float distance = boundary - source_point.x;
	if (peel_progress > 0.0 && distance > 0.0) {
		vec3 arc = arc_at(distance, width);
		vec3 direction = normalize(vec3(0.0, 0.52 + peel_lift * 0.33, 0.78 - peel_lift * 0.2));
		vec3 axis = cross(vec3(1.0, 0.0, 0.0), direction);
		vec3 offset = vec3(0.0, source_point.y - cross_center.y, source_point.z - cross_center.z);
		vec3 moved = vec3(boundary + arc.x, cross_center.y, cross_center.z) + direction * arc.y + rotate_axis(offset, axis, -arc.z);
		detached_weight = smoothstep(0.0, max(0.0001, min(width * 0.025, width * peel_progress * 0.25)), distance);
		float wave = sin(source_point.x * 57.0 + source_point.y * 34.0 + ripple_phase) * 0.6 + sin(source_point.x * 103.0 - source_point.y * 49.0 - ripple_phase * 0.7) * 0.4;
		moved += axis * wave * width * (0.00022 + ripple_energy * 0.0005) * detached_weight * clamp(peel_progress * 8.0, 0.0, 1.0);
		VERTEX = moved / metric_scale;
		// Normals cross from local to the physical foil frame and back; using
		// an unscaled rotation here makes these nonuniform GLBs shade wrongly.
		vec3 physical_normal = normalize(NORMAL / metric_scale);
		NORMAL = normalize(rotate_axis(physical_normal, axis, -arc.z) * metric_scale);
	}
}

void fragment() {
	vec4 artwork = (has_albedo_texture ? texture(albedo_texture, UV) : vec4(1.0)) * albedo_tint;
	float silver = detached_weight * reverse_surface;
	if (!FRONT_FACING) {
		silver = max(silver, detached_weight);
		NORMAL = -NORMAL;
	}
	float fine_ridges = sin(source_point.x * 185.0 + sin(source_point.y * 76.0) * 1.4) * 0.5 + 0.5;
	vec3 silver_color = mix(vec3(0.45, 0.48, 0.52), vec3(0.76, 0.79, 0.82), fine_ridges * 0.22 + 0.48);
	float height = pack_surface_height(source_point);
	ALBEDO = mix(pack_surface_color(artwork.rgb, height), silver_color, silver);
	NORMAL = pack_surface_normal(NORMAL, VERTEX, height * (1.0 - silver));
	METALLIC = mix(metallic_value, 0.88, silver);
	ROUGHNESS = clamp(mix(roughness_value + (height - 0.5) * surface_roughness_strength, 0.3, silver) + (fine_ridges - 0.5) * 0.065 * detached_weight, 0.26, 0.4);
	SPECULAR = 0.45;
	CLEARCOAT = mix(laminate_clearcoat, 0.12, silver);
	CLEARCOAT_ROUGHNESS = mix(laminate_roughness, 0.45, silver);
}
