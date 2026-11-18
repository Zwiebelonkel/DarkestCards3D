extends "res://tests/basement_cat_test.gd"
## Actual doorway travel and shared LevelProgress views of one saved helper.

const CLICK_TEXTURE := "res://assets/characters/cat/catClick.png"


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
	check(CollectionManager.use_access_key("basement_key"), "helper fixture explicitly activates basement access")
	CollectionManager.add_card("clicker")
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
	var initial_coins := GameCurrency.get_coin_cents()
	GameCurrency.advance_cat_clicker(1.0)
	check(not GameCurrency.is_cat_clicker_active() and not _cat_sprite().visible and GameCurrency.get_coin_cents() == initial_coins, "an unlocked Clicker alone cannot summon or pay the unspared cat")
	await _enter_basement()
	await _start_encounter(false)
	if cat.state != "choice":
		_finish()
		return
	await _click_at(_angel_button().get_global_rect().get_center())
	check(await _wait_until(func(): return cat.state == "spared" and not cat.is_busy()), "the real angel choice completes before the cat can become a helper")
	check(cat.actor.visible and not GameCurrency.has_basement_cat_left() and not GameCurrency.is_cat_clicker_active() and not _cat_sprite().visible, "newly spared cat remains on the basement floor until the player leaves")
	await _leave_basement_and_check_arrival()
	await _check_shared_clicker()
	await _check_return_and_reload()
	await _check_locked_then_unlocked()
	await _check_existing_spared_profile()
	await _check_shot_cannot_help()
	_finish()


func _cat_sprite() -> Sprite3D:
	return main.level_progress.get_node("Hinge/CoinButton/CatClick") as Sprite3D


func _leave_basement_and_check_arrival() -> void:
	var door := main.get_node("BasementRoom/ReturnDoor") as HospitalDoor
	await _face_door(door)
	await _click_at(main.main_camera.unproject_position(door.doorway_area.global_position))
	check(main._room_transition_active and not GameCurrency.has_basement_cat_left() and cat.actor.visible, "starting the real exit trip keeps the spared cat on the floor until travel finishes")
	check(await _wait_until(func(): return not main._room_transition_active), "the basement return door finishes its normal camera journey")
	await _settle()
	check(main._active_room == 0 and GameCurrency.has_basement_cat_left() and GameCurrency.is_cat_clicker_active(), "completed basement departure persistently activates the spared helper")
	var sprite := _cat_sprite()
	check(not cat.actor.visible and sprite.visible and sprite.get_parent() == (main.level_progress as LevelProgress).coin_button, "the cat leaves the floor and sits on the existing LevelProgress click button")
	check(sprite.texture.resource_path == CLICK_TEXTURE and sprite.hframes == 3 and sprite.vframes == 1, "the helper uses all three 32 by 32 frames of the supplied Cat Click sheet")


func _check_shared_clicker() -> void:
	var progress := main.level_progress as LevelProgress
	var sprite := _cat_sprite()
	var before := GameCurrency.get_coin_cents()
	GameCurrency.advance_cat_clicker(1.0 / 3.0)
	check(sprite.frame == 1 and GameCurrency.get_coin_cents() == before, "the second animation frame is visible before any automatic reward")
	GameCurrency.advance_cat_clicker(1.0 / 3.0)
	check(sprite.frame == 2 and GameCurrency.get_coin_cents() == before + 2, "entering frame three visibly pays exactly one current manual click")
	await _settle(0.15)
	check(GameCurrency.get_coin_cents() == before + 2, "rendering the same third frame does not pay repeatedly")
	var duplicate := (load("res://scenes/ui/LevelProgress.tscn") as PackedScene).instantiate() as LevelProgress
	check(not duplicate._can_display(), "a visor outside the scene tree safely rejects display checks before initialization")
	main.main_camera.add_child(duplicate)
	duplicate.set_enabled(false)
	duplicate.hide()
	check((duplicate.get_node("Hinge/CoinButton/CatClick") as Sprite3D).frame == sprite.frame, "a newly created visor immediately mirrors the shared cat frame")
	GameCurrency.advance_cat_clicker(1.0)
	check(GameCurrency.get_coin_cents() == before + 4 and (duplicate.get_node("Hinge/CoinButton/CatClick") as Sprite3D).frame == sprite.frame, "two visor instances share one animation clock and cannot double the automatic payout")
	duplicate.set_enabled(true)
	main.main_camera.remove_child(duplicate)
	check(not duplicate._can_display(), "a detached visor safely rejects display checks during scene changes")
	GameCurrency.advance_cat_clicker(1.0)
	check(GameCurrency.get_coin_cents() == before + 6 and duplicate._coin_press_tween == null, "a cat click received after detaching cannot animate the removed visor or interrupt the shared payout")
	main.main_camera.add_child(duplicate)
	duplicate.show()
	check(duplicate._can_display(), "reattaching the visor restores its display eligibility")
	duplicate.queue_free()
	await _settle()
	progress.set_enabled(false)
	before = GameCurrency.get_coin_cents()
	GameCurrency.advance_cat_clicker(1.0)
	check(not progress.is_expanded() and GameCurrency.get_coin_cents() == before + 2, "the helper continues earning like Auto Clicker while its panel is disabled and folded")
	progress.set_enabled(true)
	await _settle()
	_move_pointer(Vector2(viewport.size.x * 0.5, 1))
	progress.set_expanded(true)
	await _settle(0.65)
	var button := progress.coin_button
	var pointer := main.main_camera.unproject_position(button.to_global(button.get_aabb().get_center()))
	before = GameCurrency.get_coin_cents()
	await _click_at(pointer)
	check(progress.is_expanded() and GameCurrency.get_coin_cents() == before + 2, "a real pointer click still reaches the coin button beneath the cat exactly once")
	check(progress.coin_label.text == Localization.format_text("%s Soul Coins", [GameCurrency.format_coins()]), "cat and manual earnings immediately update the visible coin balance")
	await _capture("clicker")
	GameCurrency.set_process(true)
	main.pause_menu.open()
	before = GameCurrency.get_coin_cents()
	var paused_frame := sprite.frame
	await _settle(1.1)
	check(get_tree().paused and GameCurrency.get_coin_cents() == before and sprite.frame == paused_frame, "ordinary Pause freezes both the shared cat animation and automatic rewards")
	main.pause_menu.close()
	check(await _wait_until(func(): return GameCurrency.get_coin_cents() == before + 2, 1600), "after unpausing the live game clock resumes automatic third-frame income")
	GameCurrency.set_process(false)
	check(sprite.frame == 2, "the real process-driven reward arrives together with the third visible frame")
	NetworkManager.current_lobby_id = 123456
	main.pause_menu.open()
	before = GameCurrency.get_coin_cents()
	GameCurrency.advance_cat_clicker(1.0)
	check(not get_tree().paused and GameCurrency.get_coin_cents() == before + 2, "the online pause overlay preserves Auto Clicker style income without pausing network play")
	NetworkManager.current_lobby_id = 0
	main.pause_menu.close()
	await _settle()
	_move_pointer(Vector2(-50, -50))


func _check_return_and_reload() -> void:
	await _enter_basement()
	await _press_key(KEY_D)
	await _settle(0.5)
	check(cat.state == "spared" and not cat.actor.visible and not cat.is_busy() and not _choice_visible() and _cat_sprite().visible, "returning to the basement never clones the helper back onto the floor")
	var before := GameCurrency.get_coin_cents()
	await _destroy_main()
	GameCurrency.clear_profile_state()
	GameCurrency.load_currency()
	await _spawn_main()
	check(GameCurrency.has_basement_cat_left() and GameCurrency.is_cat_clicker_active() and _cat_sprite().visible and not cat.actor.visible, "saving and reloading restores the same helper without another basement visit")
	check(GameCurrency.get_coin_cents() == before, "loading the helper has no offline or scene-instantiation payout")
	await _destroy_main()


func _check_locked_then_unlocked() -> void:
	CollectionManager.clear_profile_state()
	CollectionManager.add_card("basement_key")
	check(CollectionManager.use_access_key("basement_key"), "locked-Clicker fixture still explicitly activates basement access")
	_reset_currency()
	await _spawn_main()
	await _enter_basement()
	check(bool(GameCurrency.resolve_basement_cat_choice("spared").get("ok", false)), "the locked-Clicker profile records a valid mercy outcome")
	var door := main.get_node("BasementRoom/ReturnDoor") as HospitalDoor
	await _face_door(door)
	await _fly(door, 0)
	var before := GameCurrency.get_coin_cents()
	GameCurrency.advance_cat_clicker(4.0)
	check(GameCurrency.has_basement_cat_left() and not GameCurrency.is_cat_clicker_active() and not _cat_sprite().visible and cat.actor.visible and GameCurrency.get_coin_cents() == before, "leaving records mercy but a locked Clicker keeps the cat in the basement and grants no income")
	CollectionManager.add_card("clicker_upgrade")
	check(not GameCurrency.is_cat_clicker_active() and cat.actor.visible, "owning an upgrade alone cannot move the cat onto a locked click button")
	CollectionManager.add_card("clicker")
	check(GameCurrency.is_cat_clicker_active() and _cat_sprite().visible and not cat.actor.visible, "unlocking Clicker later immediately moves the previously spared cat without another visit")
	GameCurrency.advance_cat_clicker(2.0 / 3.0)
	check(GameCurrency.get_coin_cents() == before + 3, "the helper uses the current upgraded manual click value on its first third frame")
	await _destroy_main()


func _check_shot_cannot_help() -> void:
	_reset_currency()
	check(bool(GameCurrency.resolve_basement_cat_choice("shot").get("ok", false)), "the alternative shot profile is committed normally")
	var before := GameCurrency.get_coin_cents()
	await _spawn_main()
	GameCurrency.advance_cat_clicker(3.0)
	check(not GameCurrency.has_basement_cat_left() and not GameCurrency.is_cat_clicker_active() and not _cat_sprite().visible and not cat.actor.visible and GameCurrency.get_coin_cents() == before, "a shot cat never becomes a helper or pays even when Clicker is unlocked")
	await _destroy_main()


func _check_existing_spared_profile() -> void:
	_reset_currency()
	check(bool(GameCurrency.resolve_basement_cat_choice("spared").get("ok", false)) and not GameCurrency.has_basement_cat_left(), "an existing mercy save can predate the new departure flag")
	GameCurrency.clear_profile_state()
	GameCurrency.load_currency()
	var before := GameCurrency.get_coin_cents()
	await _spawn_main()
	check(GameCurrency.has_basement_cat_left() and GameCurrency.is_cat_clicker_active() and _cat_sprite().visible and not cat.actor.visible, "loading an older spared save outside the basement moves its cat to the unlocked Clicker")
	check(GameCurrency.get_coin_cents() == before, "migrating an existing spared cat awards no extra coins")
	await _destroy_main()


func _finish() -> void:
	if get_tree().paused:
		get_tree().paused = false
	GameCurrency.set_process(false)
	if is_instance_valid(main):
		main.queue_free()
	print("CAT_CLICKER_INTEGRATION_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
