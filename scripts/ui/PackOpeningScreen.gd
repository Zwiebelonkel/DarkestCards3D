extends Node3D
class_name PackOpeningScreen
signal pack_opening_started
signal pack_ready_for_next_purchase
signal pack_batch_progress(current_pack: int, total_packs: int)

const CARD_SCENE := preload("res://scenes/table/Card3D.tscn")
const NEW_CARD_LABEL := preload("res://scripts/card/NewCardLabel.gd")
const EFFECT_OVERVIEW_SCENE := preload("res://scenes/CardEffectOverview.tscn")
const RARITY_SOUND_PATH := "res://assets/sounds/SFX/%s.mp3"
const FOIL_SCRIPT := preload("res://scripts/packs/PackFoil.gd")
const FOIL_AUDIO_SCRIPT := preload("res://scripts/packs/FoilAudio.gd")
const SURFACE_SCRIPT := preload("res://scripts/packs/PackSurface.gd")

@export var card_count := 5

@export var upgrade_ui: UpgradeUI

@export_group("Pack Opening")
@export var pack_body_open_position := Vector3(0, -0.18, 0)
@export var pack_top_throw_velocity := Vector3(2.8, 3.0, 0.6)
@export var pack_top_throw_gravity := 10.0
@export var pack_top_throw_duration := 1.1

@export_group("Pack Mouse Tilt")
@export_range(0.0, 15.0, 0.5) var pack_mouse_tilt_degrees: float = 7.0
@export_range(1.0, 20.0, 0.5) var pack_mouse_follow_speed: float = 9.0

@export_group("Pack Top Drag")
@export var drag_open_distance: float = 260.0
@export_range(0.08, 0.6, 0.01) var drag_release_snap_time: float = 0.24
@export var base_shake_strength: float = 0.012
@export var base_shake_rotation_strength: float = 1.0

@export_group("Rip Physik")
@export_range(1.0, 2.5, 0.05) var rip_resistance_curve: float = 1.3
@export_range(5.0, 30.0, 0.5) var rip_follow_speed: float = 16.0
@export_range(0.0, 24.0, 1.0) var rip_grab_slack_pixels: float = 7.0

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
var _pending_collection_instances: Array[Dictionary] = []

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
var _foil: RefCounted
var _foil_audio: Node
var _foil_rest_bounds := AABB()
var _foil_lift := 0.0
var _foil_lift_target := 0.0
var _foil_motion_speed := 0.0
var _pull_target_progress := 0.0
var _drag_start_progress := 0.0
var _drag_screen_axis := Vector2.RIGHT
var _drag_screen_distance := 260.0
var _last_drag_mouse_pos := Vector2.ZERO
var _last_drag_time_usec := 0
var _pack_transitioning := false
var _pack_generation := 0
var _pack_motion_tween: Tween
var _foil_flight_tween: Tween
var _rarity_audio_player: AudioStreamPlayer

var _pack_effect_shake_strength := 0.0
var _pack_effect_shake_time_left := 0.0
var _pack_effect_base_position := Vector3.ZERO
var _cards_effect_base_position := Vector3.ZERO

var _card_stack: Array[Card3D] = []
var _revealed_cards: Array[Card3D] = []
var _revealed_rest_positions: Dictionary = {}
var _top_revealed_card: Card3D = null
var _effect_overview_layer: CanvasLayer = null
var _effect_overview: CardEffectOverviewUI = null
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
var _purchase_in_progress := false
var _pack_batch_total := 0
var _pack_batch_current := 0
var _pack_reservation := 0


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

	_foil = FOIL_SCRIPT.new()
	_foil_audio = FOIL_AUDIO_SCRIPT.new()
	add_child(_foil_audio)
	_setup_foil()
	_ensure_pack_top_area()
	get_window().focus_exited.connect(_on_pack_focus_lost)

	if screen_flash_camera == null:
		screen_flash_camera = get_viewport().get_camera_3d()
	_camera_shake_target = screen_flash_camera
	if _camera_shake_target:
		_camera_base_position = _camera_shake_target.global_position

	_setup_screen_flash_overlay()

	_hide_pack_until_bought()
	info_label.text = "Pack am Automaten auswählen"


func _exit_tree() -> void:
	if _pack_reservation != 0:
		GameCurrency.refund_queued_packs(_pack_reservation)
		_pack_reservation = 0


func _setup_foil() -> void:
	if _foil == null or not is_instance_valid(pack_top):
		return
	SURFACE_SCRIPT.apply_to_pack(pack, selected_pack_id, false)
	_foil.configure(pack_top, selected_pack_id)
	_foil_rest_bounds = _foil.get_local_bounds()
	_reset_foil_state()


func _reset_foil_state() -> void:
	_dragging_pack_top = false
	_drag_progress = 0.0
	_drag_start_progress = 0.0
	_pull_target_progress = 0.0
	_foil_lift = 0.0
	_foil_lift_target = 0.0
	_foil_motion_speed = 0.0
	if _foil != null:
		_foil.reset()
	if _foil_audio != null:
		_foil_audio.stop()


func _update_foil_grab_shape() -> void:
	if _foil == null or not is_instance_valid(pack_top_area):
		return
	var collision := pack_top_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null or not collision.shape is BoxShape3D:
		return
	# Follow the deformed strip, so a released curled edge can be grabbed again.
	var bounds: AABB = _foil.get_deformed_bounds()
	collision.position = bounds.get_center()
	(collision.shape as BoxShape3D).size = bounds.size.max(Vector3(0.12, 0.16, 0.16)) + Vector3(0.08, 0.06, 0.08)


func _process(delta: float) -> void:
	_update_camera_shake(delta)
	_update_pack_effect_shake(delta)
	if _pack_transitioning or not _pack_bought:
		return
	if _opened:
		# The torn foil keeps fluttering during its release flight.
		if pack_top.visible and _foil != null:
			_foil.update_foil(1.0, 0.25, 0.45, delta)
		return
	if _dragging_pack_top and not pack_top_area.input_ray_pickable:
		_pull_target_progress = _drag_progress
		_release_pack_top_drag()

	var previous_progress := _drag_progress
	if _dragging_pack_top:
		var response := 1.0 - exp(-rip_follow_speed * delta)
		_drag_progress = maxf(_drag_progress, lerpf(_drag_progress, _pull_target_progress, response))
		if _pull_target_progress >= 1.0 and _drag_progress >= 0.988:
			_drag_progress = 1.0
	_foil_lift = lerpf(_foil_lift, _foil_lift_target, 1.0 - exp(-delta / maxf(drag_release_snap_time * 0.3, 0.01)))
	var tear_speed := (_drag_progress - previous_progress) / maxf(delta, 0.001)
	_foil_motion_speed = lerpf(_foil_motion_speed, 0.0, 1.0 - exp(-delta * 10.0))
	if _foil != null:
		_foil.update_foil(_drag_progress, _foil_lift, maxf(tear_speed, _foil_motion_speed), delta)
		_update_foil_grab_shape()
	if _foil_audio != null:
		_foil_audio.set_motion(clampf(tear_speed * 0.65 + _foil_motion_speed * 0.16, 0.0, 1.0) if _dragging_pack_top else 0.0, _foil_lift if _dragging_pack_top else 0.0)

	var pull_force := clampf(tear_speed * 0.3 + _foil_motion_speed * 0.12, 0.0, 1.0)
	if _dragging_pack_top:
		_apply_base_shake(pull_force)
	else:
		pack.position = _pack_start_position
		_update_pack_mouse_tilt(delta)
	if _drag_progress >= 1.0:
		_open_pack_from_drag()


func _update_pack_mouse_tilt(delta: float) -> void:
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d()
	if camera == null:
		return
	var center := pack_mesh.to_global(pack_mesh.get_aabb().get_center())
	if camera.is_position_behind(center):
		return
	var half_size := (viewport.get_visible_rect().size * 0.5).max(Vector2.ONE)
	var offset := (viewport.get_mouse_position() - camera.unproject_position(center)) / half_size
	offset = offset.clamp(Vector2(-1.0, -1.0), Vector2.ONE)
	var angle := deg_to_rad(pack_mouse_tilt_degrees)
	# Follow screen directions even when the shop or camera is rotated.
	var camera_basis := pack.get_parent_node_3d().global_basis.orthonormalized().inverse() * camera.global_basis.orthonormalized()
	var tilt := Basis(camera_basis.y, offset.x * angle) * Basis(camera_basis.x, offset.y * angle)
	var target := (tilt * Basis.from_euler(_pack_home_rotation * (PI / 180.0))).get_rotation_quaternion()
	pack.quaternion = pack.quaternion.slerp(target, 1.0 - exp(-pack_mouse_follow_speed * delta))


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
		_update_pack_top_drag(event.position)
		get_viewport().set_input_as_handled()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_release_pack_top_drag()
		get_viewport().set_input_as_handled()


func _on_pack_top_input(
	camera: Node,
	event: InputEvent,
	_position: Vector3,
	_normal: Vector3,
	_shape_idx: int
) -> void:
	if _opened or _pack_transitioning:
		return
		
	if not _pack_bought:
		info_label.text = "Erst ein Pack kaufen"
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_begin_pack_top_drag(event.position, camera as Camera3D)
		get_viewport().set_input_as_handled()


func _begin_pack_top_drag(mouse_position: Vector2, camera: Camera3D = null) -> void:
	if _opened or not _pack_bought or _pack_transitioning or _dragging_pack_top:
		return
	if camera == null:
		camera = get_viewport().get_camera_3d()
	_drag_screen_axis = Vector2.RIGHT
	var viewport_size := get_viewport().get_visible_rect().size
	_drag_screen_distance = drag_open_distance * clampf(viewport_size.y / 720.0, 0.6, 2.0)
	if camera != null:
		var left := _foil_rest_bounds.get_center()
		left.x = _foil_rest_bounds.position.x
		var right := left
		right.x = _foil_rest_bounds.end.x
		var projected_width := camera.unproject_position(pack_top.to_global(right)) - camera.unproject_position(pack_top.to_global(left))
		if projected_width.length() > 12.0:
			_drag_screen_axis = projected_width.normalized()
			_drag_screen_distance = clampf(projected_width.length() * 1.45, _drag_screen_distance * 0.65, viewport_size.x * 0.65)
	_dragging_pack_top = true
	_drag_start_mouse_pos = mouse_position
	_last_drag_mouse_pos = mouse_position
	_last_drag_time_usec = Time.get_ticks_usec()
	_drag_start_progress = _drag_progress
	_pull_target_progress = _drag_progress
	_foil_lift_target = 0.45
	_pack_start_position = pack.position
	_pack_start_rotation = pack.rotation_degrees
	_pack_top_start_position = pack_top.position
	_pack_top_start_rotation = pack_top.rotation_degrees
	info_label.text = "Peel the foil to the right" if _drag_screen_axis.x >= 0.0 else "Peel the foil to the left"


func _update_pack_top_drag(mouse_position: Vector2) -> void:
	if not _dragging_pack_top or _opened:
		return
	var drag_delta := mouse_position - _drag_start_mouse_pos
	var pull_distance := maxf(drag_delta.dot(_drag_screen_axis) - rip_grab_slack_pixels, 0.0)
	var remaining := maxf(1.0 - _drag_start_progress, 0.001)
	var pull := clampf(pull_distance / maxf(_drag_screen_distance * remaining, 1.0), 0.0, 1.0)
	# A torn seam cannot reseal when the cursor moves backwards.
	_pull_target_progress = maxf(_drag_progress, _drag_start_progress + remaining * pow(pull, rip_resistance_curve))
	var up_axis := Vector2(_drag_screen_axis.y, -_drag_screen_axis.x)
	if up_axis.y > 0.0:
		up_axis = -up_axis
	_foil_lift_target = clampf(0.45 + drag_delta.dot(up_axis) / maxf(_drag_screen_distance, 1.0) * 1.8, 0.08, 1.0)
	var now := Time.get_ticks_usec()
	var elapsed := maxf(float(now - _last_drag_time_usec) / 1000000.0, 1.0 / 240.0)
	_foil_motion_speed = clampf(mouse_position.distance_to(_last_drag_mouse_pos) / maxf(_drag_screen_distance * elapsed, 1.0), 0.0, 3.0)
	_last_drag_mouse_pos = mouse_position
	_last_drag_time_usec = now
	if _pull_target_progress >= 0.9:
		info_label.text = "Noch ein Stück – die Naht gibt nach"


func _release_pack_top_drag() -> void:
	if not _dragging_pack_top:
		return
	_dragging_pack_top = false
	_foil_lift_target = 0.0
	_foil_motion_speed = 0.0
	if _foil_audio != null:
		_foil_audio.set_motion(0.0, 0.0)
	if _pull_target_progress >= 1.0:
		_drag_progress = 1.0
		_open_pack_from_drag()
	else:
		_pull_target_progress = _drag_progress
		info_label.text = "Folie wieder greifen und weiter abziehen" if _drag_progress > 0.0 else "Folienrand greifen und seitlich abziehen"


func _on_pack_focus_lost() -> void:
	# Losing focus releases the grip without completing a delayed mouse pull.
	_pull_target_progress = _drag_progress
	_release_pack_top_drag()
	if _foil_audio != null:
		_foil_audio.stop()

func _open_pack_from_drag() -> void:
	if _opened or not _pack_bought or _pack_transitioning or _drag_progress < 1.0:
		return
	_opened = true
	_hovering_pack = false
	_dragging_pack_top = false
	info_label.text = "Pack wird geöffnet..."

	_set_foil_input_enabled(false)
	if _foil_audio != null:
		_foil_audio.play_tear()
	var generation := _pack_generation
	var released_top := pack_top
	var start_position := pack_top.position
	var start_rotation := pack_top.rotation_degrees
	_foil_flight_tween = create_tween()
	# Keep the sheet's size and curled shape; it tumbles under gravity rather
	# than shrinking into a disappearing rigid lid.
	_foil_flight_tween.tween_method(func(time: float):
		if generation != _pack_generation or not is_instance_valid(released_top):
			return
		released_top.position = start_position + pack_top_throw_velocity * time + Vector3.DOWN * pack_top_throw_gravity * 0.5 * time * time
		released_top.rotation_degrees = start_rotation + Vector3(45.0, -30.0, -105.0) * time
	, 0.0, pack_top_throw_duration, pack_top_throw_duration)
	_foil_flight_tween.tween_callback(func():
		if generation == _pack_generation and is_instance_valid(released_top):
			released_top.hide()
	)
	_pack_motion_tween = create_tween().set_parallel(true)
	_pack_motion_tween.tween_property(pack, "position", _pack_home_position + pack_body_open_position, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_pack_motion_tween.tween_property(pack, "rotation_degrees", _pack_home_rotation, 0.25)
	_trigger_camera_shake(0.05, 0.14)

	await get_tree().create_timer(0.45).timeout

	if generation != _pack_generation or not _pack_bought or not _opened:
		return
	_pack_effect_base_position = pack.position
	_spawn_cards_inside_pack()


func _spawn_cards_inside_pack() -> void:
	var generation := _pack_generation
	_clear_old_cards()

	if CardDatabase.cards.is_empty():
		info_label.text = "Keine Karten gefunden"
		return

	var rolled_card_ids: Array[String] = []
	for i in range(card_count):
		var data: Dictionary = CardDatabase.get_random_card_for_current_pack(rolled_card_ids)
		if data.is_empty():
			continue
		rolled_card_ids.append(str(data.get("id", "")))
		var instance := CollectionManager.roll_card_instance(str(data.get("id", "")))
		data = CardData.with_instance_metadata(data, instance)

		var card := CARD_SCENE.instantiate() as Card3D
		cards_root.add_child(card)
		card.set_meta("collection_instance", instance)
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
	if generation != _pack_generation:
		return

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
	if not is_instance_valid(card) or not _card_stack.has(card):
		return
	_disconnect_top_card()

	var card_id := str(card.card_data.get("id", ""))
	var card_name := str(card.card_data.get("name", card_id))
	var rarity_id := str(card.card_data.get("rarity", "common"))
	var rarity_data := RarityEffectsData.get_data(rarity_id)

	if card_id != "":
		# Acquisitions are saved when collecting the pack. Pending IDs also
		# count as seen so only the first revealed copy gets the NEW label.
		card.set_meta("new_discovery", not CollectionManager.has_discovered_card(card_id) and not _pending_collection_card_ids.has(card_id))
		_pending_collection_card_ids.append(card_id)
		_pending_collection_instances.append((card.get_meta("collection_instance", {}) as Dictionary).duplicate(true))

	info_label.text = Localization.format_text("Drew %s", [Localization.localized_arg(card_name)])
	_play_card_draw_sound(card)

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
	_connect_revealed_effect_overview(card)

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
	var sound_key := str(RarityEffectsData.get_data(rarity_id).get("sound_key", "reveal_" + rarity_id))
	var path := RARITY_SOUND_PATH % sound_key.trim_prefix("reveal_")

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
	if not _collecting_cards and _revealed_cards.has(card) and card.get_meta("new_discovery", false) and not card.has_node("NewLabel"):
		# A billboard would be visible through the flip while the back faces us.
		# Attach it only once the new card has finished turning face-up.
		var label := NEW_CARD_LABEL.new()
		label.name = "NewLabel"
		card.add_child(label)


func _connect_revealed_hover(card: Card3D) -> void:
	if not is_instance_valid(card) or not card.area:
		return

	_connect_revealed_effect_overview(card)

	var hover_started := _on_revealed_card_hover_start.bind(card)
	var hover_ended := _on_revealed_card_hover_end.bind(card)
	if not card.area.mouse_entered.is_connected(hover_started):
		card.area.mouse_entered.connect(hover_started)

	if not card.area.mouse_exited.is_connected(hover_ended):
		card.area.mouse_exited.connect(hover_ended)


func _disconnect_revealed_hover(card: Card3D) -> void:
	if not is_instance_valid(card) or not card.area:
		return

	var hover_started := _on_revealed_card_hover_start.bind(card)
	var hover_ended := _on_revealed_card_hover_end.bind(card)
	if card.area.mouse_entered.is_connected(hover_started):
		card.area.mouse_entered.disconnect(hover_started)

	if card.area.mouse_exited.is_connected(hover_ended):
		card.area.mouse_exited.disconnect(hover_ended)

	if card.card_hovered.is_connected(_on_revealed_effect_card_hovered):
		card.card_hovered.disconnect(_on_revealed_effect_card_hovered)

	if card.card_unhovered.is_connected(_on_revealed_effect_card_unhovered):
		card.card_unhovered.disconnect(_on_revealed_effect_card_unhovered)


func _connect_revealed_effect_overview(card: Card3D) -> void:
	if not is_instance_valid(card):
		return

	if not card.card_hovered.is_connected(_on_revealed_effect_card_hovered):
		card.card_hovered.connect(_on_revealed_effect_card_hovered)

	if not card.card_unhovered.is_connected(_on_revealed_effect_card_unhovered):
		card.card_unhovered.connect(_on_revealed_effect_card_unhovered)


func _ensure_effect_overview() -> void:
	if _effect_overview != null and is_instance_valid(_effect_overview):
		return

	_effect_overview_layer = CanvasLayer.new()
	_effect_overview_layer.name = "EffectOverviewLayer"
	_effect_overview_layer.layer = 40
	add_child(_effect_overview_layer)

	_effect_overview = EFFECT_OVERVIEW_SCENE.instantiate() as CardEffectOverviewUI
	_effect_overview_layer.add_child(_effect_overview)


func _on_revealed_effect_card_hovered(card: Card3D) -> void:
	if CardData.get_active_effects(card.card_data).is_empty():
		return
	_ensure_effect_overview()
	if _effect_overview != null:
		_effect_overview.show_for_card(card)


func _on_revealed_effect_card_unhovered(card: Card3D) -> void:
	if _effect_overview != null:
		_effect_overview.hide_overview(card)


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
	if _effect_overview != null:
		_effect_overview.hide_overview()

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

	pack.position = _pack_start_position + Vector3(shake_x - amount * 0.025, shake_y, shake_z)

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
	if _effect_overview != null:
		_effect_overview.hide_overview()
	info_label.text = "Karten werden gesammelt..."

	var target_pos := global_position + Vector3(0, 1.2, -0.8)

	if cards_fly_target:
		target_pos = cards_fly_target.global_position

	var result := CollectionManager.add_card_instances(_pending_collection_instances)
	if not result["success"]:
		_collecting_cards = false
		_waiting_for_collect_click = true
		info_label.text = "Speichern fehlgeschlagen – zum Wiederholen klicken"
		return

	if collection_screen and collection_screen.has_method("refresh_collection"):
		collection_screen.refresh_collection()
		
	_refresh_upgrade_ui()

	var tween := create_tween().set_parallel(true)

	for i in range(_revealed_cards.size()):
		var card := _revealed_cards[i]
		if not is_instance_valid(card):
			continue

		_disconnect_revealed_hover(card)
		var new_label := card.get_node_or_null("NewLabel") as Sprite3D
		if new_label != null:
			new_label.hide()

		var delay := i * 0.045

		tween.tween_property(card, "global_position", target_pos, cards_fly_duration) \
			.set_delay(delay) \
			.set_trans(Tween.TRANS_CUBIC) \
			.set_ease(Tween.EASE_IN)

		tween.tween_property(card, "rotation_degrees", card.rotation_degrees + Vector3(0, 180, 25), cards_fly_duration) \
			.set_delay(delay)

		tween.tween_property(card, "scale", Vector3.ONE * 0.001, cards_vanish_duration) \
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
	_pending_collection_instances.clear()
	_top_revealed_card = null

	await _reset_pack_for_next_opening()
	_collecting_cards = false


func _reset_pack_for_next_opening() -> void:
	_invalidate_pack_motion()
	var generation := _pack_generation
	_pack_transitioning = true
	_set_foil_input_enabled(false)
	var hidden_pos := _pack_home_position + pack_hidden_offset
	_pack_motion_tween = create_tween().set_parallel(true)

	_pack_motion_tween.tween_property(
		pack,
		"position",
		hidden_pos,
		pack_disappear_duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

	_pack_motion_tween.tween_property(
		pack,
		"scale",
		_pack_home_scale * 0.15,
		pack_disappear_duration
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

	await _pack_motion_tween.finished
	if generation != _pack_generation:
		return

	pack.visible = false
	pack_top.visible = false

	pack.position = _pack_home_position
	pack.rotation_degrees = _pack_home_rotation
	pack.scale = _pack_home_scale

	pack_top.position = _pack_top_home_position
	pack_top.rotation_degrees = _pack_top_home_rotation
	pack_top.scale = _pack_top_home_scale

	_opened = false
	_reset_foil_state()
	_waiting_for_collect_click = false
	_pack_bought = false
	_pack_transitioning = false
	_hovering_pack = false
	_pack_effect_base_position = _pack_home_position
	_pack_start_position = _pack_home_position
	_pack_start_rotation = _pack_home_rotation

	if _pack_batch_current < _pack_batch_total:
		if GameCurrency.consume_queued_pack(_pack_reservation):
			_pack_batch_current += 1
			_present_purchased_pack()
			return
		# A failed save must not hand out a pack that is still marked refundable.
		# Retain any failed refund in the wallet for recovery on the next load.
		GameCurrency.refund_queued_packs(_pack_reservation)
		info_label.text = "Öffnung unterbrochen – übrige Packs werden erstattet"
	else:
		info_label.text = "Neues Pack kaufen"
	_pack_batch_total = 0
	_pack_batch_current = 0
	_pack_reservation = 0
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

func buy_pack(pack_id: String, pack_data: Dictionary, quantity: int = 1) -> bool:
	if _purchase_in_progress or _pack_bought or _pack_transitioning or _opened or _dragging_pack_top or _collecting_cards:
		return false
	if quantity < 1:
		return false
	if quantity > 1 and GameCurrency.get_level() < 2:
		info_label.text = "Mehrere Packs sind ab Level 2 verfügbar"
		return false
	# Check the catalog here as well as in the shop: direct callers cannot
	# bypass progression by omitting or changing the supplied pack metadata.
	if not PackDefinition.is_unlocked(pack_id, GameCurrency.get_level()):
		info_label.text = PackDefinition.get_unlock_message(pack_id)
		return false
	# A Secret-only exhausted catalog cannot guarantee a complete paid pack.
	# Keep its rarity gate intact and reject before any reservation or debit.
	if not CardDatabase.has_regular_pack_rewards():
		info_label.text = "Keine Karten verfügbar"
		return false

	var unit_price := PackDefinition.get_price(pack_id, pack_data)
	if not is_finite(unit_price) or unit_price <= 0.0 or unit_price > GameCurrency.coins:
		info_label.text = "Nicht genug Soul Coins"
		return false
	var cost_cents := roundi(unit_price * GameCurrency.CENTS_PER_COIN)
	# Wallet signals are synchronous. Lock before payment to reject a second
	# purchase submitted by a balance listener during the original transaction.
	_purchase_in_progress = true
	var reservation := GameCurrency.begin_pack_purchase(cost_cents, quantity)
	if reservation == 0:
		_purchase_in_progress = false
		info_label.text = "Kauf nicht möglich – Guthaben und Speicher prüfen"
		return false

	selected_pack_id = pack_id
	selected_pack_data = pack_data.duplicate(true)
	_pack_batch_total = quantity
	_pack_batch_current = 1
	_pack_reservation = reservation
	_pack_bought = true
	pack_opening_started.emit()
	_present_purchased_pack()
	_purchase_in_progress = false
	return true


func _present_purchased_pack() -> void:
	CardDatabase.set_pack_rarity_weights(
		selected_pack_data.get("rarity_weights", {})
	)
	card_count = int(selected_pack_data.get("card_count", card_count))
	_pack_bought = true
	var progress := " (%d/%d)" % [_pack_batch_current, _pack_batch_total] if _pack_batch_total > 1 else ""
	info_label.text = Localization.format_text("%s%s — Grab the top foil and peel", [Localization.localized_arg(str(selected_pack_data.get("name", "Pack"))), progress])
	var pack_scene := selected_pack_data.get("scene", null) as PackedScene
	_set_pack_model(pack_scene)
	_show_bought_pack()
	pack_batch_progress.emit(_pack_batch_current, _pack_batch_total)
	
func _hide_pack_until_bought() -> void:
	pack.visible = false
	pack_top.visible = false
	_set_foil_input_enabled(false)

func _show_bought_pack() -> void:
	_invalidate_pack_motion()
	var generation := _pack_generation
	_reset_foil_state()
	_pack_transitioning = true
	_set_foil_input_enabled(false)
	pack.visible = true
	pack_top.visible = true

	var start_pos := _pack_home_position + pack_hidden_offset

	pack.position = start_pos
	pack.rotation_degrees = _pack_home_rotation
	# Keep transforms invertible while ray-picking and camera projection run.
	pack.scale = _pack_home_scale * 0.001

	pack_top.position = _pack_top_home_position
	pack_top.rotation_degrees = _pack_top_home_rotation
	pack_top.scale = _pack_top_home_scale

	_pack_motion_tween = create_tween().set_parallel(true)

	_pack_motion_tween.tween_property(
		pack,
		"position",
		_pack_home_position,
		pack_appear_duration
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_pack_motion_tween.tween_property(
		pack,
		"scale",
		_pack_home_scale,
		pack_appear_duration
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pack_motion_tween.chain().tween_callback(func() -> void:
		if generation != _pack_generation:
			return
		_pack_start_position = _pack_home_position
		_pack_start_rotation = _pack_home_rotation
		_pack_effect_base_position = _pack_home_position
		_pack_transitioning = false
		_set_foil_input_enabled(true)
	)


func _set_pack_model(pack_scene: PackedScene) -> void:
	if pack_scene == null:
		return

	_invalidate_pack_motion()
	var old_pack := pack
	var old_index := pack.get_index()

	remove_child(old_pack)
	old_pack.queue_free()

	pack = pack_scene.instantiate() as Node3D
	pack.name = "pack"
	add_child(pack)
	move_child(pack, old_index)
	pack.position = _pack_home_position
	pack.rotation_degrees = _pack_home_rotation
	pack.scale = _pack_home_scale

	pack_mesh = pack.get_node_or_null("base") as MeshInstance3D
	pack_top = pack.get_node_or_null("top") as MeshInstance3D
	rarity_particle_spawn = pack.get_node_or_null("RarityParticleSpawn") as Marker3D

	if rarity_particle_spawn == null:
		rarity_particle_spawn = Marker3D.new()
		rarity_particle_spawn.name = "RarityParticleSpawn"
		pack.add_child(rarity_particle_spawn)
		rarity_particle_spawn.position = rarity_particle_spawn_offset

	_pack_top_home_position = pack_top.position
	_pack_top_home_rotation = pack_top.rotation_degrees
	_pack_top_home_scale = pack_top.scale
	_setup_foil()
	_ensure_pack_top_area()
	
func _ensure_pack_top_area() -> void:
	if pack_top == null:
		push_error("Pack hat keinen Node namens 'top'")
		return

	pack_top_area = pack_top.get_node_or_null("PackTopArea") as Area3D

	if pack_top_area == null:
		pack_top_area = Area3D.new()
		pack_top_area.name = "PackTopArea"
		pack_top.add_child(pack_top_area)

	var collision := pack_top_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null:
		collision = CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		pack_top_area.add_child(collision)
	# The hitbox follows this pack's foil without editing a shared imported shape.
	collision.shape = BoxShape3D.new()
	_update_foil_grab_shape()
	_set_foil_input_enabled(_pack_bought and not _pack_transitioning and not _opened)

	if not pack_top_area.input_event.is_connected(_on_pack_top_input):
		pack_top_area.input_event.connect(_on_pack_top_input)

	if not pack_top_area.mouse_entered.is_connected(_on_pack_mouse_entered):
		pack_top_area.mouse_entered.connect(_on_pack_mouse_entered)

	if not pack_top_area.mouse_exited.is_connected(_on_pack_mouse_exited):
		pack_top_area.mouse_exited.connect(_on_pack_mouse_exited)


func _set_foil_input_enabled(enabled: bool) -> void:
	if not is_instance_valid(pack_top_area):
		return
	pack_top_area.input_ray_pickable = enabled
	pack_top_area.set_meta("keep_input_ray_pickable_disabled", not enabled)
	pack_top_area.set_deferred("monitoring", enabled)
	pack_top_area.set_deferred("monitorable", enabled)


func _invalidate_pack_motion() -> void:
	_pack_generation += 1
	if _pack_motion_tween != null and _pack_motion_tween.is_valid():
		_pack_motion_tween.kill()
	if _foil_flight_tween != null and _foil_flight_tween.is_valid():
		_foil_flight_tween.kill()
	_pack_effect_shake_strength = 0.0
	_pack_effect_shake_time_left = 0.0
	if is_instance_valid(cards_root):
		cards_root.position = _cards_effect_base_position
	if _foil_audio != null:
		_foil_audio.stop()
		
func _on_pack_mouse_entered() -> void:
	_hovering_pack = true


func _on_pack_mouse_exited() -> void:
	_hovering_pack = false

func _play_card_draw_sound(card: Card3D) -> void:
	if card == null or not is_instance_valid(card):
		return

	var card_id := str(card.card_data.get("id", card.card_data.get("card_id", "")))

	if card_id == "":
		return

	var sound_path := "res://assets/sounds/SFX/cards/" + card_id + ".ogg"

	if not ResourceLoader.exists(sound_path):
		return

	var player := AudioStreamPlayer3D.new()
	player.bus = "SFX"
	player.stream = load(sound_path)
	add_child(player)
	player.global_position = card.global_position

	player.play()
	player.finished.connect(player.queue_free)
