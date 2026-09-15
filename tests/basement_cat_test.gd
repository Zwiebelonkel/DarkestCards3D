extends Node
## Exercises the encounter through Main's physical doors, D key and UI input.

const LIVING_TEXTURE := "res://assets/characters/cat.png"
const DEAD_TEXTURE := "res://assets/characters/catDead.png"
const SPARED_TEXTURE := "res://assets/characters/catSpare.png"

var checks := 0
var failures := 0
var viewport: SubViewport
var main: MainScene
var cat: BasementCatEncounter
var shots := 0
var shot_flash_seen := false
var shot_audio_started := false


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
	print(("PASS: " if condition else "FAIL: ") + message)


func _settle(seconds: float = 0.08) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().physics_frame
	await get_tree().process_frame


func _wait_until(predicate: Callable, timeout_ms: int = 10000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not bool(predicate.call()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/") or not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Use the isolated runner to protect player saves.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	CollectionManager.clear_profile_state()
	DeckManager.clear_profile_state()
	CardUpgradeManager.clear_profile_state()
	CollectionManager.add_card("basement_key")
	CollectionManager.add_card("black_market_access")
	SettingsManager.set_fullscreen(false)
	Localization.set_locale("en")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	_reset_currency()
	await _spawn_main()
	if cat == null or cat.actor == null or cat.presentation == null:
		check(false, "Main instantiates the basement cat, actor and choice presentation")
		_finish()
		return
	check(main.basement_cat == cat and cat.get_parent() == main.get_node("BasementRoom"), "the cat belongs to the permanent basement in Main's existing world")
	check(cat.actor.texture.resource_path == LIVING_TEXTURE and cat.actor.hframes == 2 and cat.actor.vframes == 1, "the living cat uses the two-frame 40 by 23 pixel walk sheet")
	await _check_unrelated_views()
	await _enter_basement()
	if main._active_room != 3:
		_finish()
		return
	check(main._active_side == 0 and cat.state == "unseen" and not cat.is_busy(), "basement arrival alone leaves the encounter waiting for a right turn")
	await _start_encounter(true)
	if cat.state != "choice":
		_finish()
		return
	await _check_choice_ui()
	await _check_save_failure()
	await _shoot_cat()
	await _check_shot_reload()
	await _check_spared_branch()
	_finish()


func _reset_currency() -> void:
	GameCurrency.clear_profile_state()
	GameCurrency.coins = 42.75
	check(GameCurrency.save(), "the isolated fresh profile saves successfully")


func _spawn_main() -> void:
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.mouse_tilt_strength = 0.0
	main.wakeup_blur_duration = 0.01
	main.rotation_duration = 0.22
	main.settle_duration = 0.08
	main.room_travel_duration = 0.7
	viewport.add_child(main)
	cat = main.get_node_or_null("BasementRoom/BasementCatEncounter") as BasementCatEncounter
	if cat != null and cat.presentation != null:
		cat.presentation.shot_fired.connect(_on_shot)
	_move_pointer(Vector2(-50, -50))
	await _settle(0.6)


func _destroy_main() -> void:
	main.queue_free()
	await _settle()


func _check_unrelated_views() -> void:
	for _turn in range(4):
		await _press_key(KEY_D)
		await _settle(0.4)
		check(cat.state == "unseen" and not cat.is_busy() and not cat.actor.visible, "hub cardinal view %d cannot start the basement encounter" % main._active_side)
	var area := _room_entrance(4)
	await _face_door(area.door)
	await _fly(area.door, 4)
	await _press_key(KEY_D)
	await _settle(0.4)
	check(main._active_room == 4 and main._active_side == 3 and cat.state == "unseen" and not cat.is_busy(), "the same right-facing view in the Black Market cannot trigger the cat")
	var door := main.get_node("BlackMarketRoom/ReturnDoor") as HospitalDoor
	await _face_door(door)
	await _fly(door, 0)


func _enter_basement() -> void:
	var entrance := _room_entrance(3)
	await _face_door(entrance.door)
	await _fly(entrance.door, 3)


func _start_encounter(test_pause: bool) -> void:
	await _press_key(KEY_D)
	check(main._phase != MainScene.Phase.IDLE and cat.state == "unseen", "the real D key starts a right turn without starting the cat during camera rotation")
	check(await _wait_until(func(): return cat.state == "walking"), "the cat starts walking only after the right turn settles")
	if cat.state != "walking":
		return
	var start := cat.actor.global_position
	check(main._active_side == 3 and cat.actor.visible and cat.is_busy(), "right-facing basement view reveals the moving cat and owns the encounter")
	check(not _choice_visible(), "the moral-choice UI waits until the cat finishes crossing the floor")
	check(not main._can_turn() and not main._can_travel_between_rooms() and not _any_crate_pickable(), "walking blocks turns, doorway travel and underlying crate interaction")
	if test_pause:
		main.pause_menu.open()
		await _settle()
		var paused_position := cat.actor.global_position
		await _settle(0.25)
		check(get_tree().paused and cat.state == "walking" and cat.actor.global_position.is_equal_approx(paused_position), "Pause freezes the walking cat in place")
		var blocked := cat.choose("shot")
		check(not bool(blocked.get("ok", false)) and GameCurrency.get_basement_cat_choice().is_empty(), "a paused queued choice cannot resolve the encounter")
		main.pause_menu.close()
		await _settle(0.08)
		NetworkManager.current_lobby_id = 123456
		main.pause_menu.open()
		var online_paused_position := cat.actor.global_position
		var online_paused_camera := main.main_camera.transform
		await _settle(0.3)
		check(not get_tree().paused and cat.actor.global_position.is_equal_approx(online_paused_position) and main.main_camera.transform.is_equal_approx(online_paused_camera), "the online pause overlay also freezes the cat and shared camera without pausing networking")
		NetworkManager.current_lobby_id = 0
		main.pause_menu.close()
	await _settle(0.25)
	check(cat.actor.global_position.distance_to(start) > 0.05, "the live cat advances from the back corner toward the player")
	check(await _wait_until(func(): return cat.state == "choice"), "arrival completes before the player receives the angel and Satan choice")
	check(await _wait_until(func(): return cat.presentation._can_accept_choice()), "the raised portraits and pistol finish their entrance before accepting input")
	await _settle()
	check(cat.actor.visible and cat.actor.texture.resource_path == LIVING_TEXTURE and _choice_visible(), "the cat stays alive in front of the player while the choice is displayed")


func _check_choice_ui() -> void:
	var angel := _angel_button()
	var devil := _devil_button()
	check(angel != null and devil != null, "both choices expose real pointer controls")
	if angel == null or devil == null:
		return
	check(angel.get_global_rect().get_center().x < viewport.size.x * 0.5 and devil.get_global_rect().get_center().x > viewport.size.x * 0.5, "the angel appears on the left and Satan on the right")
	check(cat.presentation._gun_mount.is_visible_in_tree() and is_equal_approx(cat.presentation._gun_mount.position.x, viewport.size.x * 0.5), "the same first-person pistol rises in the middle of the screen")
	_move_pointer(devil.get_global_rect().get_center())
	await _settle(0.15)
	var satan_text := _visible_text(cat.presentation).to_lower()
	check("shoot" in satan_text and ("1000" in satan_text or "1,000" in satan_text or "1.000" in satan_text), "hovering Satan explains the shot and the exact 1000 Soul Coin reward")
	_move_pointer(angel.get_global_rect().get_center())
	await _settle(0.15)
	var angel_text := _visible_text(cat.presentation).to_lower()
	check("live" in angel_text or "life" in angel_text, "hovering the angel explains sparing the cat's life")
	check(GameCurrency.get_basement_cat_choice().is_empty() and is_equal_approx(GameCurrency.coins, 42.75), "hovering either character has no monetary or permanent effect")
	await _capture("choice")
	await _press_key(KEY_D)
	check(main._active_side == 3 and main._phase == MainScene.Phase.IDLE and cat.state == "choice", "D cannot rotate the camera away from an unanswered choice")
	main.pause_menu.open()
	await _settle()
	var blocked := cat.choose("shot")
	check(get_tree().paused and not bool(blocked.get("ok", false)) and cat.state == "choice" and GameCurrency.get_basement_cat_choice().is_empty(), "Pause suspends the choice without accepting a queued shot")
	main.pause_menu.close()
	await _settle(0.15)
	check(cat.state == "choice" and _choice_visible(), "unpausing restores the unanswered choice")


func _check_save_failure() -> void:
	var original_path := GameCurrency.save_path
	var before := GameCurrency.get_coin_cents()
	GameCurrency.save_path = "res://test-user/missing-cat-save-directory/currency.cfg"
	await _click_at(_devil_button().get_global_rect().get_center())
	await _settle(0.15)
	GameCurrency.save_path = original_path
	check(GameCurrency.get_basement_cat_choice().is_empty() and GameCurrency.get_coin_cents() == before, "a failed profile save cannot award coins or commit a shot")
	check(cat.state == "choice" and cat.actor.visible and cat.actor.texture.resource_path == LIVING_TEXTURE and shots == 0, "save failure leaves the cat alive and the choice retryable without firing")


func _shoot_cat() -> void:
	var before := GameCurrency.get_coin_cents()
	var resting_position := cat.actor.global_position
	await _click_at(_devil_button().get_global_rect().get_center())
	check(GameCurrency.get_basement_cat_choice() == "shot" and GameCurrency.get_coin_cents() - before == 1000 * GameCurrency.CENTS_PER_COIN, "clicking Satan commits exactly 1000 Soul Coins with the permanent shot choice")
	check(cat.state == "shooting" and not main._can_turn() and not main._can_travel_between_rooms(), "the gun cinematic retains navigation ownership until its shot finishes")
	cat.presentation.choice_requested.emit("shot")
	cat.presentation.choice_requested.emit("spared")
	check(await _wait_until(func(): return shots == 1), "the shared gun presentation fires exactly once")
	check(shot_flash_seen and shot_audio_started, "the muzzle flash and shot sound begin on the exact world-impact signal")
	check(cat.actor.texture.resource_path == DEAD_TEXTURE and cat.actor.hframes == 1, "the shot impact immediately replaces the living sheet with Cat Dead")
	NetworkManager.current_lobby_id = 123456
	main.pause_menu.open()
	var paused_shot_position := cat.actor.global_position
	await _settle(0.75)
	check(not get_tree().paused and cat.state == "shooting" and cat.actor.global_position.is_equal_approx(paused_shot_position) and not cat.presentation.visible, "online pause suspends the knockback, recoil and shot timers together")
	NetworkManager.current_lobby_id = 0
	main.pause_menu.close()
	await _settle(0.14)
	check(cat.actor.global_position.distance_to(resting_position) > 0.1, "Cat Dead visibly flies away from the impact position")
	await _capture("shot")
	check(await _wait_until(func(): return cat.state == "shot" and not cat.is_busy()), "the shot sequence resolves and releases the camera")
	check(not cat.actor.visible and not _choice_visible() and main._can_turn() and main._can_travel_between_rooms(), "the dead cat and gun UI disappear and normal navigation resumes")
	check(shots == 1 and GameCurrency.get_coin_cents() - before == 1000 * GameCurrency.CENTS_PER_COIN, "duplicate callbacks cannot fire again, change the choice or duplicate its reward")
	await _press_key(KEY_D)
	await _settle(0.4)
	await _press_key(KEY_A)
	await _settle(0.4)
	check(cat.state == "shot" and not cat.actor.visible and not cat.is_busy(), "turning away and returning never brings the shot cat back")


func _check_shot_reload() -> void:
	var saved_coins := GameCurrency.get_coin_cents()
	await _destroy_main()
	GameCurrency.clear_profile_state()
	GameCurrency.load_currency()
	check(GameCurrency.get_basement_cat_choice() == "shot" and GameCurrency.get_coin_cents() == saved_coins, "save/load restores the permanent shot and the single reward together")
	await _spawn_main()
	await _enter_basement()
	await _press_key(KEY_D)
	await _settle(0.5)
	check(cat.state == "shot" and not cat.actor.visible and not cat.is_busy() and not _choice_visible(), "a freshly loaded basement never respawns the shot cat or its choice")
	check(GameCurrency.get_coin_cents() == saved_coins, "revisiting the loaded basement cannot award another 1000 Soul Coins")
	await _destroy_main()


func _check_spared_branch() -> void:
	_reset_currency()
	shots = 0
	shot_flash_seen = false
	shot_audio_started = false
	await _spawn_main()
	await _enter_basement()
	await _start_encounter(false)
	if cat.state != "choice":
		return
	var resting_position := cat.actor.global_position
	var before := GameCurrency.get_coin_cents()
	var gun_start_y := cat.presentation._gun_mount.position.y
	await _click_at(_angel_button().get_global_rect().get_center())
	check(GameCurrency.get_basement_cat_choice() == "spared" and GameCurrency.get_coin_cents() == before, "clicking the angel saves mercy without a coin reward")
	await _settle(0.18)
	check(cat.state == "sparing" and cat.presentation._gun_mount.position.y > gun_start_y + 1.0, "mercy visibly lowers the pistol below the screen before hiding it")
	check(await _wait_until(func(): return cat.state == "spared" and not cat.is_busy()), "the mercy animation stows the gun and ends the encounter")
	check(shots == 0 and cat.actor.visible and cat.actor.texture.resource_path == SPARED_TEXTURE and cat.actor.hframes == 2 and cat.actor.global_position.is_equal_approx(resting_position), "sparing never fires and leaves the cat standing there with its two-frame Cat Spare sheet")
	var cat_visible := true
	for local_point: Vector3 in [Vector3(-0.6, -0.345, 0), Vector3(0.6, -0.345, 0), Vector3(-0.6, 0.345, 0), Vector3(0.6, 0.345, 0)]:
		# The billboard faces the camera, so measure its camera-facing corners.
		var world_point := cat.actor.global_position + main.main_camera.global_basis.x * local_point.x + Vector3.UP * local_point.y
		cat_visible = cat_visible and viewport.get_visible_rect().grow(-5).has_point(main.main_camera.unproject_position(world_point))
	check(cat_visible, "the entire spared cat remains visible after the normal room camera returns")
	var spared_frame := cat.actor.frame
	check(await _wait_until(func(): return cat.actor.frame != spared_frame, 1600), "the spared cat continues animating while it stays in the basement")
	check(not _choice_visible() and main._can_turn() and main._can_travel_between_rooms(), "mercy dismisses the characters and gun and restores normal room navigation")
	await _capture("spared")
	var door := main.get_node("BasementRoom/ReturnDoor") as HospitalDoor
	await _face_door(door)
	await _fly(door, 0)
	await _enter_basement()
	await _press_key(KEY_D)
	await _settle(0.5)
	check(cat.state == "spared" and cat.actor.visible and not cat.is_busy() and not _choice_visible(), "leaving and reentering retains the spared cat without repeating the moral choice")
	await _destroy_main()
	GameCurrency.clear_profile_state()
	GameCurrency.load_currency()
	check(GameCurrency.get_basement_cat_choice() == "spared" and GameCurrency.get_coin_cents() == before, "the spared outcome and unchanged balance survive profile reload")
	await _spawn_main()
	await _enter_basement()
	await _press_key(KEY_D)
	await _settle(0.5)
	check(cat.state == "spared" and cat.actor.visible and cat.actor.texture.resource_path == SPARED_TEXTURE and cat.actor.hframes == 2 and not cat.is_busy() and not _choice_visible(), "a fresh scene restores the animated Cat Spare at the encounter location")
	var restored_frame := cat.actor.frame
	check(await _wait_until(func(): return cat.actor.frame != restored_frame, 1600), "the restored Cat Spare animation keeps playing after profile reload")
	await _destroy_main()


func _room_entrance(index: int) -> ProgressionArea:
	for area in main.progression_areas:
		if area.room_index == index:
			return area
	return null


func _any_crate_pickable() -> bool:
	for crate in (main.get_node("BasementRoom") as BasementDiscovery).get_crates():
		if crate._pick_area.input_ray_pickable:
			return true
	return false


func _choice_visible() -> bool:
	var angel := _angel_button()
	return cat.presentation.visible and angel != null and angel.is_visible_in_tree()


func _angel_button() -> BaseButton:
	return cat.presentation._angel


func _devil_button() -> BaseButton:
	return cat.presentation._satan


func _on_shot() -> void:
	shots += 1
	shot_flash_seen = shot_flash_seen or cat.presentation._muzzle_flash.visible
	shot_audio_started = shot_audio_started or cat.presentation._shot_audio.playing


func _visible_text(node: Node) -> String:
	var result := ""
	if node is Label and node.is_visible_in_tree():
		result = node.text + " "
	elif node is RichTextLabel and node.is_visible_in_tree():
		result = node.get_parsed_text() + " "
	for child in node.get_children():
		result += _visible_text(child)
	return result


func _face_door(door: HospitalDoor) -> void:
	_move_pointer(Vector2(-50, -50))
	await _settle(0.45)
	for _step in range(4):
		var target := door.doorway_area.global_position
		if not main.main_camera.is_position_behind(target) and viewport.get_visible_rect().grow(-20).has_point(main.main_camera.unproject_position(target)):
			return
		await _press_key(KEY_D)
		await _settle(0.4)
	check(false, "the requested doorway can be reached with normal cardinal turns")


func _fly(door: HospitalDoor, room_index: int) -> void:
	await _click_at(main.main_camera.unproject_position(door.doorway_area.global_position))
	check(main._room_transition_active and not cat.is_busy(), "a real doorway click starts travel while the cat remains inactive")
	check(await _wait_until(func(): return not main._room_transition_active), "physical room travel finishes")
	await _settle()
	check(main._active_room == room_index, "door travel arrives in room %d" % room_index)


func _press_key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame
		await get_tree().process_frame


func _move_pointer(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	viewport.push_input(event, true)


func _click_at(point: Vector2) -> void:
	_move_pointer(point)
	await _settle(0.04)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		viewport.push_input(event, true)
		await get_tree().physics_frame
		await get_tree().process_frame


func _capture(stage: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(viewport.get_texture().get_image().save_png("res://basement-cat-%s.png" % stage) == OK, "rendered evidence: " + stage)


func _finish() -> void:
	if get_tree().paused:
		get_tree().paused = false
	if is_instance_valid(main):
		main.queue_free()
	print("BASEMENT_CAT_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
