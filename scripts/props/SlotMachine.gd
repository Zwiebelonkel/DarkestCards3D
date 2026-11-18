extends Node3D
class_name SoulSlotMachine

signal spin_started(stake_cents: int)
signal spin_finished(result: Array[int], payout_cents: int)

const BETS: Array[int] = [100, 200, 500, 1000, 2000, 5000]
const BET_STEP_CENTS := 1000
const COLOR_NAMES: Array[String] = ["GRÜN", "ROT", "BLAU", "GOLD", "VIOLETT"]
const COLOR_TINTS: Array[Color] = [Color("69ed4b"), Color("ff5c65"), Color("639dff"), Color("ffcb50"), Color("ee75ff")]
const SYMBOL_NAMES: Array[String] = ["HEILUNG", "LEBENSRAUB", "SCHILD", "DREIFACHSCHLAG", "FLUCH"]
const SYMBOL_TEXTURES: Array[Texture2D] = [
	preload("res://assets/effects/regeneration.png"),
	preload("res://assets/effects/lifesteal.png"),
	preload("res://assets/effects/shield_first_hit.png"),
	preload("res://assets/effects/triple_strike.png"),
	preload("res://assets/effects/curse.png"),
]
const MULTIPLIERS: Array[int] = [5, 10, 15, 35, 55]
# The five actual colored faces of the imported pentagonal cylinders.
const STOP_ANGLES: Array[float] = [0.0, -72.0, -144.0, -216.0, -288.0]
const BUTTON_NAMES := {"increase": "erhöhen", "decrease": "verringern", "bet": "setzen", "spin": "spin"}
const FONT := preload("res://fonts/VCR_OSD_MONO_1.001.ttf")
const CLICK_SOUND := preload("res://assets/sounds/SFX/button.mp3")
const SPIN_SOUND := preload("res://assets/sounds/SFX/spin.mp3")
const ROLLING_SOUND := preload("res://assets/sounds/SFX/rolling.mp3")
# The recording is already quiet. Extra gain reduction plus 3D attenuation
# buried it under the reel clicks at the player's normal viewing distance.
const ROLLING_VOLUME_DB := 0.0
const ROLLING_END_VOLUME_DB := -55.0
const ROLLING_END_PITCH := 0.4
const SPIN_CLICK_ANGLE := TAU / 5.0
const WIN_SOUND := preload("res://assets/sounds/SFX/rare.mp3")
const REWARD_EFFECT := preload("res://scripts/ui/RewardRevealEffect.gd")
const BUTTON_BLINK_PERIOD := 0.8

@export var interaction_enabled := true
@export_range(0.1, 8.0, 0.1) var spin_duration := 2.3
@export_range(0.01, 1.0, 0.01) var reel_stop_delay := 0.38

var selected_bet_index := 0
var committed_bet_cents := 0
var is_spinning := false
var last_result: Array[int] = []
var last_payout_cents := 0
var button_areas: Dictionary = {}
var reel_pivots: Array[Node3D] = []
var _reel_angles: Array[float] = [0.0, 0.0, 0.0]
var _button_meshes: Dictionary = {}
var _button_materials: Dictionary = {}
var _button_rest_positions: Dictionary = {}
var _button_tweens: Dictionary = {}
var _spin_tweens: Array[Tween] = []
var _rng := RandomNumberGenerator.new()
var _hovered_action := ""
var _button_blink_elapsed := 0.0
var _blinking_action := ""
var _owns_pending_spin := false
var _spin_generation := 0
var _status_text := ""
var _status_color := Color("ded6b2")
var _credit_label: Label3D
var _bet_label: Label3D
var _status_label: Label3D
var _result_label: Label3D
var _click_audio: AudioStreamPlayer3D
var _spin_audio: AudioStreamPlayer3D
var _rolling_audio: AudioStreamPlayer3D
var _rolling_tail_tween: Tween
var _spin_next_click_angle := 0.0
var _stop_audio: AudioStreamPlayer3D
var _win_audio: AudioStreamPlayer3D
var _win_effect: RewardRevealEffect
var _model_text: LocalizedModelText
var _jackpot_elapsed := 0.0


func _ready() -> void:
	_rng.randomize()
	_recover_orphaned_spin()
	_prepare_model()
	_model_text = LocalizedModelText.attach_slot_model($Model/slots)
	_build_display()
	_build_audio()
	Localization.locale_changed.connect(_refresh_display)
	_win_effect = REWARD_EFFECT.new()
	_win_effect.name = "RewardReveal"
	_win_effect.position = Vector3(-0.11, 1.468, 0.38)
	add_child(_win_effect)
	GameCurrency.coins_changed.connect(_on_coins_changed)
	visibility_changed.connect(_refresh_buttons)
	_refresh_display()
	_refresh_buttons()


func set_interaction_enabled(enabled: bool) -> void:
	if interaction_enabled == enabled:
		return
	interaction_enabled = enabled
	if not enabled:
		_set_hover("")
		if is_instance_valid(_win_effect):
			_win_effect.cancel()
	if is_node_ready():
		_refresh_buttons()


func _can_interact() -> bool:
	return interaction_enabled and is_visible_in_tree() and is_inside_tree() and not get_tree().paused


func _can_present_win_effect() -> bool:
	if not _can_interact() or not is_instance_valid(_win_effect):
		return false
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.is_position_behind(_win_effect.global_position):
		return false
	if global_basis.z.normalized().dot(camera.global_position - _win_effect.global_position) <= 0.0:
		return false
	return get_viewport().get_visible_rect().has_point(camera.unproject_position(_win_effect.global_position))


func choose_bet(direction: int) -> bool:
	if not _can_interact() or is_spinning or _owns_pending_spin or direction == 0:
		return false
	var next := maxi(selected_bet_index + signi(direction), 0)
	if next == selected_bet_index:
		return false
	selected_bet_index = next
	committed_bet_cents = 0
	_set_status("")
	_refresh_display()
	_refresh_buttons()
	return true


func get_selected_bet_cents() -> int:
	if selected_bet_index < BETS.size():
		return BETS[selected_bet_index]
	return BETS[-1] + (selected_bet_index - BETS.size() + 1) * BET_STEP_CENTS


func confirm_bet() -> bool:
	if not _can_interact() or is_spinning or _owns_pending_spin:
		return false
	if GameCurrency.get_coin_cents() < get_selected_bet_cents():
		_set_status("Nicht genug Soul Coins", Color("ff8178"))
		return false
	committed_bet_cents = get_selected_bet_cents()
	_set_status("")
	_refresh_display()
	_refresh_buttons()
	return true


func start_spin() -> bool:
	if not _can_interact() or is_spinning:
		return false
	if _owns_pending_spin:
		_finish_spin(_spin_generation)
		return false
	_recover_orphaned_spin()
	if committed_bet_cents <= 0:
		_set_status("")
		_refresh_buttons()
		return false
	if GameCurrency.get_coin_cents() < committed_bet_cents:
		_set_status("Nicht genug Soul Coins", Color("ff8178"))
		return false
	var result := _draw_result()
	var payout := payout_for(result, committed_bet_cents)
	# Acquire the input lock before currency signals can re-enter this method.
	is_spinning = true
	if not GameCurrency.begin_slot_spin(committed_bet_cents, payout):
		is_spinning = false
		_owns_pending_spin = false
		_set_status("Einsatz konnte nicht gebucht werden", Color("ff8178"))
		_refresh_buttons()
		return false
	_owns_pending_spin = true
	_win_effect.cancel()
	GameCurrency.set_meta("slot_spin_visual_owner", weakref(self))
	_spin_generation += 1
	last_result = result
	last_payout_cents = payout
	if is_instance_valid(_result_label):
		_result_label.text = ""
		_result_label.modulate = Color("ded6b2")
	_set_status("")
	_refresh_buttons()
	_spin_audio.play()
	_start_rolling_audio()
	spin_started.emit(committed_bet_cents)
	_animate_result()
	return true


func _draw_result() -> Array[int]:
	return [_rng.randi_range(0, 4), _rng.randi_range(0, 4), _rng.randi_range(0, 4)]


static func payout_for(result: Array[int], stake_cents: int) -> int:
	if stake_cents <= 0 or result.size() != 3:
		return 0
	var color := result[0]
	if color < 0 or color >= MULTIPLIERS.size() or result[1] != color or result[2] != color:
		return 0
	return stake_cents * MULTIPLIERS[color]


func _animate_result() -> void:
	_spin_tweens.clear()
	_spin_next_click_angle = _reel_angles.back() + SPIN_CLICK_ANGLE
	for index in range(3):
		var start := _reel_angles[index]
		var stop := deg_to_rad(STOP_ANGLES[last_result[index]])
		var end := start + TAU * (5 + index) + fposmod(stop - start, TAU)
		var tween := create_tween()
		_spin_tweens.append(tween)
		tween.tween_method(_set_reel_angle.bind(index), start, end, spin_duration + reel_stop_delay * index).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_callback(_on_reel_stopped.bind(index, _spin_generation))
		if index == 2:
			tween.tween_callback(_finish_spin.bind(_spin_generation))


func _set_reel_angle(angle: float, index: int) -> void:
	_reel_angles[index] = angle
	reel_pivots[index].rotation.x = angle
	# The final reel drives the shared ratchet: one click per symbol passing
	# the payline. Its actual eased movement naturally spaces the clicks out.
	if is_spinning and index == 2 and angle >= _spin_next_click_angle:
		_spin_audio.play()
		# Skip crossed teeth on a slow frame instead of playing a burst of
		# overdue clicks. Keep the next tooth aligned with the reel angle.
		var crossed := floori((angle - _spin_next_click_angle) / SPIN_CLICK_ANGLE) + 1
		_spin_next_click_angle += crossed * SPIN_CLICK_ANGLE


func _on_reel_stopped(index: int, generation: int) -> void:
	if generation != _spin_generation or not _owns_pending_spin:
		return
	_set_reel_angle(deg_to_rad(STOP_ANGLES[last_result[index]]), index)
	_stop_audio.pitch_scale = 0.8 + index * 0.16
	_stop_audio.play()
	if index == 0:
		_fade_rolling_audio()
	if index == 2:
		_spin_audio.stop()
		_stop_rolling_audio()


func _finish_spin(generation: int = -1) -> void:
	if not _owns_pending_spin or (generation >= 0 and generation != _spin_generation):
		return
	_spin_audio.stop()
	_stop_rolling_audio()
	if not GameCurrency.complete_slot_spin():
		is_spinning = false
		_update_jackpot_flicker(0.0)
		_set_status("Speichern fehlgeschlagen\nSPIN: Auszahlung erneut versuchen", Color("ff8178"))
		_refresh_buttons()
		return
	_owns_pending_spin = false
	GameCurrency.remove_meta("slot_spin_visual_owner")
	is_spinning = false
	_update_jackpot_flicker(0.0)
	_spin_tweens.clear()
	if last_payout_cents > 0:
		if is_instance_valid(_result_label):
			_result_label.text = ""
			_result_label.modulate = COLOR_TINTS[last_result[0]]
		_set_status("")
		_win_audio.play()
		var color := last_result[0]
		_win_effect.play_reward(color, last_payout_cents, COLOR_TINTS[color], SYMBOL_TEXTURES[color], SYMBOL_NAMES[color], MULTIPLIERS[color], _can_present_win_effect)
	else:
		if is_instance_valid(_result_label):
			_result_label.text = ""
		_set_status("")
	_refresh_display()
	_refresh_buttons()
	spin_finished.emit(last_result.duplicate(), last_payout_cents)


func _prepare_model() -> void:
	var model := $Model/slots as Node3D
	for index in range(3):
		var reel := model.find_child("spinner%d" % (index + 1), true, false) as MeshInstance3D
		var pivot := Node3D.new()
		pivot.name = "ReelPivot%d" % (index + 1)
		model.add_child(pivot)
		pivot.position = reel.position
		reel.reparent(pivot, true)
		reel_pivots.append(pivot)
		# Dark reel faces make the colored effect silhouettes readable in room light.
		for surface in range(reel.mesh.get_surface_count()):
			var material := reel.get_active_material(surface).duplicate() as StandardMaterial3D
			if surface < SYMBOL_TEXTURES.size():
				material.albedo_texture = null
				material.albedo_color = Color("10151b").lerp(COLOR_TINTS[surface], 0.035)
				material.emission_enabled = false
				material.roughness = 0.85
				_add_reel_symbol(reel, pivot, surface)
			reel.set_surface_override_material(surface, material)
		_set_reel_angle(deg_to_rad(STOP_ANGLES[index]), index)
	for action: String in BUTTON_NAMES:
		var mesh := model.find_child(BUTTON_NAMES[action], true, false) as MeshInstance3D
		_button_meshes[action] = mesh
		_button_rest_positions[action] = mesh.position
		var material := mesh.get_active_material(1).duplicate() as StandardMaterial3D
		mesh.set_surface_override_material(1, material)
		_button_materials[action] = material
		# Bake the nested non-uniform glTF transforms into a fixed machine-space
		# box. Button press animation never moves the input target.
		var relative := global_transform.affine_inverse() * mesh.global_transform
		var bounds: AABB = relative * mesh.get_aabb()
		var area := Area3D.new()
		area.name = action.capitalize() + "ButtonArea"
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = false
		add_child(area)
		area.position = bounds.get_center()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = bounds.size.max(Vector3(0.06, 0.055, 0.06))
		shape.shape = box
		area.add_child(shape)
		area.input_event.connect(_on_button_input.bind(action))
		button_areas[action] = area


func _add_reel_symbol(reel: MeshInstance3D, pivot: Node3D, surface: int) -> void:
	var arrays := reel.mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	# Bake the imported non-uniform mesh scale into the face layout, so symbols
	# stay square and upright when their face reaches the winning line.
	var normal := (reel.basis.inverse().transposed() * normals[0]).normalized()
	var right := (reel.basis * Vector3.UP).normalized()
	var up := normal.cross(right).normalized()
	var center := Vector3.ZERO
	var lower := Vector2(INF, INF)
	var upper := Vector2(-INF, -INF)
	for vertex in vertices:
		var point := reel.transform * vertex
		center += point
		var on_face := Vector2(point.dot(right), point.dot(up))
		lower = lower.min(on_face)
		upper = upper.max(on_face)
	center /= vertices.size()
	var face_size := upper - lower
	var symbol := _make_effect_symbol(pivot, "EffectSymbol%d" % surface, surface, minf(face_size.x, face_size.y) * 0.84)
	symbol.transform = Transform3D(Basis(right, up, normal), center + normal * 0.002)


func _make_effect_symbol(parent: Node3D, node_name: String, index: int, size: float) -> Sprite3D:
	var symbol := Sprite3D.new()
	symbol.name = node_name
	symbol.texture = SYMBOL_TEXTURES[index]
	symbol.modulate = COLOR_TINTS[index]
	symbol.pixel_size = size / float(symbol.texture.get_width())
	symbol.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	symbol.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	symbol.double_sided = false
	symbol.shaded = false
	symbol.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(symbol)
	return symbol


func _on_button_input(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_index: int, action: String) -> void:
	if not _can_interact() or is_spinning or not (button_areas[action] as Area3D).input_ray_pickable:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		get_viewport().set_input_as_handled()
		_press_button(action)
		match action:
			"increase": choose_bet(1)
			"decrease": choose_bet(-1)
			"bet": confirm_bet()
			"spin": start_spin()


func _process(delta: float) -> void:
	_update_jackpot_flicker(delta)
	var action := ""
	if _can_interact() and not is_spinning:
		var camera := get_viewport().get_camera_3d()
		var pointer := get_viewport().get_mouse_position()
		if camera != null and get_viewport().get_visible_rect().has_point(pointer):
			var origin := camera.project_ray_origin(pointer)
			var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(pointer) * camera.far)
			query.collide_with_areas = true
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			for key: String in button_areas:
				if hit.get("collider") == button_areas[key] and (button_areas[key] as Area3D).input_ray_pickable:
					action = key
					break
	_set_hover(action)
	_update_button_blink(delta)


func _update_jackpot_flicker(delta: float) -> void:
	if is_spinning:
		_jackpot_elapsed += delta
		# Uneven short flashes, independent of the payout RNG.
		var phase := fmod(_jackpot_elapsed, 0.46)
		var lit := phase < 0.09 or (phase > 0.15 and phase < 0.21) or phase > 0.30
		_model_text.set_jackpot_brightness(1.0 if lit else 0.16)
	else:
		_jackpot_elapsed = 0.0
		_model_text.set_jackpot_brightness(1.0)


func _notification(what: int) -> void:
	if what in [NOTIFICATION_PAUSED, NOTIFICATION_UNPAUSED] and is_node_ready():
		# The normal process loop stops immediately when Pause opens.
		_refresh_buttons()


func _set_hover(action: String) -> void:
	if action == _hovered_action:
		return
	_hovered_action = action
	_refresh_buttons()


func _refresh_buttons() -> void:
	for action: String in button_areas:
		var enabled := _can_interact() and not is_spinning
		if _owns_pending_spin and action != "spin": enabled = false
		if action == "decrease": enabled = enabled and selected_bet_index > 0
		var area := button_areas[action] as Area3D
		area.input_ray_pickable = enabled
		area.set_meta("keep_input_ray_pickable_disabled", not enabled)
		var material := _button_materials[action] as StandardMaterial3D
		material.emission_enabled = true
		material.emission = material.albedo_color
		material.emission_energy_multiplier = (1.4 if action == _hovered_action else 0.22) if enabled else 0.0
	_update_button_blink(0.0)


func _update_button_blink(delta: float) -> void:
	var can_use_buttons := _can_interact() and not is_spinning
	var next_action := ""
	if can_use_buttons and not _owns_pending_spin:
		next_action = "bet" if committed_bet_cents <= 0 else "spin"
	if next_action != _blinking_action:
		_blinking_action = next_action
		_button_blink_elapsed = 0.0
	if not _blinking_action.is_empty():
		_button_blink_elapsed = fposmod(_button_blink_elapsed + delta, BUTTON_BLINK_PERIOD)
	for action: String in ["bet", "spin"]:
		var material := _button_materials.get(action) as StandardMaterial3D
		if material == null:
			continue
		var enabled := can_use_buttons and (not _owns_pending_spin or action == "spin")
		if action == _blinking_action:
			# Switch abruptly; hover must not keep the lamp lit in the off phase.
			material.emission_energy_multiplier = 3.2 if _button_blink_elapsed < BUTTON_BLINK_PERIOD * 0.5 else 0.0
		else:
			material.emission_energy_multiplier = (1.4 if _hovered_action == action else 0.22) if enabled else 0.0


func _press_button(action: String) -> void:
	_click_audio.pitch_scale = 1.0
	_click_audio.play()
	var previous := _button_tweens.get(action) as Tween
	if previous != null:
		previous.kill()
	var mesh := _button_meshes[action] as MeshInstance3D
	var rest: Vector3 = _button_rest_positions[action]
	var tween := create_tween()
	_button_tweens[action] = tween
	tween.tween_property(mesh, "position", rest + Vector3(0, -0.25, 0), 0.055)
	tween.tween_property(mesh, "position", rest, 0.12)


func _build_display() -> void:
	_make_panel("CreditDisplay", Vector3(-0.11, 0.53, 0.31), Vector2(1.24, 0.17))
	_credit_label = _make_label("Credits", "", Vector3(-0.11, 0.53, 0.335), 0.003, 22)
	_make_panel("BetDisplay", Vector3(-0.11, 0.96, 0.37), Vector2(1.34, 0.25))
	_bet_label = _make_label("BetAmount", "", Vector3(-0.11, 1.015, 0.39), 0.003, 26, Color("f6d887"))
	_status_label = _make_label("Status", "", Vector3(-0.11, 0.905, 0.39), 0.002, 22)
	_result_label = _make_label("Result", "", Vector3(-0.11, 1.925, 0.305), 0.0028, 20)
	# A fixed line marks the exact face read for payout, independent of camera tilt.
	_make_label("PaylineLeft", "▶", Vector3(-0.99, 1.468, 0.325), 0.0016, 28, Color("ffcb50"))
	_make_label("PaylineRight", "◀", Vector3(0.77, 1.468, 0.325), 0.0016, 28, Color("ffcb50"))
	_make_panel("PayoutTable", Vector3(1.27, 1.60, 0.30), Vector2(0.94, 1.43))
	_make_label("PayoutTitle", "GEWINNTABELLE", Vector3(1.27, 2.18, 0.33), 0.0026, 28, Color("f6d887"))
	for index in range(COLOR_NAMES.size()):
		var row_y := 1.88 - 0.16 * index
		var symbol := _make_effect_symbol(self, "PayoutSymbol%d" % index, index, 0.11)
		symbol.position = Vector3(0.90, row_y, 0.33)
		_make_label("PayoutRow%d" % index, Localization.format_text("%s  ×%d", [Localization.localized_arg(SYMBOL_NAMES[index]), MULTIPLIERS[index]]), Vector3(1.36, row_y, 0.33), 0.0024, 20, COLOR_TINTS[index])


func _make_panel(node_name: String, center: Vector3, panel_size: Vector2) -> void:
	var panel := MeshInstance3D.new()
	panel.name = node_name
	var box := BoxMesh.new()
	box.size = Vector3(panel_size.x, panel_size.y, 0.035)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("121b18")
	material.roughness = 0.75
	material.emission_enabled = true
	material.emission = Color("101814")
	material.emission_energy_multiplier = 0.4
	box.material = material
	panel.mesh = box
	panel.position = center
	add_child(panel)


func _make_label(node_name: String, text: String, at: Vector3, pixel_size: float, font_size: int, color: Color = Color("ded6b2")) -> Label3D:
	var label := Label3D.new()
	label.name = node_name
	label.text = text
	label.font = FONT
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 3
	label.outline_modulate = Color("070b09")
	label.position = at
	label.no_depth_test = false
	label.shaded = false
	add_child(label)
	var available_width := 0.0
	if node_name == "PayoutTitle":
		available_width = 0.85
	elif node_name.begins_with("PayoutRow"):
		available_width = 0.67
	if available_width > 0.0:
		Localization.fit_text_3d(label, available_width)
	return label


func _build_audio() -> void:
	_click_audio = _make_audio("ButtonClick", CLICK_SOUND, -13.0)
	var spin_stream := SPIN_SOUND.duplicate() as AudioStreamMP3
	spin_stream.loop = false
	_spin_audio = _make_audio("SpinSound", spin_stream, -13.0)
	_spin_audio.max_polyphony = 4
	# Only this machine's private stream loops; keep the imported source intact.
	var rolling_stream := ROLLING_SOUND.duplicate() as AudioStreamMP3
	rolling_stream.loop = true
	_rolling_audio = _make_audio("RollingSound", rolling_stream, ROLLING_VOLUME_DB)
	_stop_audio = _make_audio("ReelStop", CLICK_SOUND, -10.0)
	_win_audio = _make_audio("WinSound", WIN_SOUND, -15.0)


func _start_rolling_audio() -> void:
	_stop_rolling_audio()
	_rolling_audio.pitch_scale = 1.0
	_rolling_audio.volume_db = ROLLING_VOLUME_DB
	_rolling_audio.play()


func _fade_rolling_audio() -> void:
	if not _rolling_audio.playing:
		return
	# The first visible result starts the slowdown. The last reel's stop owns
	# final silence, including failed payouts and short test/custom spins.
	var tail_duration := maxf(reel_stop_delay * 2.0, 0.01)
	_rolling_tail_tween = create_tween().set_parallel(true)
	_rolling_tail_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_rolling_tail_tween.tween_property(_rolling_audio, "pitch_scale", ROLLING_END_PITCH, tail_duration)
	_rolling_tail_tween.tween_property(_rolling_audio, "volume_db", ROLLING_END_VOLUME_DB, tail_duration)


func _stop_rolling_audio() -> void:
	if _rolling_tail_tween != null and _rolling_tail_tween.is_valid():
		_rolling_tail_tween.kill()
	_rolling_tail_tween = null
	if is_instance_valid(_rolling_audio):
		_rolling_audio.stop()


func _make_audio(node_name: String, stream: AudioStream, volume: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = node_name
	player.stream = stream
	player.volume_db = volume
	player.unit_size = 4.0
	player.max_distance = 20.0
	# Keep the machine's clicks and rewards crisp; room muffling belongs
	# exclusively to Main's music bus, not the 3D players' distance filter.
	player.attenuation_filter_cutoff_hz = 20500.0
	player.attenuation_filter_db = 0.0
	player.position = Vector3(0, 1.5, 0)
	if AudioServer.get_bus_index("SFX") >= 0:
		player.bus = "SFX"
	add_child(player)
	return player


func _set_status(message: String, color: Color = Color("ded6b2")) -> void:
	_status_text = message
	_status_color = color
	if _status_label != null:
		_status_label.text = message
		_status_label.modulate = color
		Localization.fit_text_3d(_status_label, 1.24, 0.095)


func _refresh_display() -> void:
	_credit_label.text = Localization.format_text("SOUL COINS  %s", [GameCurrency.format_coins()])
	_bet_label.text = Localization.format_text("EINSATZ  %s SC", [_format_cents(get_selected_bet_cents())])
	Localization.fit_text_3d(_credit_label, 1.14, 0.13)
	Localization.fit_text_3d(_bet_label, 1.24, 0.14)
	_set_status(_status_text, _status_color)


func _on_coins_changed(_coins: float) -> void:
	_refresh_display()


static func _format_cents(cents: int) -> String:
	return Localization.decimal(float(cents) / 100.0)


func _recover_orphaned_spin() -> void:
	if not GameCurrency.has_pending_slot_spin():
		return
	var owner_ref: WeakRef = null
	if GameCurrency.has_meta("slot_spin_visual_owner"):
		owner_ref = GameCurrency.get_meta("slot_spin_visual_owner") as WeakRef
	if owner_ref == null or owner_ref.get_ref() == null:
		# Retry a failed exit save when returning from a menu, without stealing
		# a still-running machine's transaction in another instantiated scene.
		GameCurrency.complete_slot_spin()


func _exit_tree() -> void:
	_stop_rolling_audio()
	if is_instance_valid(_spin_audio):
		_spin_audio.stop()
	for tween in _spin_tweens:
		if tween != null:
			tween.kill()
	# A started spin has a persisted outcome. Leaving/closing cannot discard
	# a win or credit it twice; crash recovery is handled by GameCurrency.
	if _owns_pending_spin:
		_owns_pending_spin = false
		GameCurrency.complete_slot_spin()
