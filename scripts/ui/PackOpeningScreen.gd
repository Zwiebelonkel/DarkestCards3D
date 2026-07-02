extends Node3D
class_name PackOpeningScreen
signal pack_ready_for_next_purchase

const CARD_SCENE := preload("res://scenes/table/Card3D.tscn")
const RARITY_SOUND_PATH := "res://assets/sounds/SFX/%s.mp3"

@export var card_count := 5

@export var upgrade_ui: UpgradeUI

@export_group("Pack Opening")
@export var pack_body_open_position := Vector3(0, -0.18, 0)
@export var pack_top_fly_position := Vector3(0, 3.5, -2.6)
@export var pack_top_fly_rotation := Vector3(-180, 35, 90)

@export_group("Pack Top Drag")
@export var drag_open_distance: float = 260.0
@export var drag_top_max_offset := Vector3(1.65, 0.0, 0.0)
@export var drag_top_rotation := Vector3(0.0, 0.0, -28.0)
@export var drag_release_snap_time: float = 0.18
@export var base_shake_strength: float = 0.045
@export var base_shake_rotation_strength: float = 4.0

@export_group("Rip Physik")
@export var rip_fold_rotation_max: float = 55.0
@export var rip_resistance_curve: float = 2.4
@export var rip_bow_offset_max := Vector3(0.0, 0.05, -0.04)
@export var rip_snap_threshold: float = 0.82
@export var rip_snap_overshoot_rotation := Vector3(-12.0, 10.0, -55.0)
@export var rip_snap_overshoot_time: float = 0.09

@export_group("Cards In Pack")
@export var stack_base_position := Vector3(0, 0.62, -0.55)
@export var stack_position_offset := Vector3(0, 0.025, -0.018)
@export var stack_face_down_rotation := Vector3(-8, 180, 0)
@export var stack_card_scale := 0.82

@export_group("Reveal")
@export var shoot_height_offset := 0.45
@export var revealed_stack_position := Vector3(1.0, 0.62, -0.55)
@export var revealed_stack_offset := Vector3(0.015, 0.02, -0.01)
@export var revealed_scale := 0.72
@export var revealed_rotation := Vector3(-8, 0, 0)
@export var revealed_hover_offset := Vector3(-0.25, 0, 0)
@export var revealed_hover_rotation_offset := Vector3(0, -25, 0)
@export var revealed_hover_duration := 0.18
@onready var card_hover_sfx: AudioStreamPlayer = $CardHoverSFX

@export var card_drag_reveal_height: float = 0.55
@export var card_drag_pixels_per_unit: float = 280.0
@export var card_drag_snap_back_time: float = 0.16

var _dragging_top_card := false
var _top_card_drag_start_mouse_pos := Vector2.ZERO
var _top_card_drag_start_position := Vector3.ZERO

@export_group("Rarity Effekte")
@export var rarity_particle_spawn_offset := Vector3(0.0, 0.15, -0.45)
@export var rarity_pack_shake_multiplier: float = 1.0
@export var rarity_pack_shake_frequency: float = 55.0

@export var rarity_particle_spawn_box := Vector3(0.75, 0.05, 0.18)
@export var rarity_particle_up_spread: float = 6.0
@export var rarity_camera_shake_multiplier: float = 1.0
## Wie lange (Echtzeit-Sekunden, unbeeinflusst von Engine.time_scale) der
## Slow-Motion-Effekt bei hohen Rarities aktiv bleibt, bevor er ausklingt.
@export var rarity_slow_motion_fade_time: float = 0.25

@export var rarity_particle_lifetime: float = 0.9
@export var rarity_camera_shake_decay: float = 4.0

signal pack_cards_collected(card_ids: Array[String])

@export var cards_fly_target: Marker3D
@export var collection_screen: Node
@export var cards_fly_duration := 0.45
@export var cards_vanish_duration := 0.18
@export var screen_flash_camera: Camera3D

@export_group("Pack Reset")
@export var pack_hidden_offset := Vector3(0, -2.0, 0)
@export var pack_disappear_duration := 0.35
@export var pack_appear_duration := 0.45

var _waiting_for_collect_click := false
var _collecting_cards := false
var _pending_collection_card_ids: Array[String] = []

@onready var pack: Node3D = $pack
@onready var pack_mesh: MeshInstance3D = $pack/base
@onready var pack_top: MeshInstance3D = $pack/top
@onready var pack_top_area: Area3D = $pack/top/PackTopArea
@onready var cards_root: Node3D = $Cards
@onready var info_label: Label3D = $InfoLabel
@onready var rarity_particle_spawn: Marker3D = $pack/RarityParticleSpawn

var _hovering_pack := false
var _opened := false
var _dragging_pack_top := false
var _drag_start_mouse_pos := Vector2.ZERO
var _drag_progress := 0.0
var _pack_top_start_position := Vector3.ZERO
var _pack_top_start_rotation := Vector3.ZERO
var _pack_start_position := Vector3.ZERO
var _pack_start_rotation := Vector3.ZERO
var _rip_has_snapped := false
var _bend_material: ShaderMaterial = null
var _rarity_audio_player: AudioStreamPlayer

var _pack_effect_shake_strength := 0.0
var _pack_effect_shake_time_left := 0.0
var _pack_effect_base_position := Vector3.ZERO
var _cards_effect_base_position := Vector3.ZERO

var _card_stack: Array[Card3D] = []
var _revealed_cards: Array[Card3D] = []
var _revealed_rest_positions: Dictionary = {}
var _top_revealed_card: Card3D = null
var _pack_home_position := Vector3.ZERO
var _pack_home_rotation := Vector3.ZERO
var _pack_home_scale := Vector3.ONE

var _pack_top_home_position := Vector3.ZERO
var _pack_top_home_rotation := Vector3.ZERO
var _pack_top_home_scale := Vector3.ONE

var _screen_flash_layer: CanvasLayer = null
var _screen_flash_rect: ColorRect = null
var _camera_shake_strength := 0.0
var _camera_shake_time_left := 0.0
var _camera_base_position := Vector3.ZERO
var _camera_shake_target: Camera3D = null
var _active_camera_tween: Tween = null

var selected_pack_id := "basic"
var selected_pack_data: Dictionary = {}
var _pack_bought := false


func _ready() -> void:
	randomize()

	_pack_top_start_position = pack_top.position
	_pack_top_start_rotation = pack_top.rotation_degrees
	_pack_start_position = pack.position
	_pack_start_rotation = pack.rotation_degrees
	_pack_home_position = pack.position
	_pack_home_rotation = pack.rotation_degrees
	_pack_home_scale = pack.scale
	_pack_effect_base_position = pack.position
	_cards_effect_base_position = cards_root.position
	_rarity_audio_player = AudioStreamPlayer.new()
	_rarity_audio_player.bus = "SFX"
	add_child(_rarity_audio_player)

	_pack_top_home_position = pack_top.position
	_pack_top_home_rotation = pack_top.rotation_degrees
	_pack_top_home_scale = pack_top.scale

	_setup_bend_mesh()

	print("PackTopArea gefunden: ", pack_top_area)
	print("PackTopArea pickable: ", pack_top_area.input_ray_pickable)
	print("PackTopArea shapes: ", pack_top_area.get_child_count())

	if pack_top_area:
		pack_top_area.input_ray_pickable = true
		pack_top_area.monitoring = true
		pack_top_area.monitorable = true

		pack_top_area.mouse_entered.connect(func(): _hovering_pack = true)
		pack_top_area.mouse_exited.connect(func(): _hovering_pack = false)
		pack_top_area.input_event.connect(_on_pack_top_input)

	if screen_flash_camera == null:
		screen_flash_camera = get_viewport().get_camera_3d()
	_camera_shake_target = screen_flash_camera
	if _camera_shake_target:
		_camera_base_position = _camera_shake_target.global_position

	_setup_screen_flash_overlay()

	info_label.text = "PackTop ziehen"
	_hide_pack_until_bought()


## Erzeugt/holt das ShaderMaterial fuer den Bend-Mesh und initialisiert
## den bend_amount-Parameter auf 0 (komplett flach, am Body anliegend).
## bend_mesh bleibt standardmaessig unsichtbar - du schaltest selbst
## zwischen dem alten starren pack_top und diesem neuen Bend-Mesh um.
func _setup_bend_mesh() -> void:
	if pack_top == null:
		return

	var shader := load("res://assets/shader/bendVertex.gdshader") as Shader

	_bend_material = ShaderMaterial.new()
	_bend_material.shader = shader

	_bend_material.set_shader_parameter("bend_amount", 0.0)
	_bend_material.set_shader_parameter("pivot_x", -0.5)
	_bend_material.set_shader_parameter("bend_length", 1.0)

	var tex := load("res://assets/cards/pack/pack_cover1 - Kopie.png") as Texture2D
	_bend_material.set_shader_parameter("albedo_texture", tex)

	pack_top.material_override = _bend_material
	
func _process(delta: float) -> void:
	_update_camera_shake(delta)
	_update_pack_effect_shake(delta)

	if _opened:
		return

	if _dragging_pack_top:
		_apply_rip_physics(_drag_progress)
		return

	pack.rotation.y += sin(Time.get_ticks_msec() * 0.002) * delta * 0.45
	pack.rotation.x = sin(Time.get_ticks_msec() * 0.0015) * 0.08


func _input(event: InputEvent) -> void:
	if _dragging_top_card:
		if event is InputEventMouseMotion:
			var drag_delta: Vector2 = event.position - _top_card_drag_start_mouse_pos
			var lift_amount: float = clamp(-drag_delta.y / card_drag_pixels_per_unit, 0.0, card_drag_reveal_height)

			var top_card := _get_top_card()
			if top_card:
				top_card.position = _top_card_drag_start_position + Vector3(0, lift_amount, 0)

				if lift_amount >= card_drag_reveal_height:
					_dragging_top_card = false
					_reveal_top_card(top_card)

			return

		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_dragging_top_card = false

			var top_card := _get_top_card()
			if top_card:
				var tween := create_tween()
				tween.tween_property(top_card, "position", _top_card_drag_start_position, card_drag_snap_back_time) \
					.set_trans(Tween.TRANS_CUBIC) \
					.set_ease(Tween.EASE_OUT)

			return
	if _waiting_for_collect_click and not _collecting_cards:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_collect_revealed_cards()
		return

	if _opened:
		return

	if not _dragging_pack_top:
		return

	if event is InputEventMouseMotion:
		var drag_delta: Vector2 = event.position - _drag_start_mouse_pos

		# Maus nach links ziehen = Pack aufreissen
		var amount: float = clamp(drag_delta.x / drag_open_distance, 0.0, 1.0)
		_drag_progress = amount

		_apply_rip_physics(amount)

		if amount >= 1.0:
			info_label.text = "Loslassen zum Öffnen"
		elif amount >= rip_snap_threshold:
			info_label.text = "Fast durch..."
		else:
			info_label.text = "Nach links ziehen..."

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging_pack_top = false

		if _drag_progress >= 1.0:
			_open_pack_from_drag()
		else:
			_reset_pack_top_drag()


func _on_pack_top_input(
	_camera: Node,
	event: InputEvent,
	_position: Vector3,
	_normal: Vector3,
	_shape_idx: int
) -> void:
	if _opened:
		return
		
	if not _pack_bought:
		info_label.text = "Erst ein Pack kaufen"
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_dragging_pack_top = true
		print("Dragging")
		_drag_start_mouse_pos = event.position
		_drag_progress = 0.0
		_rip_has_snapped = false
		_pack_start_position = pack.position
		_pack_start_rotation = pack.rotation_degrees
		_pack_top_start_position = pack_top.position
		_pack_top_start_rotation = pack_top.rotation_degrees
		info_label.text = "Pack nach links aufreissen..."


## Wandelt den linearen Drag-Fortschritt (0..1) in eine "zaehe, dann
## nachgebende" Kurve um. Am Anfang bewegt sich kaum etwas (die Folie leistet
## Widerstand), dann beschleunigt es sichtbar Richtung Schnapp-Punkt.
func _rip_resistance(amount: float) -> float:
	return pow(amount, rip_resistance_curve)


func _apply_rip_physics(amount: float) -> void:
	var eased := _rip_resistance(amount)

	# Knick um die Biegeachse: waechst nichtlinear, nicht linear wie vorher.
	var fold_z := -rip_fold_rotation_max * eased

	pack_top.position = _pack_top_start_position \
		+ drag_top_max_offset * amount \
		+ rip_bow_offset_max * eased

	pack_top.rotation_degrees = _pack_top_start_rotation \
		+ drag_top_rotation * amount \
		+ Vector3(0.0, 0.0, fold_z)

	# Bend-Mesh (falls aktiv genutzt) bekommt denselben eased-Fortschritt
	# als Shader-Parameter, damit es sich synchron zur pack_top-Bewegung
	# verformt, statt nur starr rotiert zu werden.
	if _bend_material:
		_bend_material.set_shader_parameter("bend_amount", eased)

	_apply_base_shake(eased)

	# Schnapp-Moment: einmaliger kurzer Ueberschwinger, sobald der
	# Schwellenwert ueberschritten wird (nur einmal pro Drag-Versuch).
	if not _rip_has_snapped and amount >= rip_snap_threshold:
		_rip_has_snapped = true
		_play_rip_snap_overshoot()

func _play_rip_snap_overshoot() -> void:
	var snap_tween := create_tween()
	var target_rot := _pack_top_start_rotation + drag_top_rotation + rip_snap_overshoot_rotation
	snap_tween.tween_property(pack_top, "rotation_degrees", target_rot, rip_snap_overshoot_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Bend-Mesh: kurzer Ueberschwinger ueber bend_amount = 1.0 hinaus,
	# simuliert das ploetzliche Nachgeben der Folie am Schnapp-Punkt.
	if _bend_material:
		var bend_snap_tween := create_tween()
		bend_snap_tween.tween_method(
			func(v: float): _bend_material.set_shader_parameter("bend_amount", v),
			_bend_material.get_shader_parameter("bend_amount"),
			1.15,
			rip_snap_overshoot_time
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		bend_snap_tween.tween_method(
			func(v: float): _bend_material.set_shader_parameter("bend_amount", v),
			1.15,
			1.0,
			rip_snap_overshoot_time
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# leichter Zusatz-Ruck am Pack-Body, als ob die Folie ploetzlich nachgibt
	var jolt_tween := create_tween()
	var jolt_offset := _pack_start_position + Vector3(-0.025, 0.015, 0.0)
	jolt_tween.tween_property(pack, "position", jolt_offset, rip_snap_overshoot_time * 0.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	jolt_tween.tween_property(pack, "position", _pack_start_position, rip_snap_overshoot_time * 0.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	_trigger_camera_shake(0.08, 0.12)

func _reset_pack_top_drag() -> void:
	_rip_has_snapped = false

	var tween := create_tween().set_parallel(true)

	tween.tween_property(pack_top, "position", _pack_top_start_position, drag_release_snap_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(pack_top, "rotation_degrees", _pack_top_start_rotation, drag_release_snap_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	tween.tween_property(pack, "position", _pack_start_position, drag_release_snap_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(pack, "rotation_degrees", _pack_start_rotation, drag_release_snap_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	if _bend_material:
		tween.tween_method(
			func(v: float): _bend_material.set_shader_parameter("bend_amount", v),
			_bend_material.get_shader_parameter("bend_amount"),
			0.0,
			drag_release_snap_time
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	_drag_progress = 0.0
	info_label.text = "Pack nach links aufreissen"

func _open_pack_from_drag() -> void:
	_opened = true
	_hovering_pack = false
	_dragging_pack_top = false
	info_label.text = "Pack wird geöffnet..."

	if pack_top_area:
		pack_top_area.monitoring = false

	# Der Deckel fliegt jetzt aus seiner "geknickten" Haltung weiter, statt
	# erst zur Neutralstellung zurueckzuspringen - wirkt wie abgerissene Folie.
	var top_tween := create_tween().set_parallel(true)
	top_tween.tween_property(pack_top, "position", pack_top_fly_position, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	top_tween.tween_property(pack_top, "rotation_degrees", pack_top_fly_rotation, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	top_tween.tween_property(pack_top, "scale", Vector3.ZERO, 0.35)

	var body_tween := create_tween().set_parallel(true)
	body_tween.tween_property(pack, "position", pack_body_open_position, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	body_tween.tween_property(pack, "rotation_degrees", Vector3.ZERO, 0.25)

	_trigger_camera_shake(0.18, 0.22)

	await get_tree().create_timer(0.45).timeout

	pack_top.visible = false
	_spawn_cards_inside_pack()


func _spawn_cards_inside_pack() -> void:
	_clear_old_cards()

	var cards := CardDatabase.get_all_cards()
	if cards.is_empty():
		info_label.text = "Keine Karten gefunden"
		return

	cards.shuffle()

	for i in range(card_count):
		var data: Dictionary = CardDatabase.get_random_card_weighted()

		var card := CARD_SCENE.instantiate() as Card3D
		cards_root.add_child(card)
		card.setup(data)

		var final_pos := _get_stack_position(i)
		card.position = final_pos + Vector3(0, -0.75, 0)
		card.rotation_degrees = stack_face_down_rotation
		card.scale = Vector3.ONE * stack_card_scale

		_card_stack.append(card)


		var tween := create_tween().set_parallel(true)
		tween.tween_property(card, "position", final_pos, 0.32 + i * 0.045) \
			.set_trans(Tween.TRANS_CUBIC) \
			.set_ease(Tween.EASE_OUT)

		tween.tween_property(card, "rotation_degrees", stack_face_down_rotation, 0.32 + i * 0.045)

	await get_tree().create_timer(0.7).timeout

	_connect_top_card()
	info_label.text = "Oberste Karte anklicken"


func _get_stack_position(index: int) -> Vector3:
	return stack_base_position + stack_position_offset * index


func _get_revealed_position(index: int) -> Vector3:
	return revealed_stack_position + revealed_stack_offset * index


func _get_top_card() -> Card3D:
	if _card_stack.is_empty():
		return null

	return _card_stack[0]


func _connect_top_card() -> void:
	var top_card := _get_top_card()
	if top_card == null:
		return

	if top_card.area and not top_card.area.input_event.is_connected(_on_top_card_input):
		top_card.area.input_event.connect(_on_top_card_input)


func _disconnect_top_card() -> void:
	var top_card := _get_top_card()
	if top_card == null:
		return

	if top_card.area and top_card.area.input_event.is_connected(_on_top_card_input):
		top_card.area.input_event.disconnect(_on_top_card_input)


func _on_top_card_input(
	_camera: Node,
	event: InputEvent,
	_position: Vector3,
	_normal: Vector3,
	_shape_idx: int
) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return

	var top_card := _get_top_card()
	if top_card == null:
		return

	_dragging_top_card = true
	_top_card_drag_start_mouse_pos = event.position
	_top_card_drag_start_position = top_card.position

	info_label.text = "Karte nach oben ziehen"


func _reveal_top_card(card: Card3D) -> void:
	_disconnect_top_card()

	var card_id := str(card.card_data.get("id", ""))
	var card_name := str(card.card_data.get("name", card_id))
	var rarity_id := str(card.card_data.get("rarity", "common"))
	var rarity_data := RarityEffectsData.get_data(rarity_id)

	if card_id != "":
		_pending_collection_card_ids.append(card_id)

	info_label.text = card_name + " gezogen"

	_card_stack.erase(card)
	_revealed_cards.append(card)

	var reveal_index := _revealed_cards.size() - 1
	var final_pos := _get_revealed_position(reveal_index)

	if _card_stack.is_empty():
		info_label.text = "Pack vollständig geöffnet - klicken zum Einsammeln"
		_waiting_for_collect_click = true
	else:
		_realign_stack_in_pack()
		_connect_top_card()
		info_label.text = "Nächste Karte anklicken"

	var previous_top_card := _top_revealed_card
	if is_instance_valid(previous_top_card):
		_connect_revealed_hover(previous_top_card)

	_top_revealed_card = card

	_trigger_rarity_effects(rarity_id, rarity_data)
	_animate_revealed_card(card, final_pos, rarity_data)


## Buendelt alle Rarity-abhaengigen Praesentationseffekte: Partikel,
## Screen-Flash, Kamera-Shake, Slow-Motion und Sound-Hook.
func _trigger_rarity_effects(rarity_id: String, rarity_data: Dictionary) -> void:
	_spawn_reveal_particles(rarity_data)
	_trigger_screen_flash(rarity_data)
	_trigger_camera_shake(
		rarity_data.get("camera_shake_strength", 0.0),
		0.35 + RarityEffectsData.rarity_rank(rarity_id) * 0.05
	)
	_trigger_pack_effect_shake(
		rarity_data.get("camera_shake_strength", 0.0) * rarity_pack_shake_multiplier,
		0.35 + RarityEffectsData.rarity_rank(rarity_id) * 0.08
	)
	_play_rarity_sound(rarity_id)

	if RarityEffectsData.should_slow_motion(rarity_id):
		_apply_slow_motion(
			rarity_data.get("slow_motion_scale", 1.0),
			rarity_data.get("slow_motion_duration", 0.0)
		)


## Erzeugt einen einmaligen GPUParticles3D-Schuss, der senkrecht aus dem
## Pack-Inneren nach oben schiesst (wie ein Energieausbruch beim Reveal).
## Die Partikelmenge/-geschwindigkeit/-Gluehstaerke skaliert mit Rarity.
func _spawn_reveal_particles(rarity_data: Dictionary) -> void:
	var particles := GPUParticles3D.new()
	cards_root.add_child(particles)
	# Spawnt aus dem Pack-Inneren heraus, nicht an der (bereits hochfliegenden) Karte.
	if rarity_particle_spawn:
		particles.global_position = rarity_particle_spawn.global_position
	else:
		particles.global_position = pack.to_global(rarity_particle_spawn_offset)

	var amount: int = rarity_data.get("particle_amount", 10)
	var speed_scale: float = rarity_data.get("particle_speed", 1.0)
	var color: Color = rarity_data.get("color", Color.WHITE)
	var glow_energy: float = rarity_data.get("particle_glow_energy", 2.0)
	var glow_scale: float = rarity_data.get("particle_glow_scale", 1.0)

	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(0, 1, 0)
	# Enger Spread = klar erkennbarer Schuss nach oben statt diffuser Wolke.
	material.spread = rarity_particle_up_spread
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = rarity_particle_spawn_box
	# Kaum Schwerkraft am Anfang, damit der Schuss sichtbar nach oben durchkommt,
	# bevor die Partikel gegen Ende ihrer Lebenszeit leicht zurueckfallen.
	material.gravity = Vector3(0, -0.6, 0)
	material.initial_velocity_min = 2.2 * speed_scale
	material.initial_velocity_max = 3.4 * speed_scale
	# Leichtes Abbremsen zum Ende hin, statt linear durchzuschiessen.
	material.damping_min = 0.4
	material.damping_max = 0.9
	material.scale_min = 0.02 * glow_scale
	material.scale_max = 0.05 * glow_scale
	material.color = color

	# Kern-Mesh: kleine, helle Sphere mit starker Emission - der eigentliche
	# "leuchtende Kern" jedes Partikels.
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0

	var mesh_material := StandardMaterial3D.new()
	mesh_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_material.albedo_color = color
	mesh_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_material.emission_enabled = true
	mesh_material.emission = color
	mesh_material.emission_energy_multiplier = glow_energy
	mesh.material = mesh_material

	particles.process_material = material
	particles.draw_pass_1 = mesh
	particles.amount = max(amount, 1)
	particles.lifetime = rarity_particle_lifetime
	particles.one_shot = true
	particles.explosiveness = 0.75
	particles.emitting = true

	# Halo-Layer: zweites, deutlich groesseres und weicheres Partikelsystem
	# mit denselben Bewegungsdaten, aber additiver Transparenz und geringer
	# Deckkraft. Erzeugt einen weichen Lichthof um jeden Partikel, der den
	# "gluehenden" Eindruck verstaerkt, ohne projektweites Bloom anzufassen.
	if glow_scale > 1.0:
		var halo := GPUParticles3D.new()
		cards_root.add_child(halo)
		halo.global_position = particles.global_position

		var halo_material := material.duplicate() as ParticleProcessMaterial
		halo.process_material = halo_material

		var halo_mesh := SphereMesh.new()
		halo_mesh.radius = 1.0
		halo_mesh.height = 2.0

		var halo_mesh_material := StandardMaterial3D.new()
		halo_mesh_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		halo_mesh_material.albedo_color = Color(color.r, color.g, color.b, 0.35)
		halo_mesh_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		halo_mesh_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		halo_mesh_material.emission_enabled = true
		halo_mesh_material.emission = color
		halo_mesh_material.emission_energy_multiplier = glow_energy * 0.6
		halo_mesh.material = halo_mesh_material
		halo.draw_pass_1 = halo_mesh

		halo.amount = max(amount, 1)
		halo.lifetime = rarity_particle_lifetime
		halo.one_shot = true
		halo.explosiveness = 0.75
		halo.emitting = true
		# Halo-Partikel sind das 2.5-fache der Kern-Groesse, damit sie als
		# weicher Schein um den Kern liegen statt ihn zu verdecken.
		halo_material.scale_min = material.scale_min * 2.5
		halo_material.scale_max = material.scale_max * 2.5

		get_tree().create_timer(rarity_particle_lifetime + 0.5).timeout.connect(func():
			if is_instance_valid(halo):
				halo.queue_free()
		)

	var cleanup_time := rarity_particle_lifetime + 0.5
	get_tree().create_timer(cleanup_time).timeout.connect(func():
		if is_instance_valid(particles):
			particles.queue_free()
	)


## Erzeugt (einmalig, lazy) das CanvasLayer/ColorRect-Overlay fuer den
## Reveal-Glow und haengt es als Kindknoten dieser Szene ein. Das Rect
## bekommt den rarity_vignette_glow Shader, der per SCREEN_TEXTURE einen
## farbigen Vignette-Puls ueber das gerenderte Bild legt.
func _setup_screen_flash_overlay() -> void:
	_screen_flash_layer = CanvasLayer.new()
	_screen_flash_layer.layer = 50
	add_child(_screen_flash_layer)

	_screen_flash_rect = ColorRect.new()
	_screen_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)

	var shader := load("res://assets/shader/rarity_vignette_glow.gdshader") as Shader
	var shader_material := ShaderMaterial.new()
	shader_material.shader = shader
	shader_material.set_shader_parameter("glow_strength", 0.0)
	shader_material.set_shader_parameter("vignette_strength", 0.9)
	shader_material.set_shader_parameter("pulse_speed", 2.0)
	shader_material.set_shader_parameter("pulse_amount", 0.25)
	shader_material.set_shader_parameter("edge_power", 2.2)
	shader_material.set_shader_parameter("flicker_strength", 0.0)
	shader_material.set_shader_parameter("flicker_speed", 18.0)
	shader_material.set_shader_parameter("aberration_strength", 0.0)
	shader_material.set_shader_parameter("distortion_strength", 0.0)
	shader_material.set_shader_parameter("distortion_speed", 3.0)
	_screen_flash_rect.material = shader_material

	_screen_flash_layer.add_child(_screen_flash_rect)


## Faded den Vignette-Glow rarity-abhaengig ein, haelt ihn kurz und faded
## wieder aus. glow_strength ist der Haupt-animierte Parameter; Flicker,
## Aberration und Distortion laufen auf derselben Huellkurve mit, damit sie
## am Ende synchron wieder bei 0 ankommen statt haengenzubleiben.
func _trigger_screen_flash(rarity_data: Dictionary) -> void:
	var strength: float = rarity_data.get("screen_flash_strength", 0.0)
	var flicker_strength: float = rarity_data.get("screen_flicker_strength", 0.0)

	if (strength <= 0.0 and flicker_strength <= 0.0) or _screen_flash_rect == null or _screen_flash_rect.material == null:
		return

	var shader_material := _screen_flash_rect.material as ShaderMaterial
	var color: Color = rarity_data.get("color", Color.WHITE)
	var peak_glow := strength * 3.0 # glow_strength-Range ist 0..3, screen_flash_strength ist 0..~0.65

	var flicker_speed: float = rarity_data.get("screen_flicker_speed", 18.0)
	var aberration_target: float = rarity_data.get("aberration_strength", 0.0)
	var distortion_target: float = rarity_data.get("distortion_strength", 0.0)
	var distortion_speed: float = rarity_data.get("distortion_speed", 3.0)

	shader_material.set_shader_parameter("rarity_color", color)
	shader_material.set_shader_parameter("pulse_speed", 2.0 + strength * 4.0)
	shader_material.set_shader_parameter("pulse_amount", clamp(0.15 + strength * 0.3, 0.0, 1.0))
	shader_material.set_shader_parameter("vignette_strength", 0.7 + strength * 0.5)
	shader_material.set_shader_parameter("flicker_speed", flicker_speed)
	shader_material.set_shader_parameter("distortion_speed", distortion_speed)

	var hold_time := 0.15 + strength * 0.5
	var fade_in_time := 0.18
	var fade_out_time := 0.5

	# Eine Huellkurve (0 -> 1 -> 0), die alle vier Parameter gemeinsam treibt,
	# damit Flicker/Aberration/Distortion nicht unabhaengig vom Glow nachlaufen.
	var envelope_tween := create_tween()
	envelope_tween.tween_method(
		func(t: float):
			shader_material.set_shader_parameter("glow_strength", peak_glow * t)
			shader_material.set_shader_parameter("flicker_strength", flicker_strength * t)
			shader_material.set_shader_parameter("aberration_strength", aberration_target * t)
			shader_material.set_shader_parameter("distortion_strength", distortion_target * t),
		0.0, 1.0, fade_in_time
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	envelope_tween.tween_interval(hold_time)

	envelope_tween.tween_method(
		func(t: float):
			shader_material.set_shader_parameter("glow_strength", peak_glow * t)
			shader_material.set_shader_parameter("flicker_strength", flicker_strength * t)
			shader_material.set_shader_parameter("aberration_strength", aberration_target * t)
			shader_material.set_shader_parameter("distortion_strength", distortion_target * t),
		1.0, 0.0, fade_out_time
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)


func _trigger_camera_shake(strength: float, duration: float) -> void:
	if strength <= 0.0 or _camera_shake_target == null:
		return

	_camera_shake_strength = max(_camera_shake_strength, strength)
	_camera_shake_time_left = max(_camera_shake_time_left, duration)


func _update_camera_shake(delta: float) -> void:
	if _camera_shake_target == null:
		return

	if _camera_shake_time_left <= 0.0:
		# Kein Shake aktiv -> Basis kontinuierlich mit der tatsaechlichen
		# Kameraposition synchron halten. Andere Systeme (z.B. GameTable-
		# Kamera-Tweens) duerfen die Kamera frei bewegen, ohne dass der
		# Shake-Code sie anschliessend auf eine veraltete Position zurueckzieht.
		_camera_base_position = _camera_shake_target.global_position
		return

	_camera_shake_time_left -= delta
	_camera_shake_strength = max(_camera_shake_strength - rarity_camera_shake_decay * delta, 0.0)

	var t := Time.get_ticks_msec() * 0.001
	var offset := Vector3(
		sin(t * 37.0) * _camera_shake_strength,
		cos(t * 29.0) * _camera_shake_strength,
		0.0
	) * 0.05

	_camera_shake_target.global_position = _camera_base_position + offset

	if _camera_shake_time_left <= 0.0:
		_camera_shake_target.global_position = _camera_base_position


## Verlangsamt die globale Engine-Zeit kurz fuer ein "Bullet-Time"-Gefuehl
## bei seltenen Karten. duration ist in Echtzeit-Sekunden gemeint.
func _apply_slow_motion(scale: float, duration: float) -> void:
	if duration <= 0.0:
		return

	Engine.time_scale = scale

	var real_duration := duration * scale
	var timer := get_tree().create_timer(real_duration, false, false, true) # ignore time_scale
	await timer.timeout

	var fade_tween := create_tween()
	fade_tween.tween_method(
		func(v: float): Engine.time_scale = v,
		scale,
		1.0,
		rarity_slow_motion_fade_time
	)


func _play_rarity_sound(rarity_id: String) -> void:
	var path := RARITY_SOUND_PATH % rarity_id

	if not ResourceLoader.exists(path):
		push_warning("Kein Reveal-Sound gefunden: %s" % path)
		return

	var stream := load(path) as AudioStream
	if stream == null:
		return

	_rarity_audio_player.stop()
	_rarity_audio_player.stream = stream
	_rarity_audio_player.play()


func _animate_revealed_card(card: Card3D, final_pos: Vector3, rarity_data: Dictionary) -> void:
	var lift_position := card.position + Vector3(0, shoot_height_offset, 0)
	var rarity_scale_boost: float = 1.0 + RarityEffectsData.rarity_rank(str(card.card_data.get("rarity", "common"))) * 0.015

	var shoot_tween := create_tween().set_parallel(true)
	shoot_tween.tween_property(card, "position", lift_position, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	shoot_tween.tween_property(card, "scale", Vector3.ONE * 1.05 * rarity_scale_boost, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	await shoot_tween.finished

	if not is_instance_valid(card):
		return

	var flip_tween := create_tween().set_parallel(true)
	flip_tween.tween_property(card, "rotation_degrees", revealed_rotation, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	flip_tween.tween_property(card, "position", final_pos, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	flip_tween.tween_property(card, "scale", Vector3.ONE * revealed_scale, 0.32)

	await flip_tween.finished

	if not is_instance_valid(card):
		return

	card.position = final_pos
	card.rotation_degrees = revealed_rotation

	_revealed_rest_positions[card] = final_pos


func _connect_revealed_hover(card: Card3D) -> void:
	if not is_instance_valid(card) or not card.area:
		return

	if not card.area.mouse_entered.is_connected(_on_revealed_card_hover_start):
		card.area.mouse_entered.connect(_on_revealed_card_hover_start.bind(card))

	if not card.area.mouse_exited.is_connected(_on_revealed_card_hover_end):
		card.area.mouse_exited.connect(_on_revealed_card_hover_end.bind(card))


func _disconnect_revealed_hover(card: Card3D) -> void:
	if not is_instance_valid(card) or not card.area:
		return

	if card.area.mouse_entered.is_connected(_on_revealed_card_hover_start):
		card.area.mouse_entered.disconnect(_on_revealed_card_hover_start)

	if card.area.mouse_exited.is_connected(_on_revealed_card_hover_end):
		card.area.mouse_exited.disconnect(_on_revealed_card_hover_end)


func _on_revealed_card_hover_start(card: Card3D) -> void:
	if not is_instance_valid(card) or not _revealed_rest_positions.has(card):
		return

	if card == _top_revealed_card:
		return
		
	_play_card_hover_sfx()

	var rest_pos: Vector3 = _revealed_rest_positions[card]
	var hover_pos := rest_pos + revealed_hover_offset
	var hover_rot := revealed_rotation + revealed_hover_rotation_offset

	var tween := create_tween().set_parallel(true)
	tween.tween_property(card, "position", hover_pos, revealed_hover_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "rotation_degrees", hover_rot, revealed_hover_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _on_revealed_card_hover_end(card: Card3D) -> void:
	if not is_instance_valid(card) or not _revealed_rest_positions.has(card):
		return

	var rest_pos: Vector3 = _revealed_rest_positions[card]

	var tween := create_tween().set_parallel(true)
	tween.tween_property(card, "position", rest_pos, revealed_hover_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "rotation_degrees", revealed_rotation, revealed_hover_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _realign_stack_in_pack() -> void:
	for i in range(_card_stack.size()):
		var card := _card_stack[i]
		var tween := create_tween().set_parallel(true)
		tween.tween_property(card, "position", _get_stack_position(i), 0.18)
		tween.tween_property(card, "rotation_degrees", stack_face_down_rotation, 0.18)


func _clear_old_cards() -> void:
	for card in _card_stack:
		if is_instance_valid(card):
			card.queue_free()

	for card in _revealed_cards:
		if is_instance_valid(card):
			card.queue_free()

	_card_stack.clear()
	_revealed_cards.clear()
	_revealed_rest_positions.clear()
	_top_revealed_card = null


func _apply_base_shake(amount: float) -> void:
	var t := Time.get_ticks_msec() * 0.05

	var shake_power := amount * amount

	var shake_x := sin(t * 1.7) * base_shake_strength * shake_power
	var shake_y := cos(t * 2.1) * base_shake_strength * 0.45 * shake_power
	var shake_z := sin(t * 2.8) * base_shake_strength * 0.35 * shake_power

	pack.position = _pack_start_position + Vector3(shake_x, shake_y, shake_z)

	pack.rotation_degrees = _pack_start_rotation + Vector3(
		sin(t * 2.4) * base_shake_rotation_strength * shake_power,
		cos(t * 1.8) * base_shake_rotation_strength * 0.6 * shake_power,
		sin(t * 2.9) * base_shake_rotation_strength * 0.8 * shake_power
	)


func _collect_revealed_cards() -> void:
	if _collecting_cards:
		return

	_collecting_cards = true
	_waiting_for_collect_click = false
	info_label.text = "Karten werden gesammelt..."

	var target_pos := global_position + Vector3(0, 1.2, -0.8)

	if cards_fly_target:
		target_pos = cards_fly_target.global_position

	for card_id in _pending_collection_card_ids:
		CollectionManager.add_card(card_id)

	if collection_screen and collection_screen.has_method("refresh_collection"):
		collection_screen.refresh_collection()
		
	_refresh_upgrade_ui()

	var tween := create_tween().set_parallel(true)

	for i in range(_revealed_cards.size()):
		var card := _revealed_cards[i]
		if not is_instance_valid(card):
			continue

		_disconnect_revealed_hover(card)

		var delay := i * 0.045

		tween.tween_property(card, "global_position", target_pos, cards_fly_duration) \
			.set_delay(delay) \
			.set_trans(Tween.TRANS_CUBIC) \
			.set_ease(Tween.EASE_IN)

		tween.tween_property(card, "rotation_degrees", card.rotation_degrees + Vector3(0, 180, 25), cards_fly_duration) \
			.set_delay(delay)

		tween.tween_property(card, "scale", Vector3.ZERO, cards_vanish_duration) \
			.set_delay(delay + cards_fly_duration - 0.08) \
			.set_trans(Tween.TRANS_BACK) \
			.set_ease(Tween.EASE_IN)

	await tween.finished

	for card in _revealed_cards:
		if is_instance_valid(card):
			card.queue_free()

	_revealed_cards.clear()
	_revealed_rest_positions.clear()
	_pending_collection_card_ids.clear()
	_top_revealed_card = null

	await _reset_pack_for_next_opening()
	_collecting_cards = false


func _reset_pack_for_next_opening() -> void:
	var hidden_pos := _pack_home_position + pack_hidden_offset

	if pack_top_area:
		pack_top_area.monitoring = false
		pack_top_area.monitorable = false
		pack_top_area.input_ray_pickable = false

	var disappear_tween := create_tween().set_parallel(true)

	disappear_tween.tween_property(
		pack,
		"position",
		hidden_pos,
		pack_disappear_duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

	disappear_tween.tween_property(
		pack,
		"scale",
		_pack_home_scale * 0.15,
		pack_disappear_duration
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

	await disappear_tween.finished

	pack.visible = false
	pack_top.visible = false

	pack.position = _pack_home_position
	pack.rotation_degrees = _pack_home_rotation
	pack.scale = _pack_home_scale

	pack_top.position = _pack_top_home_position
	pack_top.rotation_degrees = _pack_top_home_rotation
	pack_top.scale = _pack_top_home_scale

	_opened = false
	_dragging_pack_top = false
	_drag_progress = 0.0
	_waiting_for_collect_click = false
	_rip_has_snapped = false
	_pack_bought = false

	info_label.text = "Neues Pack kaufen"
	pack_ready_for_next_purchase.emit()
	
func _refresh_upgrade_ui() -> void:
	if upgrade_ui == null:
		return

	var owned_cards := CollectionManager.get_owned_cards()
	var card_ids: Array = []

	for card_id in owned_cards.keys():
		if int(owned_cards[card_id]) <= 0:
			continue

		card_ids.append(str(card_id))

	upgrade_ui.set_cards(card_ids)
	upgrade_ui.refresh_balance()

func _trigger_pack_effect_shake(strength: float, duration: float) -> void:
	if strength <= 0.0:
		return

	_pack_effect_shake_strength = max(_pack_effect_shake_strength, strength)
	_pack_effect_shake_time_left = max(_pack_effect_shake_time_left, duration)

	_pack_effect_base_position = pack.position
	_cards_effect_base_position = cards_root.position


func _update_pack_effect_shake(delta: float) -> void:
	if _pack_effect_shake_time_left <= 0.0:
		pack.position = _pack_effect_base_position
		cards_root.position = _cards_effect_base_position
		return

	_pack_effect_shake_time_left -= delta

	var t := Time.get_ticks_msec() * 0.001 * rarity_pack_shake_frequency
	var power := _pack_effect_shake_strength

	var offset := Vector3(
		sin(t * 1.3) * power,
		cos(t * 1.7) * power * 0.45,
		sin(t * 2.1) * power * 0.35
	) * 0.04

	pack.position = _pack_effect_base_position + offset
	cards_root.position = _cards_effect_base_position + offset * 1.25

	_pack_effect_shake_strength = max(
		_pack_effect_shake_strength - rarity_camera_shake_decay * delta,
		0.0
	)

	if _pack_effect_shake_time_left <= 0.0:
		pack.position = _pack_effect_base_position
		cards_root.position = _cards_effect_base_position
		
func _play_card_hover_sfx() -> void:
	if card_hover_sfx == null:
		return
	
	if card_hover_sfx.playing:
		card_hover_sfx.stop()
	
	card_hover_sfx.play()

func buy_pack(pack_id: String, pack_data: Dictionary) -> bool:
	if _opened or _dragging_pack_top or _collecting_cards:
		return false

	var cost := int(pack_data.get("cost", 0))

	if not GameCurrency.spend_coins(cost):
		info_label.text = "Nicht genug Soul Coins"
		return false

	selected_pack_id = pack_id
	selected_pack_data = pack_data
	card_count = int(pack_data.get("card_count", card_count))
	_pack_bought = true

	info_label.text = str(pack_data.get("name", "Pack")) + " gekauft - PackTop ziehen"
	var pack_scene := pack_data.get("scene", null) as PackedScene
	_set_pack_model(pack_scene)
	_show_bought_pack()

	return true
	
func _hide_pack_until_bought() -> void:
	pack.visible = false
	pack_top.visible = false

func _show_bought_pack() -> void:
	pack.visible = true
	pack_top.visible = true

	var start_pos := _pack_home_position + pack_hidden_offset

	pack.position = start_pos
	pack.rotation_degrees = _pack_home_rotation
	pack.scale = Vector3.ZERO

	pack_top.position = _pack_top_home_position
	pack_top.rotation_degrees = _pack_top_home_rotation
	pack_top.scale = _pack_top_home_scale

	if pack_top_area:
		pack_top_area.monitoring = true
		pack_top_area.monitorable = true
		pack_top_area.input_ray_pickable = true

	var tween := create_tween().set_parallel(true)

	tween.tween_property(
		pack,
		"position",
		_pack_home_position,
		0.45
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	tween.tween_property(
		pack,
		"scale",
		_pack_home_scale,
		0.45
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_pack_model(pack_scene: PackedScene) -> void:
	if pack_scene == null:
		return

	var old_pack := pack
	var old_transform := pack.transform
	var old_index := pack.get_index()

	remove_child(old_pack)
	old_pack.queue_free()

	pack = pack_scene.instantiate() as Node3D
	pack.name = "pack"
	add_child(pack)
	move_child(pack, old_index)
	pack.transform = old_transform

	pack_mesh = pack.get_node_or_null("base") as MeshInstance3D
	pack_top = pack.get_node_or_null("top") as MeshInstance3D
	rarity_particle_spawn = pack.get_node_or_null("RarityParticleSpawn") as Marker3D

	if rarity_particle_spawn == null:
		rarity_particle_spawn = Marker3D.new()
		rarity_particle_spawn.name = "RarityParticleSpawn"
		pack.add_child(rarity_particle_spawn)
		rarity_particle_spawn.position = rarity_particle_spawn_offset

	_ensure_pack_top_area()
	_setup_bend_mesh()

	_pack_home_position = pack.position
	_pack_home_rotation = pack.rotation_degrees
	_pack_home_scale = pack.scale

	_pack_top_home_position = pack_top.position
	_pack_top_home_rotation = pack_top.rotation_degrees
	_pack_top_home_scale = pack_top.scale
	
func _ensure_pack_top_area() -> void:
	if pack_top == null:
		push_error("Pack hat keinen Node namens 'top'")
		return

	pack_top_area = pack_top.get_node_or_null("PackTopArea") as Area3D

	if pack_top_area == null:
		pack_top_area = Area3D.new()
		pack_top_area.name = "PackTopArea"
		pack_top.add_child(pack_top_area)

		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(2.06586, 0.235229, 4.01843)

		collision.shape = shape
		collision.position = Vector3(-1.0485, 0.055725, 0.0370484)
		pack_top_area.add_child(collision)

	pack_top_area.input_ray_pickable = true
	pack_top_area.monitoring = true
	pack_top_area.monitorable = true

	if not pack_top_area.input_event.is_connected(_on_pack_top_input):
		pack_top_area.input_event.connect(_on_pack_top_input)

	if not pack_top_area.mouse_entered.is_connected(_on_pack_mouse_entered):
		pack_top_area.mouse_entered.connect(_on_pack_mouse_entered)

	if not pack_top_area.mouse_exited.is_connected(_on_pack_mouse_exited):
		pack_top_area.mouse_exited.connect(_on_pack_mouse_exited)
		
func _on_pack_mouse_entered() -> void:
	_hovering_pack = true


func _on_pack_mouse_exited() -> void:
	_hovering_pack = false
