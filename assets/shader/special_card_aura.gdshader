shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

// A separate, front-facing veil leaves print, animated artwork and Holo intact.
uniform vec4 gold_color : source_color = vec4(1.0, 0.62, 0.19, 1.0);
uniform vec4 violet_color : source_color = vec4(0.55, 0.22, 1.0, 1.0);
uniform float flow_speed : hint_range(0.0, 2.0) = 0.48;
uniform float intensity : hint_range(0.0, 3.0) = 1.25;
uniform float phase = 0.0;
uniform vec2 veil_size = vec2(0.972, 1.32);
uniform vec2 card_half_size = vec2(0.396, 0.57);

float hash_2d(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float soft_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 weight = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash_2d(cell), hash_2d(cell + vec2(1.0, 0.0)), weight.x),
		mix(hash_2d(cell + vec2(0.0, 1.0)), hash_2d(cell + vec2(1.0)), weight.x),
		weight.y
	);
}

float mist_noise(vec2 p) {
	return soft_noise(p) * 0.65 + soft_noise(p * 2.03 + vec2(7.1, 3.4)) * 0.35;
}

float rounded_card(vec2 p) {
	float radius = 0.045;
	vec2 q = abs(p) - card_half_size + vec2(radius);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

void fragment() {
	// No aura through a face-down card or a bright strip seen edge-on.
	float facing = smoothstep(0.08, 0.40, dot(NORMAL, VIEW));
	vec2 p = (UV - vec2(0.5)) * veil_size;
	float distance_to_card = rounded_card(p);
	// Only the perimeter is shaded: labels and the artwork remain clear.
	if (facing <= 0.0 || distance_to_card < -0.085) {
		discard;
	}
	float time = TIME * flow_speed + phase;
	vec2 flow_uv = p * 5.0 + vec2(time * 0.18, -time * 0.72);
	vec2 warp = vec2(
		mist_noise(flow_uv + vec2(0.0, time * 0.13)),
		mist_noise(flow_uv + vec2(8.2, 3.7))
	) - vec2(0.5);
	float warped_edge = rounded_card(p + warp * 0.095);
	float smoke = mist_noise(flow_uv * 1.7 + warp * 2.1 - vec2(time * 0.12, 0.0));
	float ribbon = exp(-abs(warped_edge + 0.004) * 95.0);
	float halo = exp(-abs(distance_to_card) * 25.0) * smoothstep(0.24, 0.83, smoke);
	float inner_fade = smoothstep(-0.085, -0.025, distance_to_card);
	float outer_fade = 1.0 - smoothstep(0.045, 0.085, distance_to_card);
	float breath = 0.90 + 0.10 * sin(time * 1.35);
	float energy = (ribbon * (0.35 + smoke * 0.9) + halo * 0.65) * inner_fade * outer_fade;
	float color_flow = smoothstep(0.22, 0.78, soft_noise(p * 3.0 + warp + vec2(time * 0.20, -time * 0.15)));
	vec3 tint = mix(violet_color.rgb, gold_color.rgb, color_flow);
	ALBEDO = tint * energy * intensity * breath;
	ALPHA = facing * max(gold_color.a, violet_color.a);
}
