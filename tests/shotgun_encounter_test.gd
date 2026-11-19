extends "res://tests/prisoner_dialogue_test.gd"

var encounter: Node3D
var table: GameTable
var costs: Dictionary = {}


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute("res://test-user/shotgun")
	CollectionManager.clear_profile_state()
	DeckManager.clear_profile_state()
	GameCurrency.clear_profile_state()
	GameCurrency.set_process(false)
	PlaytimeManager.set_process(false)
	PlaytimeManager.encounter_completed = true
	Localization.set_locale("de")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	await _load_main()
	check(not encounter.gun.visible and not main.level_progress.shotgun_rack.visible, "unowned shotgun has no rack or camera model")
	await _open_rack()
	await _sample_cost("unowned-visor")
	for id: String in CollectionManager.RITUAL_CARD_IDS:
		CollectionManager.add_card(id)
		CollectionManager.place_vault_ritual_card(id, CollectionManager.RITUAL_CARD_IDS.find(id))
	check(CollectionManager.claim_vault_ritual_shotgun(), "ritual grants the real saved shotgun")
	check(encounter.gun.visible and main.level_progress.shotgun_rack.visible, "the ownership signal immediately mounts the shotgun by the clicker")
	check(not CollectionManager.is_clicker_unlocked(), "fixture tests pickup without a Clicker card")
	CollectionManager.reload_profile()
	check(encounter.gun.visible, "ownership survives profile reload")
	await _open_rack()
	await _sample_cost("owned-rack")
	await _capture("rack")
	var gun_point := _gun_point()
	check(viewport.get_visible_rect().has_point(gun_point) and main.level_progress._pointer_hits_shotgun(gun_point), "mounted gun is visible and mesh-pickable within the visor")
	main.pause_menu.open()
	_button(MOUSE_BUTTON_LEFT, gun_point)
	await _settle()
	check(not encounter.held, "Pause blocks pickup")
	main.pause_menu.close()
	await _open_rack()
	gun_point = _gun_point()
	var coins_before := GameCurrency.get_coin_cents()
	_button(MOUSE_BUTTON_LEFT, gun_point)
	check(encounter.held and encounter.shots_fired == 0, "a real rack click equips without firing or requiring Clicker ownership")
	await _settle(0.4)
	await _sample_cost("held")
	check(encounter.gun.get_parent() == main.main_camera and not main.level_progress.is_expanded(), "the same model moves to the camera and the visor folds away")
	await _capture("held")
	check(not main._satan_jumpscare_context_is_safe(), "holding the shotgun disables ordinary Satan click reactions")
	_button(MOUSE_BUTTON_LEFT, Vector2(20, 400))
	await _settle()
	check(encounter.shots_fired == 0, "clicking away from Satan cannot fire")
	main.pause_menu.open()
	_button(MOUSE_BUTTON_LEFT, _satan_point())
	await _settle()
	check(encounter.shots_fired == 0, "Pause blocks shooting")
	main.pause_menu.close()
	await _settle()
	GameCurrency.set_training_session(self, true)
	_button(MOUSE_BUTTON_LEFT, _satan_point())
	check(encounter.shots_fired == 0, "training blocks story shots")
	GameCurrency.set_training_session(self, false)
	NetworkManager.current_lobby_id = 123
	_button(MOUSE_BUTTON_LEFT, _satan_point())
	check(encounter.shots_fired == 0, "an online lobby blocks story shots")
	NetworkManager.current_lobby_id = 0
	NetworkManager._joining_lobby_id = 123
	_button(MOUSE_BUTTON_LEFT, _satan_point())
	check(encounter.shots_fired == 0, "a pending lobby operation blocks story shots")
	NetworkManager._joining_lobby_id = 0
	main._request_turn(1)
	await _wait_until(func(): return main._phase == MainScene.Phase.IDLE)
	_button(MOUSE_BUTTON_LEFT, Vector2(640, 360))
	check(encounter.shots_fired == 0, "looking at another hub side cannot fire")
	main._request_turn(-1)
	await _wait_until(func(): return main._phase == MainScene.Phase.IDLE)
	await _settle()
	await _open_rack()
	var clicker_point := main.main_camera.unproject_position(main.level_progress.coin_button.global_position)
	CollectionManager.add_card("clicker")
	var before_click := GameCurrency.get_coin_cents()
	_button(MOUSE_BUTTON_LEFT, clicker_point)
	check(GameCurrency.get_coin_cents() > before_click and encounter.shots_fired == 0, "the clicker still awards coins without firing the held weapon")
	coins_before = GameCurrency.get_coin_cents()
	_move_pointer(Vector2(20, 400))
	await _settle(0.35)
	var satan_point := _satan_point()
	check(table._is_satan_under_pointer(satan_point), "the actual Satan pick area is reachable in the normal player view")
	_button(MOUSE_BUTTON_LEFT, satan_point)
	check(encounter.shots_fired == 1 and encounter.is_busy(), "clicking Satan fires exactly the first shot")
	check(encounter.gun.get_node("ShotSound").playing and encounter.gun.get_node("Muzzle/Flash").visible, "shot starts sound and a muzzle flash")
	check(table.dealer_satan.texture == table.SATAN_PANIC_TEXTURE and table.dealer_satan.hframes == 2 and table.dealer_satan.loop, "first hit loops the supplied two-frame Panic animation")
	check(not main._can_turn() and not main.level_progress._enabled, "movement and the visor are blocked during the shot and dialogue")
	for index in range(5):
		_button(MOUSE_BUTTON_LEFT, satan_point)
	check(encounter.shots_fired == 1, "rapid repeat clicks during recoil cannot skip Panic")
	check(await _wait_until(func(): return is_instance_valid(encounter.dialogue) and encounter.dialogue.is_dialog_open()), "the first shot opens Satan's dialogue automatically")
	var conversation: AngelDialogue = encounter.dialogue
	check(not conversation._uses_laughing_text() and table.dealer_satan.texture == table.SATAN_PANIC_TEXTURE, "Satan remains panicked while talking")
	for locale: String in Localization.SUPPORTED_LOCALES:
		Localization.set_locale(locale)
		check(conversation._body_label.text == Localization.text(conversation._message) and (locale == "de" or conversation._body_label.text != conversation._message), "shotgun dialogue is localized in " + locale)
	Localization.set_locale("de")
	conversation._advance_dialog_text(100)
	await _settle(0.3)
	await _capture("panic-dialogue")
	var panic_frame: int = table.dealer_satan.frame
	await _settle(0.13)
	check(table.dealer_satan.frame != panic_frame, "the supplied Panic sheet advances during the dialogue")
	_button(MOUSE_BUTTON_LEFT, satan_point)
	check(encounter.shots_fired == 1 and conversation._sentence_index == 1, "clicking Satan during the conversation advances only text")
	conversation._advance_dialog_text(100)
	_button(MOUSE_BUTTON_LEFT, satan_point)
	check(encounter.shots_fired == 1, "the dialogue-closing click cannot also fire")
	check(await _wait_until(func(): return not encounter.is_busy()), "dialogue dismissal releases movement and the second shot")
	await _settle()
	_move_pointer(Vector2(20, 400))
	await _settle()
	check(table.dealer_satan.texture == table.SATAN_PANIC_TEXTURE, "hover changes cannot overwrite Panic after the dialogue")
	table.set_satan_stream_laughing(true)
	check(table.dealer_satan.texture == table.SATAN_PANIC_TEXTURE, "a competing laughter request cannot overwrite the story reaction")
	table.set_satan_stream_laughing(false)
	await _capture("panic-ready")
	_button(MOUSE_BUTTON_LEFT, _satan_point())
	check(encounter.shots_fired == 2 and table.dealer_satan.texture == table.SATAN_KILL_TEXTURE, "the next aimed click fires and starts the supplied Kill animation")
	check(table.dealer_satan.hframes == 9 and not table.dealer_satan.loop, "all nine Kill frames play once")
	for index in range(5):
		_button(MOUSE_BUTTON_LEFT, _satan_point())
	await _settle(0.25)
	await _capture("kill-playing")
	check(await _wait_until(func(): return not encounter.is_busy()), "the full Kill animation completes and unlocks movement")
	check(table.dealer_satan.frame == 8 and not table.dealer_satan.is_processing(), "the encounter stays busy until the last Kill frame has actually played")
	await _settle(0.2)
	check(table.dealer_satan.frame == 8 and not table.dealer_satan.is_processing(), "Kill holds its final frame without returning to idle")
	_button(MOUSE_BUTTON_LEFT, _satan_point())
	check(encounter.shots_fired == 2 and not is_instance_valid(encounter.dialogue), "the finished encounter cannot fire a third shot or reopen dialogue")
	await _capture("kill-finished")
	_button(MOUSE_BUTTON_RIGHT, Vector2(640, 360))
	check(not encounter.held and encounter.gun.get_parent() == main.level_progress.shotgun_socket, "right click returns the shotgun to the rack")
	check(GameCurrency.get_coin_cents() == coins_before and not table._game_over, "story shooting awards no currency and does not end a card match")
	main.queue_free()
	await _settle()
	await _load_main()
	check(encounter.gun.visible and not encounter.held and encounter.shots_fired == 0, "a reloaded hub restores the owned rack with a fresh encounter")
	check(table.dealer_satan.texture != table.SATAN_KILL_TEXTURE, "normal hub loading restores Satan's normal pose")
	main.queue_free()
	await _settle()
	viewport.queue_free()
	await get_tree().process_frame
	if not costs.is_empty():
		var report := FileAccess.open("res://test-user/shotgun/costs.json", FileAccess.WRITE)
		report.store_string(JSON.stringify(costs, "  "))
	print("SHOTGUN_ENCOUNTER_TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)


func _load_main() -> void:
	main = load("res://scenes/main/Main.tscn").instantiate() as MainScene
	main.greeting_enabled = false
	main.wakeup_blur_duration = 0.01
	main.mouse_tilt_strength = 0
	main.debug_interaction_clicks = false
	main.rotation_duration = 0.04
	main.settle_duration = 0.03
	viewport.add_child(main)
	encounter = main.shotgun_encounter
	table = main.scene_pivot.get_node("GameTable")
	await _settle(0.5)


func _open_rack() -> void:
	_move_pointer(Vector2(640, 1))
	main.level_progress.set_pointer_position(Vector2(640, 1))
	await _settle(0.4)


func _gun_point() -> Vector2:
	var mesh: MeshInstance3D = encounter.gun.get_node("Model/PSX_DoubleBarrelShotgun/SM_DoubleBarrelShotgun")
	return main.main_camera.unproject_position(mesh.global_transform * mesh.get_aabb().get_center())


func _satan_point() -> Vector2:
	return main.main_camera.unproject_position(table.satan_hover_area.global_position)


func _capture(stage: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://test-user/shotgun/%s.png" % stage)


func _sample_cost(stage: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var times: Array[float] = []
	for index in range(30):
		await RenderingServer.frame_post_draw
	var previous := Time.get_ticks_usec()
	for index in range(30):
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		times.append(float(now - previous) / 1000.0)
		previous = now
	times.sort()
	var average := 0.0
	for value in times:
		average += value / times.size()
	costs[stage] = {
		"render_frame_ms_average": average,
		"render_frame_ms_p95": times[int(times.size() * 0.95)],
		"draw_calls": viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"objects": viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME),
		"primitives": viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
	}
