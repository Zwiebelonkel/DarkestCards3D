// Shared by the intact wrapper and the deforming peel. Only the relief UVs
// use physical pack coordinates; the printed artwork always keeps its UVs.
uniform sampler2D surface_heightmap : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 surface_origin = vec3(0.0);
uniform float surface_scale = 0.25;
uniform float surface_relief = 0.001;
uniform float surface_tint_strength = 0.03;
uniform float surface_roughness_strength = 0.04;
uniform float laminate_clearcoat = 0.18;
uniform float laminate_roughness = 0.3;
varying float surface_world_scale;

float pack_surface_height(vec3 physical_point) {
	vec2 point = physical_point.xy + surface_origin.xy;
	float pattern = texture(surface_heightmap, point * surface_scale).r;
	// Fine, mostly vertical compression wrinkles catch the plastic highlight.
	float wrinkles = sin(point.x * 53.0 + sin(point.y * 7.0) * 1.5 + pattern * 3.0);
	return pattern + wrinkles * 0.02;
}

vec3 pack_surface_color(vec3 artwork, float height) {
	return artwork * (1.0 + (height - 0.5) * surface_tint_strength);
}

vec3 pack_surface_normal(vec3 normal, vec3 view_position, float height) {
	// Derivative bump mapping works without imported tangents and follows the
	// curled foil; heightmap mipmaps suppress distant high-frequency detail.
	vec3 dx = dFdx(view_position);
	vec3 dy = dFdy(view_position);
	vec3 across_x = cross(dy, normal);
	vec3 across_y = cross(normal, dx);
	float determinant = dot(dx, across_x);
	vec3 gradient = sign(determinant) * (dFdx(height) * across_x + dFdy(height) * across_y);
	return normalize(abs(determinant) * normal - surface_relief * surface_world_scale * gradient);
}
