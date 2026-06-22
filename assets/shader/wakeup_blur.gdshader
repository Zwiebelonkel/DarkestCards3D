shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

uniform float blur_amount = 0.0;
uniform float chromatic_amount = 0.0;
uniform float black_amount = 0.0;
uniform float white_flash = 0.0;
uniform float noise_amount = 0.0;
uniform float vignette_amount = 0.0;
uniform float desaturation = 0.0;

float rand(vec2 co) {
	return fract(sin(dot(co.xy + TIME, vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 blur_screen(vec2 uv, float amount) {
	vec2 o = vec2(amount) / vec2(textureSize(screen_texture, 0));

	vec3 col = texture(screen_texture, uv).rgb * 0.28;
	col += texture(screen_texture, uv + vec2(o.x, 0.0)).rgb * 0.12;
	col += texture(screen_texture, uv - vec2(o.x, 0.0)).rgb * 0.12;
	col += texture(screen_texture, uv + vec2(0.0, o.y)).rgb * 0.12;
	col += texture(screen_texture, uv - vec2(0.0, o.y)).rgb * 0.12;
	col += texture(screen_texture, uv + vec2(o.x, o.y)).rgb * 0.06;
	col += texture(screen_texture, uv - vec2(o.x, o.y)).rgb * 0.06;
	col += texture(screen_texture, uv + vec2(o.x, -o.y)).rgb * 0.06;
	col += texture(screen_texture, uv + vec2(-o.x, o.y)).rgb * 0.06;

	return col;
}

void fragment() {
	vec2 uv = SCREEN_UV;

	vec3 color = blur_screen(uv, blur_amount);

	vec2 center_dir = uv - vec2(0.5);
	vec2 chroma_offset = center_dir * chromatic_amount * 0.006;

	float r = texture(screen_texture, uv + chroma_offset).r;
	float g = color.g;
	float b = texture(screen_texture, uv - chroma_offset).b;

	color = mix(color, vec3(r, g, b), clamp(chromatic_amount / 6.0, 0.0, 1.0));

	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(color, vec3(luma), desaturation);

	float n = rand(floor(uv * 320.0));
	color += (n - 0.5) * noise_amount;

	float dist = distance(uv, vec2(0.5));
	float vignette = smoothstep(0.82, 0.25, dist);
	color *= mix(1.0, vignette, vignette_amount);

	color = mix(color, vec3(1.0), white_flash);
	color = mix(color, vec3(0.0), black_amount);

	COLOR = vec4(color, 1.0);
}