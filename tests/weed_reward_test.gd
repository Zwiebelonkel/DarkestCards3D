extends Node

var checks := 0
var failures := 0
var viewport: SubViewport
var main: MainScene
var weed: Node3D
var table: GameTable
var captures: Array[String] = []
var render := false


class RejectingWallet:
	extends "res://scripts/GameCurrency.gd"
	func _ready() -> void:
		set_process(false)
	func save() -> bool:
		return false


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
	print(("PASS " if condition else "FAIL ") + label)


func settle(seconds: float = 0.05) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame


func wait_landed() -> bool:
	var deadline := Time.get_ticks_msec() + 4000
	while not weed.landed and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return weed.landed


func pointer() -> Vector2:
	return main.main_camera.unproject_position(weed.global_transform * Vector3(0, 0.0552, 0))


func move_pointer(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	viewport.push_input(event, true)
	await get_tree().physics_frame
	await settle()


func click_real() -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = pointer()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		viewport.push_input(event, true)
		await get_tree().physics_frame
	await settle()


func click_signal(button: MouseButton = MOUSE_BUTTON_LEFT, pressed: bool = true) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	weed.area.input_event.emit(main.main_camera, event, Vector3.ZERO, Vector3.ZERO, 0)


func capture(label: String, target: SubViewport = null) -> void:
	if not render:
		return
	if target == null:
		target = viewport
	await RenderingServer.frame_post_draw
	var path := "res://test-user/weed/" + label + ".png"
	check(target.get_texture().get_image().save_png(path) == OK, "capture " + label)
	captures.append(path)


func make_main() -> void:
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.greeting_enabled = false
	main.mouse_tilt_strength = 0.0
	main.wakeup_blur_duration = 0.1
	viewport.add_child(main)
	table = main.scene_pivot.get_node("GameTable") as GameTable
	weed = main.weed_pickup


func _run() -> void:
	if not GameCurrency.save_path.begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	render = DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute("res://test-user/weed")
	GameCurrency.set_process(false)
	GameCurrency.reset_progression()
	GameCurrency.level = 6
	GameCurrency.save()
	var wallet := RejectingWallet.new()
	add_child(wallet)
	check(not wallet.consume_weed_reward(), "no qualifying match win means there is no reward to consume")
	wallet.level = 7
	wallet.weed_reward_unlocked = true
	check(not wallet.consume_weed_reward() and not wallet.weed_consumed, "failed persistence keeps the reward unconsumed")
	wallet.free()
	_test_win_gate()
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	make_main()
	await settle(0.5)
	check(not weed.model.visible and not weed.dropping and not main.get_node("Hint1").visible, "before a qualifying win the weed and Hint1 are hidden")
	var result := GameCurrency.add_xp(GameCurrency.get_xp_required())
	await settle(0.15)
	check(GameCurrency.level == 7 and result["levels_gained"] == 1 and not weed.dropping, "level seven alone cannot drop the package")
	GameCurrency.award_match("loss")
	GameCurrency.award_match("draw")
	await settle()
	check(not GameCurrency.weed_reward_unlocked and not weed.model.visible, "losses and draws at level seven cannot drop the package")
	table._table_state = GameTable.TableState.PLAYING
	table._last_match_outcome = GameTable.MatchOutcome.WIN
	table._grant_match_rewards()
	check(not GameCurrency.weed_reward_unlocked, "winning a normal match at player level seven cannot unlock the package")
	GameCurrency.story_completed_level = 5
	table._local_mode = "story"
	table._story_level = 6
	table._match_reward_granted = false
	table._grant_match_rewards()
	check(not GameCurrency.weed_reward_unlocked, "the actual story-six victory path keeps the package locked")
	table._story_level = 7
	table._match_reward_granted = false
	table._grant_match_rewards()
	var coins_after_win := GameCurrency.get_coin_cents()
	table._grant_match_rewards()
	check(GameCurrency.get_coin_cents() == coins_after_win, "the actual table grants a repeated result only once")
	await settle(0.15)
	check(GameCurrency.weed_reward_unlocked and not weed.dropping and not weed.model.visible, "winning story level seven unlocks the package but waits until the match has exited")
	table._table_state = GameTable.TableState.MENU
	await settle(0.15)
	check(weed.dropping, "returning to the idle table after story seven starts the drop")
	check(weed.model.position.y > weed._rest.origin.y + 0.1 and not weed.area.input_ray_pickable, "the object drops from above and cannot be clicked mid-fall")
	await settle(0.45)
	await capture("drop")
	check(await wait_landed(), "the falling object settles on the table")
	var body: AABB = weed.mesh.global_transform * weed.mesh.get_aabb()
	var table_mesh := table.get_node("table/Cube") as MeshInstance3D
	var tabletop := (table_mesh.global_transform * table_mesh.get_aabb()).end.y
	check(body.position.y >= tabletop and body.position.y - tabletop < 0.008, "the real mesh rests on the authored tabletop with less than 8mm clearance")
	check(weed.effect_duration == 60.0 and not weed.active and not weed.overlay.visible, "landing leaves the sixty-second effect inactive")
	await capture("landed")
	await move_pointer(pointer())
	check(weed.hovered and weed.mesh.material_overlay == weed._outline, "real pointer picking applies the yellow outline")
	check(weed._outline.get_shader_parameter("outline_color") == Color(1.0, 0.85, 0.0, 1.0), "hover uses the existing yellow interaction color")
	await capture("hover")
	await move_pointer(Vector2(8, 8))
	check(not weed.hovered and weed.mesh.material_overlay == weed._original_overlay, "leaving the weed restores its original material")
	click_signal(MOUSE_BUTTON_RIGHT)
	click_signal(MOUSE_BUTTON_LEFT, false)
	check(not weed.active and not GameCurrency.weed_consumed, "right clicks and releases do not consume the weed")
	main.pause_menu.open()
	await settle()
	click_signal()
	check(not weed.active and not weed.area.input_ray_pickable and not weed.hovered, "Pause blocks pickup and clears hover")
	main.pause_menu.close()
	table._table_state = GameTable.TableState.PLAYING
	await settle()
	click_signal()
	check(not weed.active and not weed.area.input_ray_pickable, "an active match cannot consume the reward")
	table._table_state = GameTable.TableState.MENU
	NetworkManager.current_lobby_id = 123
	await settle()
	click_signal()
	check(not weed.active and not weed.area.input_ray_pickable, "a multiplayer lobby cannot consume the reward")
	NetworkManager.current_lobby_id = 0
	await settle()
	await settle(0.6)
	var hearing := table._get_or_create_lowpass()
	var master := AudioServer.get_bus_index("Master")
	var sentinel := AudioEffectEQ10.new()
	AudioServer.add_bus_effect(master, sentinel)
	var before_count := AudioServer.get_bus_effect_count(master)
	var before_volume := AudioServer.get_bus_volume_db(master)
	await move_pointer(pointer())
	await click_real()
	check(weed.active and GameCurrency.weed_consumed and not weed.model.visible and not weed.area.input_ray_pickable, "a real picked left click saves consumption and immediately removes the weed")
	check(weed.overlay.visible and weed.effect_rect.mouse_filter == Control.MOUSE_FILTER_IGNORE and main.get_node("Hint1").visible, "the camera filter and authored Hint1 become visible without blocking input")
	var hint_material := main.get_node("Hint1").material_override as StandardMaterial3D
	check(hint_material != null and hint_material.emission_enabled and hint_material.emission_texture != null
		and hint_material.emission_energy_multiplier == 3.0 and hint_material.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED,
		"Hint1 has a three-times emissive arrow map while retaining its authored orientation")
	check(AudioServer.get_bus_effect_count(master) == before_count + 1 and weed._high_cut.cutoff_hz > 1200.0, "the dedicated Master high cut starts open for a gradual fade-in")
	check(AudioServer.get_bus_effect(master, 0) == hearing and AudioServer.get_bus_effect(master, before_count - 1) == sentinel, "the gunshot hearing filter and unrelated EQ remain intact")
	var elapsed: float = weed._effect_elapsed
	click_signal()
	check(weed._effect_elapsed >= elapsed and AudioServer.get_bus_effect_count(master) == before_count + 1, "repeat clicks never restart the timer or duplicate audio effects")
	await settle(0.7)
	var initial_strength := float(weed._effect_material.get_shader_parameter("effect_mix"))
	check(initial_strength > 0.0 and initial_strength < 0.2 and main.get_node("Hint1").modulate.a < 0.2,
		"the filter and emissive arrows gradually fade in over five seconds")
	await capture("fade-in")
	weed._process(weed.fade_in_duration)
	check(is_equal_approx(weed._high_cut.cutoff_hz, 1200.0) and is_equal_approx(float(weed._effect_material.get_shader_parameter("effect_mix")), 1.0),
		"the full visual effect and 1200 Hz high cut are reached after fading in")
	check(main.music.stream is AudioStreamSynchronized and is_equal_approx(main.music._mix, 1.0), "active weed replaces theme4 with the synchronized cursed arrangement")
	await capture("active")
	var active_cost := await sample_cost()
	# Compare the same camera and consumed-object state, without UI motion or
	# different geometry obscuring the screen-pass cost.
	weed.overlay.hide()
	main.get_node("Hint1").hide()
	await settle(0.1)
	var baseline := await sample_cost()
	weed.overlay.show()
	main.get_node("Hint1").show()
	main.pause_menu.open()
	await settle()
	var remaining: float = weed.remaining
	await settle(0.15)
	check(is_equal_approx(weed.remaining, remaining), "pausing also pauses the effect's countdown")
	main.pause_menu.close()
	weed._process(maxf(weed.remaining - weed.fade_out_duration * 0.5, 0.0))
	var ending_strength := float(weed._effect_material.get_shader_parameter("effect_mix"))
	check(ending_strength > 0.0 and ending_strength < 1.0 and weed._high_cut.cutoff_hz > 1200.0,
		"the final five seconds smoothly remove the filter, hint and high cut")
	await capture("fade-out")
	check(weed.active and main.get_node("Hint1").visible and weed._high_cut != null, "filter, high cut and Hint1 remain active until the end of sixty seconds")
	weed._process(weed.remaining + 0.1)
	check(not weed.active and not weed.overlay.visible and not main.get_node("Hint1").visible, "the filter and Hint1 disappear when the effect ends")
	check(AudioServer.get_bus_effect_count(master) == before_count and AudioServer.get_bus_effect(master, before_count - 1) == sentinel and AudioServer.get_bus_volume_db(master) == before_volume, "expiry removes only the owned high cut and preserves audio settings")
	await settle(0.35)
	check(is_zero_approx(main.music._mix), "expiry crossfades back to theme4 within 0.3 seconds")
	AudioServer.remove_bus_effect(master, before_count - 1)
	GameCurrency.load_currency()
	check(GameCurrency.weed_consumed, "consumption survives saving and loading the profile")
	main.queue_free()
	await settle()
	make_main()
	await settle(0.3)
	check(not weed.model.visible and not weed.dropping, "re-entering the hub cannot respawn a consumed reward")
	main.queue_free()
	await settle()
	GameCurrency.reset_progression()
	GameCurrency.level = 12
	GameCurrency.save()
	make_main()
	await settle(0.3)
	check(not weed.model.visible and not weed.dropping, "an existing high-level profile still needs a qualifying win")
	check(not GameCurrency.award_story_win(1).is_empty() and not GameCurrency.weed_reward_unlocked, "an early story victory cannot unlock the package at a high player level")
	GameCurrency.story_completed_level = 6
	GameCurrency.award_story_win(7)
	check(await wait_landed(), "the high-level profile receives its package after winning story seven")
	await move_pointer(pointer())
	await click_real()
	check(weed.active, "another fresh profile can consume its own reward")
	GameCurrency.story_completed_level = 0
	GameCurrency.weed_reward_unlocked = false
	main.pause_menu.open()
	main.pause_menu._open_settings()
	var settings := main.pause_menu.settings_menu
	settings.cheats_toggle.button_pressed = true
	await settle(0.15)
	(settings.get_node("CenterContainer/PanelContainer/ScrollContainer") as ScrollContainer).ensure_control_visible(settings.cheat_weed_button)
	await settle(0.1)
	check(settings.cheat_weed_button is Button and settings.cheat_weed_button.is_visible_in_tree(), "the admin section exposes the drop-package button")
	await capture("admin-menu")
	var button_point := settings.cheat_weed_button.get_global_rect().get_center()
	check(viewport.get_visible_rect().has_point(button_point), "the scrolled admin drop button is reachable on screen")
	var button_motion := InputEventMouseMotion.new()
	button_motion.position = button_point
	viewport.push_input(button_motion, true)
	for pressed in [true, false]:
		var button_click := InputEventMouseButton.new()
		button_click.position = button_point
		button_click.button_index = MOUSE_BUTTON_LEFT
		button_click.pressed = pressed
		viewport.push_input(button_click, true)
		await get_tree().process_frame
	check(GameCurrency.admin_weed_drop_pending and not weed.dropping, "the admin button queues a drop while the menu is open")
	settings.close()
	main.pause_menu.close()
	check(await wait_landed(), "the admin package drops again despite prior consumption and no story completion")
	await move_pointer(pointer())
	await click_real()
	check(weed.active and GameCurrency.weed_consumed and GameCurrency.story_completed_level == 0,
		"the admin pickup activates the effect without changing story progress")
	var owned_filter: AudioEffect = weed._high_cut
	main.queue_free()
	await settle()
	var retained := false
	for index in range(AudioServer.get_bus_effect_count(master)):
		retained = retained or AudioServer.get_bus_effect(master, index) == owned_filter
	check(not retained, "leaving the scene during an active effect removes its audio filter")
	owned_filter = null
	hint_material = null
	hearing = null
	sentinel = null
	if render:
		await capture_cardinals()
	var report := {"checks": checks, "failures": failures, "captures": captures,
		"baseline": baseline, "active": active_cost, "audio_driver": AudioServer.get_driver_name()}
	var file := FileAccess.open("res://test-user/weed/review_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("WEED_REWARD_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _test_win_gate() -> void:
	var wallet := RejectingWallet.new()
	add_child(wallet)
	wallet.level = 7
	wallet.story_completed_level = 6
	var before := wallet.get_coin_cents()
	check(wallet.award_story_win(7).is_empty() and not wallet.weed_reward_unlocked and wallet.get_coin_cents() == before and wallet.story_completed_level == 6,
		"a failed victory save rolls back rewards and package eligibility together")
	wallet.set_training_session(self, true)
	check(wallet.award_match("win").is_empty() and not wallet.weed_reward_unlocked, "training cannot unlock the package")
	wallet.set_training_session(self, false)
	wallet.free()
	var legacy := ConfigFile.new()
	legacy.set_value("progression", "level", 12)
	legacy.set_value("progression", "weed_consumed", true)
	legacy.save("res://test-user/legacy-weed.cfg")
	wallet = RejectingWallet.new()
	wallet.save_path = "res://test-user/legacy-weed.cfg"
	add_child(wallet)
	wallet.load_currency()
	check(wallet.weed_consumed and wallet.weed_reward_unlocked, "older consumed rewards remain evidence of a prior trip")
	legacy.set_value("progression", "weed_consumed", false)
	legacy.save(wallet.save_path)
	wallet.load_currency()
	check(not wallet.weed_reward_unlocked, "older unconsumed high-level saves do not gain a package without winning")
	legacy.set_value("story", "completed_level", 7)
	legacy.save(wallet.save_path)
	wallet.load_currency()
	check(wallet.weed_reward_unlocked, "older saves that already beat story seven receive the unclaimed reward")
	wallet.free()


func sample_cost() -> Dictionary:
	var times: Array[float] = []
	var start := Time.get_ticks_usec()
	for index in range(30):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - start) / 1000.0)
		start = now
	times.sort()
	var total := 0.0
	for value in times:
		total += value
	return {"mean_frame_ms": total / times.size(), "p95_frame_ms": times[28],
		"draw_calls": viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"objects": viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME)}


func capture_cardinals(kind: String = "weed") -> void:
	var view := SubViewport.new()
	view.size = Vector2i(800, 800)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var prop: Node3D = load("res://scenes/props/WeedPickup.tscn").instantiate()
	view.add_child(prop)
	prop.set_process(false)
	if kind != "weed":
		prop._select_kind(kind)
	prop.model.show()
	var camera := Camera3D.new()
	view.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.9
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.16, 0.17, 0.19)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.7
	camera.environment = environment
	var light := DirectionalLight3D.new()
	view.add_child(light)
	light.rotation_degrees = Vector3(-60, -25, 0)
	for label: String in ["front", "back", "left", "right"]:
		var direction: Vector3 = {"front": Vector3(0, 0.6, 1), "back": Vector3(0, 0.6, -1),
			"left": Vector3(-1, 0.6, 0), "right": Vector3(1, 0.6, 0)}[label]
		camera.position = direction
		camera.look_at(Vector3(0, 0.055, 0))
		await settle(0.1)
		await capture(label, view)
	view.queue_free()
