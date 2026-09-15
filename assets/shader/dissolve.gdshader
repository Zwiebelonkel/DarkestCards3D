shader_type spatial;
render_mode cull_disabled;

// Godot 4 material inputs: each surface keeps its own wood/metal appearance.
uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform sampler2D albedo_texture_nearest : source_color, hint_default_white, filter_nearest;
uniform bool use_nearest_texture = false;
uniform vec2 texture_uv_scale = vec2(1.0);
uniform vec2 texture_uv_offset = vec2(0.0);
uniform bool unshaded_mode = false;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.85;
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.0;
uniform float specular_amount : hint_range(0.0, 1.0) = 0.5;

uniform float dissolve_progress : hint_range(0.0, 1.0) = 0.0;
uniform float dissolve_min_y = 0.0;
uniform float dissolve_height = 1.0;
uniform vec4 border_color : source_color = vec4(0.55, 0.25, 0.07, 1.0);
uniform float border_width : hint_range(0.001, 0.2) = 0.035;
uniform float emission_intensity = 0.8;
uniform float noise_scale = 9.0;
uniform float noise_influence : hint_range(0.0, 0.5) = 0.16;

// Crates retain the default world-space sweep. Cards supply a mesh-to-card
// transform so their shared XY field follows the whole rotating card.
uniform bool use_local_space = false;
uniform mat4 local_space_transform = mat4(1.0);
uniform bool local_space_planar = false;
varying vec3 dissolve_position;

float hash_noise(vec3 point) {
    return fract(sin(dot(point, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float smooth_noise(vec3 point) {
    vec3 cell = floor(point);
    vec3 weight = fract(point);
    weight = weight * weight * (3.0 - 2.0 * weight);
    return mix(
        mix(mix(hash_noise(cell), hash_noise(cell + vec3(1.0, 0.0, 0.0)), weight.x),
            mix(hash_noise(cell + vec3(0.0, 1.0, 0.0)), hash_noise(cell + vec3(1.0, 1.0, 0.0)), weight.x), weight.y),
        mix(mix(hash_noise(cell + vec3(0.0, 0.0, 1.0)), hash_noise(cell + vec3(1.0, 0.0, 1.0)), weight.x),
            mix(hash_noise(cell + vec3(0.0, 1.0, 1.0)), hash_noise(cell + vec3(1.0, 1.0, 1.0)), weight.x), weight.y), weight.z);
}

void vertex() {
    dissolve_position = use_local_space
        ? (local_space_transform * vec4(VERTEX, 1.0)).xyz
        : (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    if (use_local_space && local_space_planar) {
        dissolve_position.z = 0.0;
    }
}

void fragment() {
    vec2 sample_uv = UV * texture_uv_scale + texture_uv_offset;
    vec4 sampled_color = use_nearest_texture
        ? texture(albedo_texture_nearest, sample_uv)
        : texture(albedo_texture, sample_uv);
    vec4 color = base_color * sampled_color;
    float height = clamp((dissolve_position.y - dissolve_min_y) / max(dissolve_height, 0.001), 0.0, 1.0);
    float field = mix(height, smooth_noise(dissolve_position * noise_scale), noise_influence);
    if (color.a < 0.1 || dissolve_progress >= 1.0 || (dissolve_progress > 0.0 && field < dissolve_progress)) {
        discard;
    }
    float border = dissolve_progress > 0.0 ? 1.0 - smoothstep(0.0, border_width, field - dissolve_progress) : 0.0;
    vec3 surface_color = mix(color.rgb, border_color.rgb, border);
    ALBEDO = unshaded_mode ? vec3(0.0) : surface_color;
    ROUGHNESS = roughness_amount;
    METALLIC = unshaded_mode ? 0.0 : metallic_amount;
    SPECULAR = unshaded_mode ? 0.0 : specular_amount;
    EMISSION = (unshaded_mode ? surface_color : vec3(0.0)) + border * border_color.rgb * emission_intensity;
}
