shader_type spatial;

render_mode depth_prepass_alpha;
render_mode diffuse_toon;
render_mode specular_toon;

uniform sampler2D noise : repeat_enable; // cutout & shading texture
uniform float noise_shading : hint_range(0.0, 1.0) = 1.0; // shading from noise
uniform float intensity : hint_range(0.0, 1.0) = 0.0; // amount of blood
uniform vec4 color : source_color = vec4(1.0, 0.0, 0.0, 1.0); // color of blood
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform vec2 noise_offset = vec2(0.0);
// Card3D projects body and artwork into one continuous stain. Other uses
// retain the original UV-based blood mix without opting into this mode.
uniform bool use_card_projection = false;
uniform mat4 card_space_transform = mat4(1.0);
uniform bool exclude_artwork = false;
uniform vec4 artwork_rect = vec4(0.0);
varying vec2 card_xy;
varying vec2 blood_uv;
varying float blood_front;

void vertex() {
	vec3 card_position = (card_space_transform * vec4(VERTEX, 1.0)).xyz;
	card_xy = card_position.xy;
	blood_uv = card_position.xy / vec2(0.792, 1.2) + vec2(0.5);
	blood_front = normalize((card_space_transform * vec4(NORMAL, 0.0)).xyz).z;
}

void fragment() {
	if (intensity <= 0.0 || opacity <= 0.0 || (use_card_projection && blood_front < 0.5)) {
		discard;
	}
	if (use_card_projection && exclude_artwork && card_xy.x >= artwork_rect.x && card_xy.y >= artwork_rect.y && card_xy.x <= artwork_rect.z && card_xy.y <= artwork_rect.w) {
		discard;
	}
	vec2 stain_uv = use_card_projection ? blood_uv : UV;
	vec4 noise_texture = texture(noise, stain_uv + noise_offset);

	ALBEDO = color.rgb * mix(vec3(1.0), noise_texture.rgb, noise_shading);
	ALPHA = color.a * opacity * smoothstep(noise_texture.r - 0.015, noise_texture.r + 0.015, intensity);
	ROUGHNESS = 0.45;
}
