// The following shader is used in order to simulate a simple ocean using Gerstner waves.
// This shader can be added in a plane mesh. For a more detailed ocean, increase the width and depth subdivision.
// Note 1: On larger planes ex. 500x500, increasing the subdivision above 1000 comes at great performance cost
// Note 2: Special thanks to @ninetailsrabbit for fixing a caustics projection issue!

shader_type spatial;

// Set render modes: always draw depth and disable backface culling
render_mode depth_draw_always, cull_disabled;

// Uniforms for screen and depth textures
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;

// ─── NEW: Master wave controls ─────────────────────────────────────────────
group_uniforms Wave_Master;
/// Scales the amplitude (height) of ALL waves. 1.0 = default, 0.0 = flat.
uniform float wave_height : hint_range(0.0, 5.0) = 1.0;
/// Scales the speed of ALL waves. 1.0 = default, 0.0 = frozen.
uniform float wave_speed  : hint_range(0.0, 5.0) = 1.0;
group_uniforms;

// ─── Refraction ────────────────────────────────────────────────────────────
group_uniforms Refraction;
/// How strongly the surface normal distorts the underwater view (0=none, 0.05–0.15 natural).
uniform float refraction_strength   : hint_range(0.0, 0.5) = 0.08;
/// Fades refraction in shallow water to prevent shore/background bleed.
uniform float refraction_depth_scale : hint_range(0.0, 2.0) = 0.5;
group_uniforms;

// Group uniforms for wave parameters
group_uniforms Waves;
// Each wave is defined by a vec4: direction (x,y), amplitude, frequency
uniform vec4 wave_1 = vec4(0.3, 4.0, 0.2, 0.6);
uniform vec4 wave_2 = vec4(-0.26, -0.19, 0.01, 0.47);
uniform vec4 wave_3 = vec4(-7.67, 5.63, 0.1, 0.38);
uniform vec4 wave_4 = vec4(-0.42, -1.63, 0.1, 0.28);
uniform vec4 wave_5 = vec4(1.66, 0.07, 0.15, 1.81);
uniform vec4 wave_6 = vec4(1.20, 1.14, 0.01, 0.33);
uniform vec4 wave_7 = vec4(-1.6, 7.3, 0.11, 0.73);
uniform vec4 wave_8 = vec4(-0.42, -1.63, 0.15, 1.52);

// Uniforms for time factor, noise zoom, and noise amplitude
uniform float time_factor = 2.5;
uniform float noise_zoom = 2.0;
uniform float noise_amp = 1.0;

// Group uniforms for water colors
group_uniforms Water_colours;
uniform vec3 base_water_color:source_color;
uniform vec3 fresnel_water_color:source_color;
uniform vec4 deep_water_color : source_color;
uniform vec4 shallow_water_color : source_color;

// Group uniforms for depth-related parameters
group_uniforms Depth;
uniform float beers_law = 0.5;
uniform float depth_offset = -1.2;
uniform float near = 7.0;
uniform float far = 10000.0;

// Group uniforms for edge detection and foam effects
group_uniforms Edge_Detection;
uniform float edge_texture_scale = 3.5;
uniform float edge_texture_offset = 1.0;
uniform float edge_texture_speed = 0.1;
uniform float edge_foam_intensity = 2.0;
uniform float edge_fade_start = -3.0;
uniform float edge_fade_end = 6.6;
uniform sampler2D edge_foam_texture;

// Group uniforms for wave peak effects
group_uniforms WavePeakEffect;
uniform float peak_height_threshold = 1.0;
uniform vec3 peak_color = vec3(1.0, 1.0, 1.0);
uniform float peak_intensity = 1.0;
uniform sampler2D foam_texture;
uniform float foam_intensity = 1.0;
uniform float foam_scale = 1.0;

// Group uniforms for surface details
group_uniforms Surface_details;
uniform float metallic = 0.6;
uniform float roughness = 0.045;
uniform float uv_scale_text_a = 0.1;
uniform vec2 uv_speed_text_a = vec2(0.42, 0.3);
uniform float uv_scale_text_b = 0.6;
uniform vec2 uv_speed_text_b = vec2(0.15, 0.1);
uniform float normal_strength = 1.0;
uniform float uv_sampler_scale = 0.3;
uniform float blend_factor = 0.28;
uniform float perturbation_strength = 1.0;
uniform float perturbation_time = 0.3;
uniform sampler2D normalmap_a;
uniform sampler2D normalmap_b;
uniform sampler2D uv_sampler;
uniform sampler2DArray caustic_sampler : hint_default_black;
uniform float caustics_intensity = 15.0;

uniform float num_caustic_layers = 16.0;
uniform float caustic_distortion_strength = 0.001;

// Fresnel function
float fresnel(float amount, vec3 normal, vec3 view) {
    return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0)), amount);
}

// Edge depth
float edge(float depth) {
    depth = 2.0 * depth - 1.0;
    return near * far / (far - depth * (near - far));
}

// Dynamic amplitude
float dynamic_amplitude(vec2 pos, float time) {
    return 1.0 + 0.5 * sin(time + length(pos) * 0.1);
}

// Hash & noise
float hash(vec2 p) {
    return fract(sin(dot(p * 17.17, vec2(14.91, 67.31))) * 4791.9511);
}

float noise(vec2 x) {
    vec2 p = floor(x);
    vec2 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    vec2 a = vec2(1.0, 0.0);
    return mix(mix(hash(p + a.yy), hash(p + a.xy), f.x),
               mix(hash(p + a.yx), hash(p + a.xx), f.x), f.y);
}

float fbm(vec2 x) {
    float height = 0.0;
    float amplitude = 0.5;
    float frequency = 3.0;
    for (int i = 0; i < 6; i++) {
        height += noise(x * frequency) * amplitude;
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    return height;
}

// Wave result struct
struct WaveResult {
    vec3 displacement;
    vec3 tangent;
    vec3 binormal;
    vec3 normal;
};

// Gerstner wave — now accepts wave_height_scale to multiply amplitude
WaveResult gerstner_wave(vec4 params, vec2 pos, float time, float height_scale) {
    // Scale the steepness (amplitude) by wave_height
    float steepness = params.z * dynamic_amplitude(pos, time) * height_scale;
    float wavelength = params.w;
    float k = 2.0 * PI / wavelength;
    float c = sqrt(9.81 / k);
    vec2 d = normalize(params.xy);
    float f = k * (dot(d, pos.xy) - c * time);
    float a = steepness / k;

    vec3 displacement = vec3(d.x * (a * cos(f)), a * sin(f), d.y * (a * cos(f)));
    vec3 tangent  = vec3(1.0 - d.x * d.x * steepness * sin(f),  steepness * cos(f), -d.x * d.y * steepness * sin(f));
    vec3 binormal = vec3(-d.x * d.y * steepness * sin(f), steepness * cos(f), 1.0 - d.y * d.y * steepness * sin(f));
    vec3 normal   = normalize(cross(tangent, binormal));

    return WaveResult(displacement, tangent, binormal, normal);
}

// Combine all waves — passes both time (speed) and height_scale
WaveResult wave(vec2 pos, float time, float height_scale) {
    WaveResult waveResult;
    waveResult.displacement = vec3(0.0);
    waveResult.tangent  = vec3(1.0, 0.0, 0.0);
    waveResult.binormal = vec3(0.0, 0.0, 1.0);
    waveResult.normal   = vec3(0.0, 1.0, 0.0);

    WaveResult wr;

    wr = gerstner_wave(wave_1, pos, time, height_scale);
    waveResult.displacement += wr.displacement;
    waveResult.tangent  += wr.tangent;
    waveResult.binormal += wr.binormal;
    waveResult.normal   += wr.normal;

    wr = gerstner_wave(wave_2, pos, time, height_scale);
    waveResult.displacement += wr.displacement;
    waveResult.tangent  += wr.tangent;
    waveResult.binormal += wr.binormal;
    waveResult.normal   += wr.normal;

    wr = gerstner_wave(wave_3, pos, time, height_scale);
    waveResult.displacement += wr.displacement;
    waveResult.tangent  += wr.tangent;
    waveResult.binormal += wr.binormal;
    waveResult.normal   += wr.normal;

    wr = gerstner_wave(wave_4, pos, time, height_scale);
    waveResult.displacement += wr.displacement;
    waveResult.tangent  += wr.tangent;
    waveResult.binormal += wr.binormal;
    waveResult.normal   += wr.normal;

    wr = gerstner_wave(wave_5, pos, time, height_scale);
    waveResult.displacement += wr.displacement;
    waveResult.tangent  += wr.tangent;
    waveResult.binormal += wr.binormal;
    waveResult.normal   += wr.normal;

    wr = gerstner_wave(wave_6, pos, time, height_scale);
    waveResult.displacement += wr.displacement;
    waveResult.tangent  += wr.tangent;
    waveResult.binormal += wr.binormal;
    waveResult.normal   += wr.normal;

    wr = gerstner_wave(wave_7, pos, time, height_scale);
    waveResult.displacement += wr.displacement;
    waveResult.tangent  += wr.tangent;
    waveResult.binormal += wr.binormal;
    waveResult.normal   += wr.normal;

    wr = gerstner_wave(wave_8, pos, time, height_scale);
    waveResult.displacement += wr.displacement;
    waveResult.tangent  += wr.tangent;
    waveResult.binormal += wr.binormal;
    waveResult.normal   += wr.normal;

    // FBM noise displacement — also scaled by wave_height
    waveResult.displacement.y += fbm(pos.xy * (noise_zoom / 50.0)) * noise_amp * height_scale;

    return waveResult;
}

// Varyings
varying float height;
varying vec3 world_position;
varying mat3 tbn_matrix;
varying mat4 inv_mvp;

// ── VERTEX ────────────────────────────────────────────────────────────────
void vertex() {
    // wave_speed scales TIME → faster/slower waves
    // wave_height is passed as amplitude multiplier
    float time = (TIME * wave_speed) / time_factor;

    WaveResult waveResult = wave(VERTEX.xz, time, wave_height);

    VERTEX += waveResult.displacement;
    height  = waveResult.displacement.y;

    vec3 n = normalize((MODELVIEW_MATRIX * vec4(waveResult.normal, 0.0)).xyz);
    vec3 t = normalize((MODELVIEW_MATRIX * vec4(waveResult.tangent.xyz, 0.0)).xyz);
    vec3 b = normalize((MODELVIEW_MATRIX * vec4((cross(waveResult.normal, waveResult.tangent.xyz)), 0.0)).xyz);

    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    tbn_matrix     = mat3(t, b, n);
    inv_mvp        = inverse(PROJECTION_MATRIX * MODELVIEW_MATRIX);
}

// ── Helpers (fragment) ────────────────────────────────────────────────────

float random(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float smooth_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(random(i + vec2(0.0, 0.0)), random(i + vec2(1.0, 0.0)), u.x),
        mix(random(i + vec2(0.0, 1.0)), random(i + vec2(1.0, 1.0)), u.x),
        u.y
    );
}

float layered_noise(vec2 p, float scale) {
    float n = 0.0;
    n += smooth_noise(p * scale)       * 0.500;
    n += smooth_noise(p * scale * 2.0) * 0.250;
    n += smooth_noise(p * scale * 4.0) * 0.125;
    return n;
}

vec2 perturb_uv(vec2 uv, vec2 world_pos, float time, float strength) {
    vec2 noise_offset = vec2(
        layered_noise(world_pos * 0.3 + time * 0.06, 1.0),
        layered_noise(world_pos * 0.3 + time * 0.06 + vec2(10.0), 1.0)
    );
    return uv + noise_offset * strength;
}

// ── FRAGMENT ──────────────────────────────────────────────────────────────
void fragment() {
    // Use the same speed-scaled time so UV animation matches wave motion
    float time_scaled = TIME * wave_speed;

    vec2 uv = world_position.xz;

    vec2 uv_offset = texture(uv_sampler, uv * uv_sampler_scale).rg;

    vec2 base_uv_a = (uv + uv_speed_text_a * time_scaled + uv_offset) * uv_scale_text_a;
    vec2 base_uv_b = (uv + uv_speed_text_b * time_scaled + uv_offset) * uv_scale_text_b;

    vec2 animated_uv_a = perturb_uv(base_uv_a, world_position.xz, time_scaled, perturbation_strength);
    vec2 animated_uv_b = perturb_uv(base_uv_b, world_position.xz, time_scaled, perturbation_time);

    vec3 normal_sample_a = texture(normalmap_a, animated_uv_a).rgb;
    vec3 normal_sample_b = texture(normalmap_b, animated_uv_b).rgb;

    normal_sample_a = normalize(normal_sample_a * 2.0 - 1.0);
    normal_sample_b = normalize(normal_sample_b * 2.0 - 1.0);
    vec3 combined_normal   = normalize(mix(normal_sample_a, normal_sample_b, blend_factor));
    vec3 perturbed_normal  = normalize(tbn_matrix * (combined_normal * normal_strength));

    float depth_raw   = texture(DEPTH_TEXTURE, SCREEN_UV).r;
    float depth       = PROJECTION_MATRIX[3][2] / (depth_raw + PROJECTION_MATRIX[2][2]);

    float camera_depth = INV_VIEW_MATRIX[3].y - world_position.y;
    if (camera_depth < 0.0) {
        float depth_factor = smoothstep(-10.0, 0.0, camera_depth);
        ALPHA -= depth_factor * 0.3;
    }

    float depth_blend       = exp((depth + VERTEX.z + depth_offset) * -beers_law);
    depth_blend             = clamp(1.0 - depth_blend, 0.0, 1.0);
    float depth_blend_power = clamp(pow(depth_blend, 2.5), 0.0, 1.0);

    // ── Refraction ────────────────────────────────────────────────────────
    // The perturbed_normal is already in view space via the TBN matrix.
    // Its XY components directly map to screen-space distortion direction.
    // We scale by depth so refraction fades at the shoreline (avoids sky bleed).
    float refr_depth_mask = clamp(depth_blend * refraction_depth_scale, 0.0, 1.0);
    vec2  refr_offset     = perturbed_normal.xy * refraction_strength * refr_depth_mask;
    vec2  refr_uv         = SCREEN_UV + refr_offset;

    // Safety guard: if the refracted UV samples geometry that is in FRONT of
    // (above) the water surface, fall back to the unperturbed UV to avoid
    // pulling sky or air pixels through the water plane.
    float refr_depth_raw  = texture(DEPTH_TEXTURE, refr_uv).r;
    float refr_depth_lin  = PROJECTION_MATRIX[3][2] / (refr_depth_raw + PROJECTION_MATRIX[2][2]);
    float refr_depth_diff = exp((refr_depth_lin + VERTEX.z + depth_offset) * -beers_law);
    refr_uv = (refr_depth_diff > 0.98) ? SCREEN_UV : refr_uv;

    vec3 screen_color = textureLod(SCREEN_TEXTURE, refr_uv, depth_blend_power * 2.5).rgb;
    vec3 depth_color  = mix(shallow_water_color.rgb, deep_water_color.rgb, depth_blend_power);
    vec3 color        = mix(screen_color * depth_color, depth_color * 0.25, depth_blend_power * 0.5);

    float z_depth = edge(texture(DEPTH_TEXTURE, SCREEN_UV).x);
    float z_pos   = edge(FRAGCOORD.z);
    float z_dif   = z_depth - z_pos;

    // Caustics
    vec4 caustic_screenPos = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
    vec4 caustic_localPos  = inv_mvp * caustic_screenPos;
    caustic_localPos       = vec4(caustic_localPos.xyz / caustic_localPos.w, caustic_localPos.w);

    vec2 caustic_Uv = caustic_localPos.xz / vec2(1024.0) + 0.5;
    caustic_Uv += perturbed_normal.xz * caustic_distortion_strength;

    float caustic_layer_index = floor(mod(time_scaled * 26.0, num_caustic_layers));
    vec4  caustic_color       = texture(caustic_sampler, vec3(caustic_Uv * 660.0, caustic_layer_index));
    float caustic_intensity_multiplier = (1.0 - depth_blend_power) * caustics_intensity;

    color *= 1.0 + pow(caustic_color.r, 1.50) * caustic_intensity_multiplier;

    // Fresnel
    float fresnel_val  = fresnel(5.0, NORMAL, VIEW);
    vec3 surface_color = mix(base_water_color, fresnel_water_color, fresnel_val);

    // Edge foam
    vec2 edge_uv      = world_position.xz * edge_texture_scale + edge_texture_offset + time_scaled * edge_texture_speed;
    float edge_fade   = smoothstep(edge_fade_start, edge_fade_end, z_dif);
    vec3 depth_color_adj = mix(texture(edge_foam_texture, edge_uv).rgb * edge_foam_intensity, color, edge_fade);

    // Peak / crest foam — peak_height_threshold also implicitly scales with wave_height
    float peak_factor  = smoothstep(peak_height_threshold, peak_height_threshold + 0.2, height);
    float noise_factor = fbm(world_position.xz * 0.1 + time_scaled * 0.1);
    peak_factor        = peak_factor * noise_factor;

    vec3 final_color = mix(surface_color, peak_color * peak_intensity, peak_factor);

    vec2  foam_uv          = world_position.xz * foam_scale + time_scaled * 0.1;
    float foam_sample      = texture(foam_texture, foam_uv).r;
    float foam_blend_factor = smoothstep(0.0, 1.0, peak_factor) * foam_sample * foam_intensity;
    final_color = mix(final_color, vec3(1.0), foam_blend_factor);

    ALBEDO    = clamp(final_color + depth_color_adj, vec3(0.0), vec3(1.0));
    METALLIC  = metallic;
    ROUGHNESS = roughness;
    NORMAL    = perturbed_normal;
}
