shader_type spatial;
render_mode unshaded;

uniform sampler2D albedo_texture: source_color, filter_nearest, repeat_disable;
uniform sampler2D noise_texture: filter_linear, repeat_enable;
uniform vec2 uv_offset = vec2(0.0);
uniform float intensity = 0.7;
uniform float framerate = 30.0;
uniform float resolution = 64.0;

void vertex() {
	// Preserve inherited room/prop scale while facing the shared world camera.
	vec3 model_scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * model_scale.x, INV_VIEW_MATRIX[1] * model_scale.y, INV_VIEW_MATRIX[2] * model_scale.z, MODEL_MATRIX[3]);
}

void fragment() {
    vec2 flame_uv = (floor(UV * resolution) + 0.5) / resolution;
    vec2 uv = flame_uv + uv_offset;

    float vertical_intensity = (1.0 - flame_uv.y) * intensity;
	
	float time_seed = (NODE_POSITION_WORLD.x + NODE_POSITION_WORLD.y + NODE_POSITION_WORLD.z);
	float frame_time = floor(TIME * framerate) / framerate;
	float time = (frame_time * 10.0) + time_seed;
	float noise_time = (frame_time * 1.0) + time_seed;

    float noise = texture(noise_texture, flame_uv + vec2(sin(noise_time + vertical_intensity * 10.0) * 0.1, noise_time)).r;
    float normal_noise = noise - 0.5;

    float flame_offset = sin(time + uv.y * 10.0 * noise);

    uv.y += flame_offset * (vertical_intensity * 0.1);
    uv.x += normal_noise * 0.5 * vertical_intensity;

    vec4 color = texture(albedo_texture, uv);

    ALBEDO = color.rgb + (noise * vertical_intensity);
    ALPHA = color.a;
}
