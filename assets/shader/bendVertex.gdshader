shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;

uniform sampler2D albedo_texture : source_color;

uniform float bend_amount : hint_range(0.0, 1.0) = 0.0;

// Gesamtstärke der Aufrollung
uniform float max_bend_angle : hint_range(0.0, 3.14159) = 1.15;

// Wie weit die Folie nach oben abhebt
uniform float lift_strength : hint_range(0.0, 1.0) = 0.18;

// Breite der weichen Knickzone
uniform float peel_softness : hint_range(0.001, 0.5) = 0.16;

// 0 = links ist fest, 1 = rechts ist fest
uniform float flip_direction : hint_range(0.0, 1.0) = 0.0;

// Flattern
uniform float flutter_strength : hint_range(0.0, 0.2) = 0.025;
uniform float flutter_speed : hint_range(0.0, 20.0) = 8.0;

// Textur/Material
uniform float roughness_value : hint_range(0.0, 1.0) = 0.55;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;

varying float v_t;
varying float v_free;

void vertex() {
	// UV.x steuert die Länge der Folie.
	// links fest: UV.x = 0 Anker, UV.x = 1 freies Ende
	float t = mix(UV.x, 1.0 - UV.x, flip_direction);
	v_t = t;

	// Die Abrisskante wandert mit bend_amount von links nach rechts.
	float peel_edge = clamp(bend_amount, 0.0, 0.98);

	// Bereich vor der Abrisskante bleibt fest.
	float unstuck = smoothstep(peel_edge - peel_softness, peel_edge + peel_softness, t);

	// Lokaler Fortschritt NUR im gelösten Teil.
	float free_t = clamp((t - peel_edge) / max(0.001, 1.0 - peel_edge), 0.0, 1.0);
	v_free = free_t * unstuck;

	// Anfang bleibt steifer, Ende rollt stärker auf.
	float curve = free_t * free_t;

	float angle = curve * max_bend_angle * bend_amount * unstuck;

	float s = sin(angle);
	float c = cos(angle);

	// Wichtig:
	// Wir biegen in lokaler XY-Ebene.
	// X bleibt die Länge, Y geht nach oben.
	// Der bereits klebende Teil bleibt durch unstuck bei seiner Originalposition.
	float rel_x = VERTEX.x;

	float bent_x = rel_x * c;
	float bent_y = VERTEX.y + abs(rel_x) * s;

	// Zusätzliches Anheben nur im gelösten Bereich.
	float lift = lift_strength * bend_amount * unstuck * (0.15 + free_t * 0.85);

	// Leichtes Flattern am losen Ende.
	float flutter = sin(TIME * flutter_speed + UV.y * 18.0 + UV.x * 9.0)
		* flutter_strength
		* bend_amount
		* unstuck
		* free_t;

	VERTEX.x = mix(VERTEX.x, bent_x, unstuck);
	VERTEX.y = mix(VERTEX.y, bent_y, unstuck) + lift + flutter;

	// Normale grob mitdrehen.
	NORMAL = normalize((mat3(
		vec3(c, s, 0.0),
		vec3(-s, c, 0.0),
		vec3(0.0, 0.0, 1.0)
	) * NORMAL));
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);

	ALBEDO = tex.rgb;
	ALPHA = tex.a;

	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
}