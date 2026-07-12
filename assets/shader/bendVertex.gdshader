shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;

uniform sampler2D albedo_texture : source_color;
uniform float bend_amount : hint_range(0.0, 1.0) = 0.0;
uniform float max_bend_angle : hint_range(0.0, 6.28318) = 3.8;
uniform float lift_strength : hint_range(0.0, 1.0) = 0.08;
uniform float peel_softness : hint_range(0.001, 0.5) = 0.16;
uniform float flip_direction : hint_range(0.0, 1.0) = 0.0;
uniform float flutter_strength : hint_range(0.0, 0.2) = 0.025;
uniform float flutter_speed : hint_range(0.0, 20.0) = 8.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.55;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;

// Anker-Punkt + Laenge des Streifens in lokalen Mesh-Koordinaten,
// automatisch aus der AABB berechnet (siehe Script).
uniform float anchor_x = 0.0;
uniform float mesh_length = 1.0;

varying float v_t;
varying float v_free;

void vertex() {
	float raw_t = (VERTEX.x - anchor_x) / max(mesh_length, 0.001);

	// Verlauf vom festen Anker bis zur freien Seite
	float t = clamp(1.0 - raw_t, 0.0, 1.0);
	v_t = t;

	float peel_edge = clamp(bend_amount, 0.0, 0.98);

	float unstuck = smoothstep(
		peel_edge - peel_softness,
		peel_edge + peel_softness,
		t
	);

	float free_t = clamp(
		(t - peel_edge) / max(0.001, 1.0 - peel_edge),
		0.0,
		1.0
	);

	v_free = free_t * unstuck;

	// Weicher werdende Rollbewegung
	float curve = free_t * free_t;
	float angle = curve * max_bend_angle * bend_amount * unstuck;

	float s = sin(angle);
	float c = cos(angle);

	float local_x = VERTEX.x - anchor_x;

	float bend_dir = sign(local_x);
	if (bend_dir == 0.0) {
		bend_dir = 1.0;
	}

	float dist = abs(local_x);

	// X wird beim Rollen kürzer
	float bent_local_x = bend_dir * dist * c;

	// Das Packtop rollt sich in die Tiefe entlang der Z-Achse ein
	float bent_z = VERTEX.z + dist * s;

	// Nur eine minimale zusätzliche Höhe für eine natürliche Rundung
	float slight_lift =
		lift_strength
		* bend_amount
		* unstuck
		* free_t
		* 0.08;

	float flutter =
		sin(
			TIME * flutter_speed
			+ UV.y * 18.0
			+ UV.x * 9.0
		)
		* flutter_strength
		* bend_amount
		* unstuck
		* free_t;

	// Fester Anker
	VERTEX.x = anchor_x + mix(local_x, bent_local_x, unstuck);

	// Tiefe statt starker Bewegung nach oben
	VERTEX.z = mix(VERTEX.z, bent_z, unstuck);

	// Nur ganz leichte Bewegung auf Y
	VERTEX.y += slight_lift + flutter;

	// Normale ebenfalls um die Y-Achse drehen,
	// da die Biegung jetzt in der X/Z-Ebene stattfindet
	NORMAL = normalize(
		mat3(
			vec3(c, 0.0, -s),
			vec3(0.0, 1.0, 0.0),
			vec3(s, 0.0, c)
		) * NORMAL
	);
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	ALBEDO = tex.rgb;
	ALPHA = tex.a;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
}