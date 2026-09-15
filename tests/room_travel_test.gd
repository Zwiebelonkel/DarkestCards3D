extends Node3D

var main: MainScene
var failures := 0
var checks := 0
var arrivals: Array[int] = []
var _game_viewport: Viewport


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func _settle(seconds: float = 0.06) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame


func _run() -> void:
	if not str(DeckManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Use the isolated match-feature test runner.")
		get_tree().quit(1)
		return
	# This suite covers already-unlocked room travel; key discovery has its own test.
	CollectionManager.add_card(CollectionManager.SLOT_ROOM_KEY_ID)
	CollectionManager.unlock_slot_room()
	get_tree().root.size = Vector2i(1280, 720)
	_game_viewport = get_viewport()
	if DisplayServer.get_name() != "headless":
		# A hidden Windows test process cannot reliably read the OS cursor.
		# Render the real game in a viewport whose pointer comes from input
		# events, preserving production camera, physics picking and hover code.
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1280, 720)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		# SubViewportContainer would reconnect mouse polling to the native
		# window. A TextureRect displays the same image without that link.
		var preview := TextureRect.new()
		preview.size = Vector2(1280, 720)
		preview.texture = viewport.get_texture()
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(preview)
		viewport.notify_mouse_entered()
		_game_viewport = viewport
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.mouse_tilt_strength = 0.0
	main.room_travel_duration = 0.6 if DisplayServer.get_name() == "headless" else 3.2
	main.rotation_duration = 0.01
	main.settle_duration = 0.01
	if _game_viewport is SubViewport:
		_game_viewport.add_child(main)
	else:
		add_child(main)
	main.room_changed.connect(func(room: int): arrivals.append(room))
	await _settle(0.2)
	# A real window can initially place its pointer over a shop screen. Clear
	# that hover and let its camera tween finish before projecting a door hit.
	_move_pointer(Vector2(5, 700))
	await _wait_for_camera_rest()
	check(main._active_room == 0 and main._can_travel_between_rooms(), "main starts in the hub with room travel available")
	var room_bus := main._room_music_bus
	var music_bus_index := AudioServer.get_bus_index(&"Music")
	var music_setting_db := AudioServer.get_bus_volume_db(music_bus_index)
	var player_volume_db := main.music.volume_db
	check(main.music.bus == room_bus and AudioServer.get_bus_send(AudioServer.get_bus_index(room_bus)) == &"Music" and not AudioServer.is_bus_effect_enabled(AudioServer.get_bus_index(room_bus), 0), "hub music uses a clean scene-owned bus feeding the music setting")
	await _check_laugh_audio()
	check(main.hub_door.doorway_area.input_ray_pickable and not main.return_door.doorway_area.input_ray_pickable, "only the current room door accepts clicks")
	await _turn(1)
	await _wait_for_camera_rest()
	check(main._active_side == 3, "A/D still reaches the upgrade and doorway side")
	await _capture("hub-closed")
	var hub_origin := main.camera_pivot.global_position
	var hub_side := main._active_side
	var hub_basis := main.camera_pivot.global_basis
	var camera_basis := main.main_camera.basis
	var fixed_area := main.hub_door.doorway_area.global_transform
	var fixed_frame := main.hub_door.get_node("Frame").global_transform as Transform3D
	var pointer := _point_at(main.hub_door)
	check(_game_viewport.get_visible_rect().has_point(pointer), "the hub doorway is visible before hover begins")
	await _wait_for_door_hover(main.hub_door)
	check(absf(main.hub_door.hinge.rotation.y) > 0.3, "hover swings the supplied door leaf open")
	check(main.hub_door.doorway_area.global_transform.is_equal_approx(fixed_area), "hover keeps the clickable doorway stationary")
	check((main.hub_door.get_node("Frame") as Node3D).global_transform.is_equal_approx(fixed_frame), "hover keeps the door frame stationary")
	var ray := PhysicsRayQueryParameters3D.create(main.main_camera.project_ray_origin(pointer), main.main_camera.project_ray_origin(pointer) + main.main_camera.project_ray_normal(pointer) * 100.0)
	ray.collide_with_areas = true
	check(main.get_world_3d().direct_space_state.intersect_ray(ray).get("collider") == main.hub_door.doorway_area, "the doorway is reachable by an actual camera ray beside the upgrade machine")
	await _capture("hub-hover")
	_move_pointer(Vector2(5, 700))
	await _settle(0.4)
	check(absf(main.hub_door.hinge.rotation.y) < 0.01, "leaving the doorway closes the leaf")
	main._pack_opening_blocks_screen_focus = true
	_click(main.hub_door)
	check(not main._room_transition_active, "an unfinished pack blocks room travel")
	main._pack_opening_blocks_screen_focus = false
	main.table_lobby.show()
	_click(main.hub_door)
	check(not main._room_transition_active, "an open lobby blocks room travel")
	main.table_lobby.hide()
	main.pause_menu.visible = true
	_click(main.hub_door)
	check(not main._room_transition_active, "a pause overlay blocks room travel")
	main.pause_menu.visible = false
	var table := main.scene_pivot.get_node("GameTable") as GameTable
	var previous_table_state := table._table_state
	table._table_state = GameTable.TableState.PLAYING
	check(not main._can_travel_between_rooms(), "a match blocks travel even on another hub side")
	table._table_state = previous_table_state
	await _settle()
	for round_trip in range(2):
		_click(main.hub_door)
		check(main._room_transition_active, "door click starts a camera flight")
		var steps := main._settle_step_index
		main._begin_turn(1)
		_click(main.hub_door)
		check(main._settle_step_index == steps, "turning and repeated clicks cannot restart a flight")
		check(not main.hub_door.doorway_area.input_ray_pickable and not main.return_door.doorway_area.input_ray_pickable, "both doors reject extra input in flight")
		main.pause_menu.open()
		check(not main.pause_menu.visible and not get_tree().paused, "pause cannot strand an active flight")
		await _settle(0.15)
		check(main._room_music_mix > 0.0 and main._room_music_mix < 1.0, "music damping blends progressively during the doorway flight")
		check(main.camera_pivot.global_position.distance_to(hub_origin) > 0.1, "camera moves through the doorway over time")
		if round_trip == 0:
			await _settle(maxf(main.room_travel_duration * 0.43 - 0.2, 0.01))
			await _capture("passage")
		await _wait_for_arrival()
		check(main._active_room == 1, "flight arrives in the empty room")
		check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(room_bus)), main.slot_room_music_attenuation_db) and AudioServer.is_bus_effect_enabled(AudioServer.get_bus_index(room_bus), 0) and is_equal_approx(main._room_music_filter.cutoff_hz, main.slot_room_music_cutoff_hz), "slot room music is quieter with treble filtered out")
		check(is_equal_approx(main.music.volume_db, player_volume_db) and is_equal_approx(AudioServer.get_bus_volume_db(music_bus_index), music_setting_db), "room damping preserves player fades and the user's music volume")
		SettingsManager.set_music_volume(0.45)
		check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(room_bus)), main.slot_room_music_attenuation_db), "changing the music slider retains room attenuation")
		SettingsManager.set_music_volume(db_to_linear(music_setting_db))
		check(main.camera_pivot.global_position.is_equal_approx(main.room_camera_anchor.global_position), "empty room turns around its own camera center")
		check(main.main_camera.basis.is_equal_approx(camera_basis), "travel preserves the camera's normal local basis")
		check(not main.screen_camera_focus._interaction_allowed, "hub screen focus is disabled in the empty room")
		for machine_name in ["PackShopMachine", "UpgradeMachine"]:
			check(not (main.scene_pivot.get_node(machine_name + "/ScreenArea") as Area3D).input_ray_pickable, "distant " + machine_name + " screen stays inactive")
		check(main.return_door.doorway_area.input_ray_pickable and not main.hub_door.doorway_area.input_ray_pickable, "empty room exposes only its return door")
		if round_trip == 0:
			await _capture("empty-arrival")
		var room_origin := main.camera_pivot.global_position
		var room_basis := main.camera_pivot.global_basis
		for direction in [1, 1, 1, 1, -1, -1, -1, -1]:
			await _turn(direction)
		check(main.camera_pivot.global_basis.is_equal_approx(room_basis), "eight A/D turns in the new room keep exact cardinal alignment")
		check(main.camera_pivot.global_position.is_equal_approx(room_origin), "turning in the empty room does not return the rig to the hub")
		await _turn(1)
		await _turn(1)
		_point_at(main.return_door)
		await _wait_for_door_hover(main.return_door)
		if round_trip == 0:
			await _capture("empty-return-door")
		_click(main.return_door)
		await _wait_for_arrival()
		check(main._active_room == 0 and main._active_side == hub_side, "return flight restores the original hub side")
		check(is_zero_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(room_bus))) and not AudioServer.is_bus_effect_enabled(AudioServer.get_bus_index(room_bus), 0), "returning fully restores music volume and bypasses the room filter")
		check(main.camera_pivot.global_position.is_equal_approx(hub_origin), "return flight restores the hub turning center")
		check(main.camera_pivot.global_basis.is_equal_approx(hub_basis), "return flight restores exact hub orientation")
	check(arrivals == [1, 0, 1, 0], "two round trips emit one arrival per room change")
	await _capture("hub-returned")
	main.queue_free()
	await _settle()
	check(AudioServer.get_bus_index(room_bus) == -1, "leaving Main removes its room filter and audio bus")
	print("ROOM_TRAVEL_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _check_laugh_audio() -> void:
	var table := main.scene_pivot.get_node("GameTable") as GameTable
	var laugh := table._satan_laugh_audio
	check(laugh != null and not laugh.playing and laugh.bus == &"SFX", "Satan starts silent and uses the SFX setting")
	table._set_satan_laughing(true)
	await _settle(0.2)
	check(table.dealer_satan.texture == GameTable.SATAN_LAUGH_TEXTURE and not laugh.playing and not laugh.is_processing(), "the defeat laugh animation stays silent before Exit is clicked")
	table._last_match_outcome = GameTable.MatchOutcome.LOSS
	table._table_state = GameTable.TableState.GAME_OVER
	table.end_buttons.show()
	table.end_buttons.get_node("ExitButton").pressed.emit()
	check(table._loss_exit_running and laugh.playing, "clicking the real Exit button immediately starts the loss laugh sound")
	var previous_pitch := laugh.pitch_scale
	var changes := 0
	var deadline := Time.get_ticks_msec() + 1100
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not is_equal_approx(previous_pitch, laugh.pitch_scale):
			changes += 1
			previous_pitch = laugh.pitch_scale
	check(changes >= 5, "laughter repeats rapidly with a different pitch for each syllable")
	get_tree().paused = true
	var remaining: float = laugh._syllable_remaining
	await get_tree().create_timer(0.2).timeout
	# Pausing between syllables may find no active playback to pause.
	check(is_equal_approx(remaining, laugh._syllable_remaining) and (laugh.stream_paused or not laugh.playing), "pause freezes the laugh audio together with the animation")
	get_tree().paused = false
	table.dealer_satan.hide()
	await _settle()
	check(not laugh.playing, "a hidden Satan cannot leave an audible laugh behind")
	table.dealer_satan.show()
	var resumed := false
	deadline = Time.get_ticks_msec() + 500
	while Time.get_ticks_msec() < deadline and not resumed:
		await get_tree().process_frame
		resumed = laugh.playing
	check(resumed, "showing an ongoing laugh resumes its voice")
	table._set_satan_dying(true)
	check(not laugh.playing, "the death animation stops laughter immediately")
	table._set_satan_dying(false)
	table._set_satan_laughing(true)
	table._set_satan_laughing(false)
	check(not laugh.playing and not laugh.is_processing(), "returning to idle stops all voice repetitions")
	deadline = Time.get_ticks_msec() + 20000
	while table._loss_exit_running and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(not table._loss_exit_running and not laugh.playing, "the completed Exit cinematic leaves no laugh sound running")
	table._set_satan_laughing(true)
	check(not laugh.playing and not laugh.is_processing(), "a later defeat waits for a new Exit click before playing laughter")
	table._set_satan_laughing(false)
	await _wait_for_camera_rest()
	await _settle()


func _turn(direction: int) -> void:
	main._begin_turn(direction)
	await _settle()


func _wait_for_camera_rest() -> void:
	for frame in range(240):
		if not main.screen_camera_focus.is_focused() and main.screen_camera_focus._camera_tween == null:
			return
		await get_tree().process_frame
	check(false, "screen-focus camera returns before projecting doorway coordinates")


func _wait_for_door_hover(door: HospitalDoor) -> void:
	for frame in range(180):
		if is_equal_approx(door.hinge.rotation.y, deg_to_rad(door.hover_open_degrees)):
			return
		await get_tree().process_frame
	check(false, "projected pointer reaches the door's hover pose")


func _wait_for_arrival() -> void:
	for frame in range(600):
		if not main._room_transition_active:
			return
		await get_tree().process_frame
	check(false, "room flight finishes within the test timeout")


func _point_at(door: HospitalDoor) -> Vector2:
	var target := door.doorway_area.global_position
	var point := main.main_camera.unproject_position(target)
	_move_pointer(point)
	return point


func _move_pointer(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	# Route through Input so viewport mouse-position polling observes the same
	# pointer as the injected event, including in the headless display backend.
	if _game_viewport is SubViewport:
		_game_viewport.push_input(event, true)
	else:
		Input.parse_input_event(event)


func _click(door: HospitalDoor) -> void:
	# Use the actual scene signal; the separate ray test validates accessibility.
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	door.doorway_area.input_event.emit(main.main_camera, click, door.doorway_area.global_position, Vector3.FORWARD, 0)


func _capture(stage: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_game_viewport.get_texture().get_image().save_png("res://room-travel-%s.png" % stage)
