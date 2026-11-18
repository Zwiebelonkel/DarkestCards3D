shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_test_disabled, depth_draw_never;

uniform sampler2D icon_texture : source_color, filter_nearest;
uniform vec4 accent_color : source_color = vec4(0.3, 1.0, 0.35, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float radius = length(UV - vec2(0.5));
	float coverage = 1.0 - smoothstep(0.46, 0.49, radius);
	float border = smoothstep(0.41, 0.44, radius);
	vec2 icon_uv = (UV - vec2(0.5)) / 0.72 + vec2(0.5);
	float icon = 0.0;
	if (all(greaterThanEqual(icon_uv, vec2(0.0))) && all(lessThanEqual(icon_uv, vec2(1.0)))) {
		icon = texture(icon_texture, icon_uv).a;
	}
	vec3 color = mix(vec3(0.015, 0.022, 0.025), accent_color.rgb, max(border, icon));
	ALBEDO = color;
	EMISSION = accent_color.rgb * (border * 0.2 + icon * 0.45);
	ALPHA = coverage * opacity;
}
