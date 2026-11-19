shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

instance uniform float blot_seed = 0.0;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	vec2 stretched = p * vec2(1.0, 1.08);
	float angle = atan(stretched.y, stretched.x);
	float radius = length(stretched);
	float edge = 0.73 + 0.065 * sin(angle * 5.0 + blot_seed)
		+ 0.038 * sin(angle * 9.0 - blot_seed * 1.7);
	float aa = max(fwidth(radius), 0.012);
	float coverage = 1.0 - smoothstep(edge - aa, edge + aa, radius);
	// Separate little drops make this read as a spill rather than a badge.
	float drops = max(
		1.0 - smoothstep(0.075, 0.115, length(p - vec2(0.78, 0.43))),
		1.0 - smoothstep(0.055, 0.09, length(p - vec2(-0.72, -0.60)))
	);
	coverage = max(coverage, drops);
	float rim = smoothstep(edge - 0.13, edge - 0.01, radius);
	vec3 color = mix(vec3(0.82, 0.59, 0.025), vec3(0.46, 0.29, 0.008), rim * 0.6);
	float shine = 1.0 - smoothstep(0.09, 0.16, length((p - vec2(-0.18, 0.27)) * vec2(0.65, 2.2)));
	color = mix(color, vec3(1.0, 0.88, 0.34), shine * 0.7);
	ALBEDO = color;
	ALPHA = coverage * 0.98;
}
