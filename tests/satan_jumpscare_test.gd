extends Node

var failures := 0
var checks := 0
var viewport: SubViewport
var main: MainScene
var table: GameTable
var scare: Node3D
var finished_count := 0


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + message)
	if not condition:
		failures += 1


func settle(seconds: float = 0.05) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame


func _click_signal(button: MouseButton = MOUSE_BUTTON_LEFT, pressed: bool = true) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	table.satan_hover_area.input_event.emit(main.main_camera, event, Vector3.ZERO, Vector3.ZERO, 0)


func _click_real() -> void:
	var point := main.main_camera.unproject_position(table.dealer_satan.global_position)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	viewport.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		viewport.push_input(event, true)
		await get_tree().physics_frame
	await get_tree().process_frame


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	viewport.push_input(event, true)


func _spam_input() -> void:
	for code in [KEY_A, KEY_D, KEY_J, KEY_ESCAPE, KEY_SPACE, KEY_ENTER]:
		_key(code)
	_click_signal()
	main._read_input()


func _capture(label: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://satan-" + label + "-preview.png")


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	AudioServer.set_bus_mute(0, true)
	GameCurrency.set_process(false)
	CollectionManager.clear_profile_state()
	DeckManager.clear_profile_state()
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.greeting_enabled = false
	main.mouse_tilt_strength = 0.0
	viewport.add_child(main)
	table = main.scene_pivot.get_node("GameTable") as GameTable
	scare = main._satan_jumpscare
	scare.finished.connect(func() -> void: finished_count += 1)
	await settle(0.5)
	check(main._satan_jumpscare_context_is_safe(), "the idle hub allows Satan spam detection")
	check(not main.blood_overlay.active and not main.blood_overlay.blood_rect.visible, "ordinary hub entry has no blood border")
	check(scare.clicks_required == 4 and is_equal_approx(scare.click_window_seconds, 1.5) and scare.cooldown_seconds == 8.0, "four clicks in 1.5 seconds trigger with an eight-second cooldown")
	check(scare._sound.stream == scare.SCARE_SOUND and scare._sound.stream.resource_path.ends_with("jumpscare.mp3"), "jumpscare uses its dedicated sound resource")
	_click_signal(MOUSE_BUTTON_RIGHT)
	_click_signal(MOUSE_BUTTON_LEFT, false)
	check(scare._click_times.is_empty(), "right clicks and releases never count")
	for state in [GameTable.TableState.PLAYING, GameTable.TableState.GAME_OVER, GameTable.TableState.DIFFICULTY_SELECT]:
		table._table_state = state
		for index in range(8):
			_click_signal()
		check(scare._click_times.is_empty() and not scare._start_queued, "non-idle table state %d rejects spam" % state)
	table._table_state = GameTable.TableState.MENU
	main._greeting_active = true
	for index in range(8):
		_click_signal()
	check(scare._click_times.is_empty(), "the intro cannot queue a jumpscare")
	main._greeting_active = false
	main.pause_menu.open()
	for index in range(8):
		_click_signal()
	check(scare._click_times.is_empty(), "Pause cannot queue a jumpscare")
	main.pause_menu.close()
	_click_signal()
	await settle(1.6)
	_click_signal()
	check(scare._click_times.size() == 1 and not scare.active, "slow clicks expire rather than accumulating forever")
	scare._click_times.clear()
	await settle(0.2)
	var actor := table.dealer_satan
	var camera := main.main_camera
	var pose := camera.transform
	var actor_pose := actor.transform
	var original_layers := actor.layers
	var original_shaded := actor.shaded
	var mask := camera.cull_mask
	var environment := camera.environment
	var canvas_visibility := {}
	var overlay_visibility := {}
	for path in ["CanvasLayer", "CanvasLayer2"]:
		var overlay := camera.get_node(path) as CanvasLayer
		overlay_visibility[overlay] = overlay.visible
	var lens_material := main.dirty_lens.material
	var screen_effect := camera.get_node("CanvasLayer2/ColorRect") as ColorRect
	var screen_material := screen_effect.material
	var inventory := CollectionManager.collection.duplicate(true)
	var amount := GameCurrency.get_coin_cents()
	for index in range(scare.clicks_required - 1):
		await _click_real()
		if index + 1 == ceili(float(scare.clicks_required) * 0.5):
			var stream = main._satan_stream
			check(stream.active and stream.particles.emitting and stream.piss_sfx.playing,
				"half of the required real picked clicks starts the supplied particles and sound")
			check(stream.source_position.y < actor.global_position.y and stream.target_position.y < camera.global_position.y - 1.0,
				"the stream starts at lower Satan and aims at the player's lower body")
			check(stream.trajectory_position(stream.flight_seconds).distance_to(stream.target_position) < 0.001,
				"the ballistic trajectory lands at the lower player target")
			var surface := table.get_node("table/Cube") as MeshInstance3D
			var bounds := surface.global_transform * surface.get_aabb()
			var clears_table := true
			for sample_index in range(31):
				var point: Vector3 = stream.trajectory_position(stream.flight_seconds * sample_index / 30.0)
				if point.x >= bounds.position.x and point.x <= bounds.end.x and point.z >= bounds.position.z and point.z <= bounds.end.z:
					clears_table = clears_table and point.y > bounds.end.y + 0.04
			check(clears_table, "the stream clears the actual table surface throughout its crossing")
			await settle(0.3)
			await _capture("half-click-stream")
	check(not scare.active and not main._jumpscare_active, "clicks below the threshold leave Satan idle")
	await _click_real()
	check(scare.active and main._jumpscare_active, "the final required real picked click starts the jumpscare")
	check(AchievementManager.is_unlocked(AchievementManager.SATAN_JUMPSCARE),
		"the actual jumpscare unlocks its Steam achievement")
	check(not main._satan_stream.active and not main._satan_stream.particles.visible and not main._satan_stream.piss_sfx.playing,
		"the full jumpscare immediately removes the stream and stops its sound")
	if not scare.active:
		_finish()
		return
	check(camera.global_position.distance_to(actor.global_position) < 0.85, "the actual Satan sprite fills the view directly in front of the camera")
	check(actor.texture == scare.LAUGH_SHEET, "ordinary hover cannot overwrite the jumpscare's laughing sprite")
	check(scare._sound.playing and is_instance_valid(scare._light), "the jumpscare sound and dedicated strobe start together")
	check(not main.blood_overlay.active, "the blood border waits for waking up rather than covering the close-up")
	canvas_visibility = scare._canvas_visibility.duplicate()
	check(overlay_visibility.keys().all(func(overlay): return overlay.visible == overlay_visibility[overlay])
		and main.dirty_lens.material == lens_material and screen_effect.material == screen_material,
		"lens and screen overlays retain their visibility and materials when the jumpscare starts")
	var first_camera_pose := camera.transform
	var first_actor_pose := actor.global_transform
	await get_tree().process_frame
	await get_tree().process_frame
	check(not camera.transform.is_equal_approx(first_camera_pose) and not actor.global_transform.is_equal_approx(first_actor_pose), "both Satan and the camera independently shake")
	var lit := false
	var dark := false
	var captured := false
	var overlays_preserved := true
	while scare.active and not scare._recovering:
		overlays_preserved = overlays_preserved and overlay_visibility.keys().all(func(overlay): return overlay.visible == overlay_visibility[overlay])
		lit = lit or scare._light.visible
		dark = dark or not scare._light.visible
		if not captured and scare._light.visible and DisplayServer.get_name() != "headless":
			captured = true
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png("res://satan-jumpscare-preview.png")
		_spam_input()
		await get_tree().process_frame
	check(lit and dark, "the actual light alternates between lit and dark during the scare")
	check(overlays_preserved, "lens and screen overlays stay visible throughout the close-up")
	check(scare.active and scare._recovering and main._jumpscare_active and finished_count == 0, "the scare flows into waking up without releasing input or emitting finished")
	check(main.blood_overlay.active and main.blood_overlay.blood_rect.is_visible_in_tree(), "waking up on the floor triggers the blood border underneath the preserved effects")
	check(is_equal_approx(camera.global_position.y, scare._floor_y + scare.floor_eye_height)
		and (-camera.global_basis.z).dot(Vector3.UP) > 0.99,
		"the player wakes just above the actual hub floor looking at the ceiling")
	check(camera.cull_mask == mask and camera.environment == environment and not is_instance_valid(scare._light), "the room returns and the strobe disappears before waking up")
	check(actor.transform.is_equal_approx(actor_pose) and actor.layers == original_layers and actor.texture != scare.LAUGH_SHEET, "Satan returns to his place while the player remains on the floor")
	check(not main._can_turn() and not main._can_travel_between_rooms() and not main._can_open_journal()
		and main.pause_menu._cinematic_locked and table._journal_input_blocked
		and not table.satan_hover_area.input_ray_pickable and not main.level_progress._enabled
		and not main.access_key_tray._enabled, "all navigation, interaction, HUD and pause controls stay locked while waking")
	await _capture("wakeup-floor")
	var floor_pose := camera.global_transform
	_spam_input()
	await settle(0.15)
	check(camera.global_transform.is_equal_approx(floor_pose), "the camera holds the lying pose before starting to get up")
	var rose_gradually := false
	var monotonic_height := true
	var controls_stayed_locked := true
	var previous_height := camera.global_position.y
	var captured_rising := false
	while scare.active:
		_spam_input()
		overlays_preserved = overlays_preserved and overlay_visibility.keys().all(func(overlay): return overlay.visible == overlay_visibility[overlay])
		controls_stayed_locked = controls_stayed_locked and main._jumpscare_active and main.pause_menu._cinematic_locked \
			and not main.pause_menu.visible and not main.journal.is_active() and main._pending_direction == 0 \
			and table._journal_input_blocked and not table.satan_hover_area.input_ray_pickable \
			and canvas_visibility.keys().all(func(canvas): return not canvas.visible)
		var height := camera.global_position.y
		monotonic_height = monotonic_height and height >= previous_height - 0.001
		previous_height = height
		if height > floor_pose.origin.y + 0.1 and height < pose.origin.y - 0.1:
			rose_gradually = true
			if not captured_rising and height > lerpf(floor_pose.origin.y, pose.origin.y, 0.45):
				captured_rising = true
				await _capture("getting-up")
		await get_tree().process_frame
	check(rose_gradually and monotonic_height, "the camera gradually rises from the floor toward the original eye height")
	check(controls_stayed_locked and finished_count == 1, "input stays blocked throughout getting up and finishes exactly once")
	check(main.blood_overlay.active and main.blood_overlay.blood_rect.visible, "the blood border continues fading after the player has finished getting up")
	check(overlays_preserved and main.dirty_lens.material == lens_material and screen_effect.material == screen_material,
		"the same overlay effects persist throughout waking up and getting up")
	check(not main.pause_menu.visible and not main.journal.is_active() and main._pending_direction == 0, "spam and gameplay keys cannot interrupt recovery or leak into navigation")
	check(camera.transform.is_equal_approx(pose) and camera.cull_mask == mask and camera.environment == environment, "camera pose, render layers and environment restore exactly")
	check(actor.transform.is_equal_approx(actor_pose) and actor.layers == original_layers and actor.shaded == original_shaded and actor.texture != scare.LAUGH_SHEET, "Satan keeps his existing idle position and rendering state")
	check(canvas_visibility.keys().all(func(canvas): return canvas.visible == canvas_visibility[canvas]), "HUD visibility is restored after getting up")
	await settle()
	check(main._can_turn() and main._can_open_journal() and not main.pause_menu._cinematic_locked and table.satan_hover_area.input_ray_pickable, "normal controls and Satan picking recover after the scare")
	for index in range(12):
		_click_signal()
	await settle()
	check(not scare.active and scare._click_times.is_empty(), "continued spam cannot retrigger during cooldown")
	check(CollectionManager.collection == inventory and GameCurrency.get_coin_cents() == amount, "the scare never changes cards or currency")
	var lens_layer := camera.get_node("CanvasLayer") as CanvasLayer
	lens_layer.hide()
	scare._cooldown_until = 0
	for index in range(scare.clicks_required):
		_click_signal()
	await get_tree().process_frame
	await get_tree().process_frame
	check(scare.active, "a later spam burst can trigger again after cooldown")
	check(not lens_layer.visible and screen_effect.is_visible_in_tree(), "a previously hidden overlay stays hidden while the other overlay remains visible")
	scare.cancel()
	check(not scare.active and not main._jumpscare_active and camera.transform.is_equal_approx(pose), "cancelling during the close-up restores the camera immediately")
	check(not lens_layer.visible and screen_effect.is_visible_in_tree(), "cancelling preserves the original visibility of each overlay effect")
	lens_layer.visible = overlay_visibility[lens_layer]
	await settle()
	scare._cooldown_until = 0
	for index in range(scare.clicks_required):
		_click_signal()
	while not scare._recovering:
		await get_tree().process_frame
	await settle(scare.wakeup_floor_hold + scare.get_up_duration * 0.3)
	check(scare.active and camera.global_position.y > scare._floor_y + scare.floor_eye_height
		and camera.global_position.y < pose.origin.y, "the second recovery is mid-rise before a lobby interrupts")
	NetworkManager.current_lobby_id = 123
	NetworkManager.lobby_state_changed.emit()
	check(not scare.active and not main._jumpscare_active and not main.pause_menu._cinematic_locked and camera.transform.is_equal_approx(pose), "an incoming lobby cancels getting up and restores camera and input")
	check(not main.blood_overlay.active and not main.blood_overlay.blood_rect.visible, "lobby cancellation also clears the blood border")
	NetworkManager.current_lobby_id = 0
	main.queue_free()
	await settle()
	_finish()


func _finish() -> void:
	print("SATAN_JUMPSCARE_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
