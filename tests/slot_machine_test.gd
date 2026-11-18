extends Node3D

var main: MainScene
var machine: SoulSlotMachine
var failures := 0
var checks := 0
var starts: Array[int] = []
var finishes: Array[int] = []
var arrivals: Array[int] = []
var rewards: Array[Vector2i] = []
var _game_viewport: SubViewport
var _record_spin_cadence := false
var _spin_click_times: Array[float] = []
var _last_click_threshold := 0.0
var _rolling_levels: Array[Vector2] = []
var _jackpot_levels: Array[float] = []


func _ready() -> void:
	_run.call_deferred()


func _process(_delta: float) -> void:
	if is_instance_valid(machine) and machine.is_spinning:
		for entry: Dictionary in machine._model_text._atlas_labels:
			if entry["source"] == "JACKPOT":
				_jackpot_levels.append((entry["label"] as Label3D).modulate.r)
	if not _record_spin_cadence or not is_instance_valid(machine):
		return
	if machine._rolling_audio.playing:
		_rolling_levels.append(Vector2(machine._rolling_audio.pitch_scale, machine._rolling_audio.volume_db))
	if machine._spin_next_click_angle > _last_click_threshold:
		_spin_click_times.append(Time.get_ticks_msec() / 1000.0)
		_last_click_threshold = machine._spin_next_click_angle


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func _settle(seconds: float = 0.045) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().physics_frame
	await get_tree().process_frame


func _run() -> void:
	if not str(DeckManager.SAVE_PATH).begins_with("res://test-user/") or not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Use the isolated match-feature test runner to protect player saves.")
		get_tree().quit(1)
		return
	for color in range(5):
		var triple: Array[int] = [color, color, color]
		check(SoulSlotMachine.payout_for(triple, 137) == 137 * [5, 10, 15, 35, 55][color], "color %d pays its advertised multiplier without losing fractional coins" % color)
	check(SoulSlotMachine.payout_for([0, 1, 0], 100) == 0 and SoulSlotMachine.payout_for([5, 5, 5], 100) == 0 and SoulSlotMachine.payout_for([0, 0], 100) == 0 and SoulSlotMachine.payout_for([0, 0, 0], 0) == 0, "mixed, invalid and incomplete results cannot pay")
	var seeds := _find_triple_seeds()
	check(seeds.size() == 5, "bounded seed search finds every real triple outcome")
	if seeds.size() != 5:
		_finish_test()
		return
	GameCurrency.reset_progression(false)
	GameCurrency.coins = 100.37
	GameCurrency.save()
	CollectionManager.add_card(CollectionManager.SLOT_ROOM_KEY_ID)
	CollectionManager.unlock_slot_room()
	get_tree().root.size = Vector2i(1280, 720)
	# A SubViewport gives hidden Windows runs an event-driven pointer while
	# preserving the actual Main camera, physics world and button picking.
	_game_viewport = SubViewport.new()
	_game_viewport.size = Vector2i(1280, 720)
	_game_viewport.own_world_3d = true
	_game_viewport.physics_object_picking = true
	_game_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_game_viewport)
	_game_viewport.notify_mouse_entered()
	if DisplayServer.get_name() != "headless":
		var preview := TextureRect.new()
		preview.size = Vector2(1280, 720)
		preview.texture = _game_viewport.get_texture()
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(preview)
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.mouse_tilt_strength = 0.0
	main.room_travel_duration = 0.35
	main.rotation_duration = 0.01
	main.settle_duration = 0.01
	_game_viewport.add_child(main)
	machine = main.slot_machine
	machine.spin_duration = 0.22
	machine.reel_stop_delay = 0.025
	machine.spin_started.connect(func(stake: int): starts.append(stake))
	machine.spin_finished.connect(func(_result: Array[int], payout: int): finishes.append(payout))
	machine._win_effect.started.connect(func(tier: int, payout: int): rewards.append(Vector2i(tier, payout)))
	main.room_changed.connect(func(room: int): arrivals.append(room))
	_move_pointer(Vector2(5, 700))
	await _settle(0.2)
	check(machine.reel_pivots.size() == 3 and machine.button_areas.size() == 4, "actual imported machine creates all three reels and four input targets")
	check(_model_faces_match([0, 1, 2]) and machine.last_result.is_empty(), "initial decorative faces show green, red and blue without claiming an unearned result")
	check(not machine.interaction_enabled and _all_buttons_disabled() and not machine.confirm_bet() and GameCurrency.get_coin_cents() == 10037, "hub cannot operate the distant machine or charge the isolated fractional balance")
	await _turn(1)
	await _wait_for_camera_rest()
	var hub_pose := main.camera_pivot.global_transform
	var hub_side := main._active_side
	await _click_area(main.hub_door.doorway_area, "hub doorway")
	check(main._room_transition_active and _all_buttons_disabled(), "real doorway click flies toward the slot room with controls disabled in transit")
	await _wait_for_arrival()
	check(main._active_room == 1 and main._active_side == 0 and machine.interaction_enabled, "arrival enables the machine on its visible cardinal side")
	await _capture("start")
	for step in range(5):
		machine.choose_bet(1)
	check(machine.get_selected_bet_cents() == 5000 and machine.button_areas["increase"].input_ray_pickable, "50 SC keeps the increase button available")
	await _click_button("increase")
	check(machine.get_selected_bet_cents() == 6000, "plus increases 50 SC to 60 SC")
	await _click_button("increase")
	await _click_button("bet")
	check(machine.get_selected_bet_cents() == 7000 and machine.committed_bet_cents == 7000, "70 SC can be selected and confirmed")
	await _click_button("decrease")
	check(machine.get_selected_bet_cents() == 6000 and machine.committed_bet_cents == 0, "minus returns to 60 SC and clears confirmation")
	await _click_button("decrease")
	check(machine.get_selected_bet_cents() == 5000, "minus returns from 60 SC to 50 SC")
	for step in range(6):
		machine.choose_bet(1)
	check(machine.get_selected_bet_cents() == 11000 and not machine.confirm_bet(), "stakes continue beyond 100 SC but insufficient funds prevent confirmation")
	while machine.selected_bet_index > 0:
		machine.choose_bet(-1)
	var balance := GameCurrency.get_coin_cents()
	await _click_button("spin")
	check(not machine.is_spinning and starts.is_empty() and GameCurrency.get_coin_cents() == balance, "SPIN without BET cannot charge or animate")
	check(not machine._spin_audio.playing, "a rejected spin does not play the spinning sound")
	check(not machine._rolling_audio.playing, "a rejected spin never starts the rolling loop")
	await _click_button("increase")
	check(machine.selected_bet_index == 1 and machine.committed_bet_cents == 0, "projected green plus chooses the next stake")
	await _click_button("decrease")
	check(machine.selected_bet_index == 0 and machine.committed_bet_cents == 0, "projected red minus restores the lowest stake")
	await _click_button("bet")
	check(machine.committed_bet_cents == 100 and GameCurrency.get_coin_cents() == balance and not GameCurrency.has_pending_slot_spin(), "yellow BET confirms an unused stake without reserving or charging coins")
	await _turn(1)
	check(not machine.interaction_enabled and _all_buttons_disabled() and not machine.start_spin() and GameCurrency.get_coin_cents() == balance, "turning away disables every button and retains an uncharged BET")
	await _turn(-1)
	check(machine.interaction_enabled and machine.committed_bet_cents == 100, "turning back restores controls and the confirmed stake")
	main._begin_turn(1)
	check(not machine.interaction_enabled and _all_buttons_disabled() and not machine.start_spin(), "beginning an A/D turn locks buttons synchronously before the next frame")
	await _settle(0.08)
	await _turn(-1)
	main._pack_opening_blocks_screen_focus = true
	main._update_room_door_interaction()
	check(_all_buttons_disabled() and not machine.choose_bet(1) and not machine.start_spin(), "a blocking interaction context prevents stake edits and spins")
	main._pack_opening_blocks_screen_focus = false
	main._update_room_door_interaction()
	get_tree().paused = true
	check(not machine._can_interact() and not machine.choose_bet(1) and not machine.confirm_bet() and not machine.start_spin() and GameCurrency.get_coin_cents() == balance, "tree pause rejects all machine actions without charging")
	get_tree().paused = false
	var camera_pose := main.main_camera.transform
	var camera_fov := main.main_camera.fov
	var original_time_scale := Engine.time_scale
	var previous_particle_count := 0
	for color in range(5):
		machine._rng.seed = seeds[color]
		balance = GameCurrency.get_coin_cents()
		if color == 0:
			await _click_button("spin")
		else:
			machine.start_spin()
		check(machine.is_spinning and machine.last_result == [color, color, color] and GameCurrency.get_coin_cents() == balance - 100 and GameCurrency.has_pending_slot_spin(), "seeded color %d starts a real spin and charges precisely once" % color)
		check(machine._spin_audio.playing and not (machine._spin_audio.stream as AudioStreamMP3).loop and machine._spin_audio.bus == &"SFX", "accepted spins start individual clicks from the uploaded sound on the SFX bus")
		check(machine._rolling_audio.playing and (machine._rolling_audio.stream as AudioStreamMP3).loop and machine._rolling_audio.bus == &"SFX" and is_equal_approx(machine._rolling_audio.pitch_scale, 1.0) and is_equal_approx(machine._rolling_audio.volume_db, machine.ROLLING_VOLUME_DB), "each accepted spin starts a fresh full-speed rolling loop on SFX")
		check(not (machine.ROLLING_SOUND as AudioStreamMP3).loop, "looping the machine never changes the source sound resource")
		if color == 0:
			# A refused wallet settlement must retain the pending win without
			# claiming it visually. Retrying uses the same committed spin.
			GameCurrency._slot_transaction_active = true
			check(not machine.start_spin() and not machine.confirm_bet() and not machine.choose_bet(1) and _all_buttons_disabled() and starts.size() == 1 and GameCurrency.get_coin_cents() == balance - 100, "running animation rejects duplicate SPIN and all stake changes")
			await _capture("spinning")
		await _wait_for_spin()
		check(not _jackpot_levels.is_empty() and _jackpot_levels.min() < 0.3 and _jackpot_levels.max() > 0.8, "actual jackpot lettering flickers during reel movement")
		for entry: Dictionary in machine._model_text._atlas_labels:
			if entry["source"] == "JACKPOT":
				check((entry["label"] as Label3D).modulate == Color("e3cfc0"), "jackpot returns to steady light when reels stop, including failed settlement")
		check(not machine._spin_audio.playing, "the last reel silences its clicks even if payout saving fails")
		check(not machine._rolling_audio.playing and machine._rolling_tail_tween == null, "the last revealed symbol stops rolling audio and its fade even if payout saving fails")
		if color == 0:
			check(rewards.is_empty() and not machine._win_effect.active and finishes.is_empty() and machine._owns_pending_spin and GameCurrency.has_pending_slot_spin() and GameCurrency.get_coin_cents() == balance - 100, "failed settlement emits no reward effect or payout announcement")
			GameCurrency._slot_transaction_active = false
			check(not machine.start_spin() and starts.size() == 1 and rewards == [Vector2i(0, 500)], "successful settlement retry reveals its original reward once without a new spin")
			await _settle()
		check(_faces_match_result(color), "all three actual mesh facets face the payline at color %d's stop angle" % color)
		var expected: int = balance - 100 + 100 * [5, 10, 15, 35, 55][color]
		machine._finish_spin()
		check(GameCurrency.get_coin_cents() == expected and not GameCurrency.has_pending_slot_spin() and finishes.size() == color + 1, "color %d settles its exact payout once, even after duplicate completion" % color)
		var effect := machine._win_effect
		check(effect.active and effect._layer.visible and rewards.size() == color + 1 and rewards.back() == Vector2i(color, 100 * SoulSlotMachine.MULTIPLIERS[color]), "tier %d displays exactly one reward after successful payout and ignores duplicate completion" % color)
		check(effect._icon.texture == SoulSlotMachine.SYMBOL_TEXTURES[color] and effect._icon.modulate == SoulSlotMachine.COLOR_TINTS[color] and effect._flash_material.get_shader_parameter("rarity_color") == SoulSlotMachine.COLOR_TINTS[color] and effect._amount.text == Localization.format_text("+%s SC", [Localization.decimal(float(SoulSlotMachine.MULTIPLIERS[color]))]), "tier %d uses its matching effect icon, flash color and exact payout amount" % color)
		check(is_instance_valid(effect._particles) and effect._particles.amount > previous_particle_count and effect._light.light_color == SoulSlotMachine.COLOR_TINTS[color], "tier %d adds a stronger matching particle burst and machine light" % color)
		previous_particle_count = effect._particles.amount
		check(main.main_camera.transform.is_equal_approx(camera_pose) and is_equal_approx(main.main_camera.fov, camera_fov) and is_equal_approx(Engine.time_scale, original_time_scale), "tier %d leaves camera pose, FOV and game time unchanged" % color)
		if color == 0:
			await _settle(1.8)
			check(not effect.active and not effect._layer.visible and not is_instance_valid(effect._particles) and is_zero_approx(effect._light.light_energy) and is_zero_approx(float(effect._flash_material.get_shader_parameter("glow_strength"))), "reward animation fully cleans up its flash, announcement, particles and light")
		elif color == 3:
			await _settle(0.15)
			await _capture("gold-reward")
	await _settle(0.15)
	await _capture("win")
	main._begin_turn(1)
	check(not machine._win_effect.active and not machine._win_effect._layer.visible, "turning away cancels the overlay synchronously before camera movement")
	await _settle(0.08)
	await _turn(-1)
	check(rewards.size() == 5 and not machine._win_effect.active, "looking back does not replay an already presented win")
	# Use normal RNG and tween completion, with enough duration that the last
	# reel remains in motion when the player reaches the hub again.
	machine.spin_duration = 1.8
	machine._rng.seed = seeds[4]
	balance = GameCurrency.get_coin_cents()
	check(machine.start_spin() and GameCurrency.get_coin_cents() == balance - 100, "a fresh winning spin begins before leaving the room")
	_spin_click_times.assign([Time.get_ticks_msec() / 1000.0])
	_last_click_threshold = machine._spin_next_click_angle
	_record_spin_cadence = true
	await _turn(1)
	await _turn(1)
	var departure_angle := machine._reel_angles[2]
	var departure_click_angle := machine._spin_next_click_angle
	await _click_area(main.return_door.doorway_area, "return doorway")
	check(main._room_transition_active and machine.is_spinning and _all_buttons_disabled(), "return doorway remains usable during a spin and locks machine input during flight")
	await _wait_for_arrival()
	check(main._active_room == 0 and main._active_side == hub_side and main.camera_pivot.global_transform.is_equal_approx(hub_pose) and machine.is_spinning and not machine.interaction_enabled and not is_equal_approx(machine._reel_angles[2], departure_angle), "return restores the hub camera while the inaccessible machine continues spinning")
	check(machine._spin_next_click_angle > departure_click_angle, "leaving the slot room keeps triggering spatial clicks as the reel moves")
	await _wait_for_spin()
	_record_spin_cadence = false
	check(_rolling_levels.size() > 5 and _rolling_levels[0].x > 0.95 and _rolling_levels.back().x < 0.8 and _rolling_levels.back().y < machine.ROLLING_VOLUME_DB - 10.0, "rolling audio slows down and fades as the final symbols are revealed")
	var rolling_is_monotonic := true
	for index in range(1, _rolling_levels.size()):
		rolling_is_monotonic = rolling_is_monotonic and _rolling_levels[index].x <= _rolling_levels[index - 1].x + 0.001 and _rolling_levels[index].y <= _rolling_levels[index - 1].y + 0.001
	check(rolling_is_monotonic, "rolling pitch and volume decrease smoothly without restarting during a spin")
	check(_spin_click_times.size() >= 10, "a normal spin produces a rapid sequence of rotation-driven clicks")
	if _spin_click_times.size() >= 10:
		var early_gap := (_spin_click_times[5] - _spin_click_times[0]) / 5.0
		var late_gap: float = (_spin_click_times.back() - _spin_click_times[-4]) / 3.0
		check(early_gap < 0.08 and late_gap > early_gap * 2.0, "click spacing grows with actual reel deceleration")
		print("SLOT_CLICK_CADENCE: first clicks %.3f s apart, last clicks %.3f s apart" % [early_gap, late_gap])
	machine._finish_spin()
	check(GameCurrency.get_coin_cents() == balance - 100 + 5500 and starts.size() == 6 and finishes.size() == 6 and not GameCurrency.has_pending_slot_spin(), "spin finishing in the hub credits its committed win exactly once")
	check(rewards.size() == 5 and not machine._win_effect.active and not machine._win_effect._layer.visible, "off-room payout does not flash the hub or show a distant announcement")
	await _click_area(main.hub_door.doorway_area, "hub doorway on second visit")
	await _wait_for_arrival()
	check(machine.interaction_enabled and machine.last_result == [4, 4, 4] and _faces_match_result(4) and arrivals == [1, 0, 1], "reentering preserves the completed win, correct reel faces and room arrival sequence")
	machine.spin_duration = 0.22
	machine._rng.seed = _find_losing_seed()
	balance = GameCurrency.get_coin_cents()
	var old_generation := machine._spin_generation
	check(machine.start_spin() and machine.last_payout_cents == 0 and not (machine.last_result[0] == machine.last_result[1] and machine.last_result[1] == machine.last_result[2]) and GameCurrency.get_coin_cents() == balance - 100, "a seeded mixed result starts a real losing spin with one exact stake debit")
	var unsettled_angle := machine._reel_angles[2]
	machine._on_reel_stopped(2, old_generation)
	machine._finish_spin(old_generation)
	check(machine.is_spinning and GameCurrency.has_pending_slot_spin() and GameCurrency.get_coin_cents() == balance - 100 and finishes.size() == 6 and is_equal_approx(machine._reel_angles[2], unsettled_angle), "callbacks from the previous generation cannot stop a reel or settle the new spin")
	check(machine._spin_audio.playing, "stale completion callbacks cannot silence a new spin")
	check(machine._rolling_audio.playing and is_equal_approx(machine._rolling_audio.pitch_scale, 1.0), "stale callbacks cannot fade or stop the new rolling loop")
	await _wait_for_spin()
	check(GameCurrency.get_coin_cents() == balance - 100 and machine.last_payout_cents == 0 and finishes.size() == 7 and finishes.back() == 0 and not GameCurrency.has_pending_slot_spin(), "natural losing-spin completion pays zero and clears the pending transaction")
	check(rewards.size() == 5 and not machine._win_effect.active, "a losing spin never emits a reward reveal")
	machine.spin_duration = 1.8
	machine._rng.seed = seeds[3]
	balance = GameCurrency.get_coin_cents()
	check(machine.start_spin() and machine.is_spinning and GameCurrency.get_coin_cents() == balance - 100, "scene-exit scenario begins a committed gold triple before animation finishes")
	var room_music_bus := main._room_music_bus
	main.queue_free()
	await _settle()
	check(AudioServer.get_bus_index(room_music_bus) == -1, "scene exit during a spin leaves no room music filter behind")
	var after_exit := balance - 100 + 3500
	check(GameCurrency.get_coin_cents() == after_exit and not GameCurrency.has_pending_slot_spin() and starts.size() == 8 and finishes.size() == 7, "freeing Main mid-win settles exactly once while cancelling its animation")
	check(rewards.size() == 5, "scene-exit settlement cannot create an orphaned reward overlay")
	GameCurrency.load_currency()
	check(GameCurrency.get_coin_cents() == after_exit and not GameCurrency.has_pending_slot_spin() and not GameCurrency.complete_slot_spin(), "reloading the wallet after scene exit cannot credit the interrupted win again")
	_finish_test()


func _find_triple_seeds() -> Dictionary:
	var seeds := {}
	var rng := RandomNumberGenerator.new()
	for candidate in range(10000):
		rng.seed = candidate
		var first := rng.randi_range(0, 4)
		var second := rng.randi_range(0, 4)
		var third := rng.randi_range(0, 4)
		if first == second and second == third and not seeds.has(first):
			seeds[first] = candidate
		if seeds.size() == 5:
			break
	print("SLOT_TRIPLE_SEEDS: ", seeds)
	return seeds


func _faces_match_result(color: int) -> bool:
	return _model_faces_match([color, color, color]) and machine.last_result == [color, color, color] and not machine.is_spinning


func _model_faces_match(colors: Array[int]) -> bool:
	for index in range(3):
		var reel := machine.reel_pivots[index].get_child(0) as MeshInstance3D
		var arrays := reel.mesh.surface_get_arrays(colors[index])
		var normal: Vector3 = arrays[Mesh.ARRAY_NORMAL][0]
		var world_normal := (reel.global_basis.inverse().transposed() * normal).normalized()
		var expected_angle := -atan2(normal.x, normal.z)
		if world_normal.dot(machine.global_basis.z.normalized()) < 0.999:
			return false
		if absf(wrapf(machine._reel_angles[index] - expected_angle, -PI, PI)) > 0.001:
			return false
	return true


func _find_losing_seed() -> int:
	var rng := RandomNumberGenerator.new()
	for candidate in range(100):
		rng.seed = candidate
		var a := rng.randi_range(0, 4)
		var b := rng.randi_range(0, 4)
		var c := rng.randi_range(0, 4)
		if a != b or b != c:
			print("SLOT_LOSING_SEED: ", candidate)
			return candidate
	check(false, "bounded seed search finds a real losing result")
	return 0


func _all_buttons_disabled() -> bool:
	for area: Area3D in machine.button_areas.values():
		if area.input_ray_pickable:
			return false
	return true


func _click_button(action: String) -> void:
	await _click_area(machine.button_areas[action] as Area3D, action + " button")


func _click_area(area: Area3D, description: String) -> void:
	var camera := main.main_camera
	var position := camera.unproject_position(area.global_position)
	_move_pointer(position)
	await _settle(0.015)
	var origin := camera.project_ray_origin(position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(position) * camera.far)
	query.collide_with_areas = true
	check(not camera.is_position_behind(area.global_position) and _game_viewport.get_visible_rect().has_point(position) and main.get_world_3d().direct_space_state.intersect_ray(query).get("collider") == area, description + " is visible and is the first collider hit by its projected camera ray")
	# Exercise Viewport's real physics picking; do not emit Area.input_event
	# directly, so swallowed GUI events and picking flags remain observable.
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		_game_viewport.push_input(event, true)
		await _settle(0.015)


func _move_pointer(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	_game_viewport.push_input(motion, true)


func _turn(direction: int) -> void:
	_move_pointer(Vector2(5, 700))
	main._begin_turn(direction)
	await _settle(0.08)


func _wait_for_arrival() -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while main._room_transition_active and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(not main._room_transition_active, "room flight completes within five seconds")
	await _settle()


func _wait_for_camera_rest() -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while (main.screen_camera_focus.is_focused() or main.screen_camera_focus._camera_tween != null) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(not main.screen_camera_focus.is_focused() and main.screen_camera_focus._camera_tween == null, "screen focus releases the shared camera before room travel")


func _wait_for_spin() -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while machine.is_spinning and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(not machine.is_spinning, "reel animation finishes within five seconds")
	await _settle()


func _capture(stage: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_game_viewport.get_texture().get_image().save_png("res://slot-machine-%s.png" % stage)


func _finish_test() -> void:
	print("SLOT_MACHINE_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
