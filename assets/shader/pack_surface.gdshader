shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap;
uniform bool has_albedo_texture = true;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform float metallic_value = 1.0;
uniform float roughness_value = 0.42;
uniform vec3 metric_scale = vec3(1.0);

#include "res://assets/shader/pack_surface.gdshaderinc"

varying vec3 source_point;

void vertex() {
	surface_world_scale = length(MODEL_MATRIX[0].xyz) / max(metric_scale.x, 0.0001);
	source_point = VERTEX * metric_scale;
}

void fragment() {
	vec3 artwork = (has_albedo_texture ? texture(albedo_texture, UV).rgb : vec3(1.0)) * albedo_tint.rgb;
	float height = pack_surface_height(source_point);
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ALBEDO = pack_surface_color(artwork, height);
	NORMAL = pack_surface_normal(NORMAL, VERTEX, height);
	METALLIC = metallic_value;
	ROUGHNESS = clamp(roughness_value + (height - 0.5) * surface_roughness_strength, 0.26, 0.4);
	SPECULAR = 0.45;
	CLEARCOAT = laminate_clearcoat;
	CLEARCOAT_ROUGHNESS = laminate_roughness;
}
