shader_type canvas_item;
render_mode blend_add, unshaded;

uniform float brightness : hint_range(1.0, 5.0) = 3.0;
uniform float glow_strength : hint_range(0.0, 1.0) = 0.45;
uniform vec4 glow_color : source_color = vec4(1.0, 0.55, 0.15, 1.0);

varying vec4 flash_modulate;

void vertex() {
	flash_modulate = COLOR;
}

void fragment() {
	vec4 flash = texture(TEXTURE, UV);
	vec2 offset = UV - vec2(0.5);
	float halo = exp(-dot(offset, offset) * 28.0) * glow_strength;
	vec3 radiance = flash.rgb * flash.a * brightness + glow_color.rgb * halo;
	COLOR = vec4(radiance * flash_modulate.rgb, flash_modulate.a);
}
