extends Node3D

const RULES := preload("res://scripts/match/OfflineMatchRules.gd")
var checks := 0
var failures := 0
var table: GameTable
var main: MainScene
var viewport: SubViewport


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func settle() -> void:
	await get_tree().create_timer(0.36).timeout
	await get_tree().process_frame


func capture(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://" + name + ".png")


func pointer(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	viewport.push_input(motion, true)
	await get_tree().process_frame


func click_board(control: Control) -> void:
	var position: Vector2 = table._offline_board.board_to_screen(control.get_global_rect().get_center())
	await pointer(position)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = position
		click.global_position = position
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		viewport.push_input(click, true)
		await get_tree().process_frame


func key(code: Key, unicode: int = 0, ctrl: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.unicode = unicode
	event.ctrl_pressed = ctrl
	event.pressed = true
	viewport.push_input(event, true)
	await get_tree().process_frame
	event.pressed = false
	viewport.push_input(event, true)


func type_stat(spin: SpinBox, value: String) -> void:
	await click_board(spin.get_line_edit())
	await key(KEY_A, 0, true)
	for character in value:
		await key(character.unicode_at(0), character.unicode_at(0))
	await key(KEY_ENTER)
	await settle()


func _run() -> void:
	if not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Use the isolated match feature runner.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	SaveSlots.select_slot(1)
	SaveSlots.reset_slot(1)
	SaveSlots.reset_slot(2)
	CollectionManager.clear_profile_state()
	CardUpgradeManager.clear_profile_state()
	DeckManager.clear_profile_state()
	GameCurrency.reset_progression()
	_test_story_rules()
	_test_wallet()
	for index in range(6):
		CollectionManager.add_card("corpse")
		DeckManager.add_card("corpse")
	CardUpgradeManager.upgrades["corpse"] = {"attack_bonus": 6, "health_bonus": 600, "effects": [{"type": "poison", "value": 3}]}
	CardUpgradeManager.save_upgrades()
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.wakeup_blur_duration = 0.01
	main.mouse_tilt_strength = 0.0
	viewport.add_child(main)
	table = main.get_node("ScenePivot/GameTable") as GameTable
	table.enemy_turn_delay = 60.0
	table.draw_animation_duration = 0.01
	await settle()
	await pointer(Vector2(640, 360))
	await _test_camera_transitions()
	await _test_story_menu_and_match()
	await _test_training()
	_test_online_rewards()
	table._online_mode = false
	table._show_main_menu()
	main.queue_free()
	await settle()
	check(not GameCurrency.is_training_session(), "scene exit releases training reward suspension")
	print("OFFLINE_MODES_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _test_story_rules() -> void:
	var previous := 0
	var catalog := CardDatabase.get_all_cards().duplicate(true)
	for level in range(1, 101):
		var deck := RULES.story_deck(level, 20)
		check(deck.size() == 20, "story level %d has a full enemy deck" % level)
		var value := 0
		for card in deck:
			check(CardData.is_combat_card(card) and CardDatabase.has_card(str(card["id"])), "story uses real combat templates")
			value += int(card["attack"]) + int(card["defense"])
		check(value > previous, "story deck strength strictly increases at %d" % level)
		previous = value
	check(CardDatabase.get_all_cards() == catalog, "story scaling never changes the catalog")
	check(RULES.story_deck(0, 20).is_empty() and RULES.story_deck(101, 20).is_empty(), "out-of-range levels cannot build decks")


func _test_camera_transitions() -> void:
	table._show_main_menu()
	await get_tree().create_timer(0.8).timeout
	var base_pose := table.table_camera.global_transform
	var base_fov := table.table_camera.fov
	for mode in ["story", "training"]:
		for stage in ["entering", "focused", "returning"]:
			for start_match in [false, true]:
				await pointer(Vector2(640, 360))
				if mode == "story":
					table._show_story_menu()
				else:
					table._show_training_menu()
				await get_tree().create_timer(0.05 if stage == "entering" else 0.4).timeout
				if stage == "returning":
					await pointer(Vector2(5, 360))
					await get_tree().create_timer(0.12).timeout
					check(main.screen_camera_focus.is_focused(), "board focus stays stable with the pointer outside")
					main.screen_camera_focus.set_context(0, false, 0)
				if start_match:
					if mode == "story":
						table._start_story_level(1)
					else:
						var enemies: Array[Dictionary] = []
						for index in range(5):
							enemies.append(RULES.training_card(100, 500))
						table._start_training_match([0, 1, 2, 3, 4], enemies)
				else:
					table._offline_menu._go_back()
				await get_tree().create_timer(0.8).timeout
				var expected_pose := table._get_match_camera_transform() if start_match else base_pose
				var context := "%s / %s / %s" % [mode, stage, "start" if start_match else "back"]
				check(table.table_camera.global_transform.is_equal_approx(expected_pose), context + " restores exact destination camera pose")
				check(is_equal_approx(table.table_camera.fov, base_fov), context + " restores the standard field of view")
				check(not main.screen_camera_focus.is_focused() and main.screen_camera_focus._camera_tween == null, context + " leaves no competing board-focus tween")
				table._show_main_menu()
				await get_tree().create_timer(0.8).timeout


func _test_wallet() -> void:
	check(GameCurrency.is_story_level_unlocked(1) and not GameCurrency.is_story_level_unlocked(2), "new profiles unlock only level one")
	check(GameCurrency.award_story_win(2).is_empty(), "locked level cannot award progress")
	var reward := GameCurrency.award_story_win(1)
	check(reward.get("xp_awarded") == 50 and reward.get("coins_reward") == 5.0, "level one pays its displayed rewards")
	GameCurrency.reload_profile()
	check(GameCurrency.story_completed_level == 1 and GameCurrency.is_story_level_unlocked(2), "completion and unlock survive reload")
	check(SaveSlots.select_slot(2) == OK and GameCurrency.story_completed_level == 0, "story progress is isolated per save slot")
	check(SaveSlots.select_slot(1) == OK and GameCurrency.story_completed_level == 1, "returning to a slot restores its story")
	var saved_path := GameCurrency.save_path
	var wallet := [GameCurrency.coins, GameCurrency.xp, GameCurrency.level]
	GameCurrency.save_path = "res://test-user/missing-directory/currency.cfg"
	check(GameCurrency.award_story_win(2).is_empty(), "failed story save reports failure")
	check(GameCurrency.story_completed_level == 1 and wallet == [GameCurrency.coins, GameCurrency.xp, GameCurrency.level], "failed save rolls back progress and all rewards")
	GameCurrency.save_path = saved_path
	check(SaveSlots.reset_slot(1) == OK and GameCurrency.story_completed_level == 0, "profile reset clears story")


func _test_story_menu_and_match() -> void:
	table.mode_buttons.get_node("KIButton").pressed.emit()
	await settle()
	check(table._offline_menu.visible and table.is_match_active(), "story button opens modal map and locks room navigation")
	check(table._offline_menu.get_viewport() == table._offline_board.viewport and table._offline_board.visible, "story is rendered only onto a real tabletop board")
	check(main.screen_camera_focus.is_focused() and main.screen_camera_focus._focused_screen == table._offline_board.focus_area, "board uses the upgrade machines' shared camera focus")
	var map: Control = table._offline_menu.level_map
	check(map.buttons.size() == 100 and not map.buttons[0].disabled and map.buttons[1].disabled, "100 levels use saved locks")
	for offset in [0, 43, 1500, 99999]:
		table._offline_menu._story_scroll.scroll_vertical = offset
		await settle()
		var count := 0
		var visible_rect: Rect2 = table._offline_menu._story_scroll.get_global_rect()
		for button: Button in map.buttons:
			if button.get_global_rect().intersects(visible_rect):
				count += 1
		check(count <= 10 and count > 0, "scroll shows no more than ten levels (count=%d, offset=%d, viewport=%s, map=%s, row=%f)" % [count, offset, visible_rect, map.size, map.row_height])
	table._offline_menu._story_scroll.scroll_vertical = 0
	await settle()
	var scroll_point: Vector2 = table._offline_board.board_to_screen(table._offline_menu._story_scroll.get_global_rect().get_center())
	await pointer(scroll_point)
	var wheel := InputEventMouseButton.new()
	wheel.position = scroll_point
	wheel.global_position = scroll_point
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	viewport.push_input(wheel, true)
	wheel.pressed = false
	viewport.push_input(wheel, true)
	await settle()
	check(table._offline_menu._story_scroll.scroll_vertical > 0, "mouse wheel scrolls the real board surface")
	table._offline_menu._story_scroll.scroll_vertical = 0
	await capture("story-levels-locked")
	table._start_story_level(2)
	check(table._table_state == GameTable.TableState.STORY_SELECT, "direct start cannot bypass locked level")
	await click_board(table._offline_menu._next)
	check(table._local_mode == "story" and table._table_state == GameTable.TableState.PLAYING, "level starts the existing local combat")
	check(table._enemy_deck.size() == table.deck_size - 5, "story retains the normal reserve")
	check(table._enemy_slots[0].attack_value == 1 and table._enemy_slots[0].max_hp == 3, "level one starts with low stats")
	table._clear_match()
	table._player_deck.append(CardDatabase.get_card("corpse"))
	check(table._check_game_over(), "normal game-over determines story victory")
	var coins := GameCurrency.coins
	var xp := GameCurrency.xp
	table._grant_match_rewards()
	check(GameCurrency.story_completed_level == 1 and GameCurrency.coins == coins and GameCurrency.xp == xp, "victory unlocks once and duplicate result grants nothing")
	table._show_main_menu()
	table._show_story_menu()
	await settle()
	check(not table._offline_menu.level_map.buttons[1].disabled and table._offline_menu.level_map.buttons[2].disabled, "victory refreshes the map locks")
	await capture("story-levels-progress")
	table._start_story_level(2)
	table._clear_match()
	table._enemy_deck.append(CardDatabase.get_card("corpse"))
	table._check_game_over()
	check(GameCurrency.story_completed_level == 1 and GameCurrency.coins == coins and GameCurrency.xp == xp, "story loss grants no unlock or win rewards")
	table._show_main_menu()


func _profile_bytes() -> Array:
	var result: Array = []
	for file in SaveSlots.PROFILE_FILES:
		result.append(FileAccess.get_file_as_bytes(SaveSlots.get_save_path(file)))
	return result


func _test_training() -> void:
	var before := _profile_bytes()
	var wallet := [GameCurrency.coins, GameCurrency.xp, GameCurrency.level, GameCurrency.story_completed_level]
	table.mode_buttons.get_node("TrainingButton").pressed.emit()
	await settle()
	var menu: Control = table._offline_menu
	check(menu._step == 0 and not menu._next.disabled, "training first offers selection of five own deck copies")
	menu._own_selectors[1].item_selected.emit(0)
	check(menu._next.disabled, "same physical copy cannot fill two training slots")
	menu._own_selectors[1].item_selected.emit(1)
	await click_board(menu._own_selectors[4])
	for selection_step in range(6):
		await key(KEY_DOWN)
	await key(KEY_ENTER)
	await settle()
	check(menu._indices[4] == 5, "deck picker stays on the board and accepts keyboard selection")
	await capture("training-player-deck")
	await click_board(menu._next)
	await settle()
	check(menu._step == 1, "second step configures enemy cards")
	menu._enemies[4] = {"id": "piss"}
	menu._build_training()
	await settle()
	var spins := menu.find_children("*", "SpinBox", true, false)
	await type_stat(spins[0], "137")
	check(menu._enemies[0]["attack"] == 137, "typing on the physical board edits attack through projected input")
	await type_stat(spins[0], "100")
	await type_stat(spins[1], "500")
	await capture("training-enemy-deck")
	await click_board(menu._next)
	await settle()
	check(table._local_mode == "training" and table._table_state == GameTable.TableState.PLAYING, "configured training enters the shared fight")
	check(table._player_slots.all(func(card): return card != null) and table._enemy_slots.all(func(card): return card != null) and table._player_deck.is_empty() and table._enemy_deck.is_empty(), "exactly five cards per player, without reserves")
	check(table._enemy_slots[0].attack_value == 100 and table._enemy_slots[0].current_hp == 500, "custom 100 attack / 500 defense reaches real Card3D")
	check(CardData.has_effect(table._enemy_slots[4].card_data, "lava"), "real opponent cards retain native effects")
	var attacker := table._player_slots[0]
	check(attacker.attack_value == int(CardDatabase.get_card("corpse")["attack"]) + 6 and CardData.has_effect(attacker.card_data, "poison"), "owned stats and upgraded effects survive training selection")
	SettingsManager.set_damage_numbers_enabled(false)
	attacker.attack_out_duration = 0.01
	attacker.attack_hit_duration = 0.01
	attacker.attack_return_duration = 0.01
	var target := table._enemy_slots[0]
	var expected := attacker.attack_value
	await table._resolve_duel(attacker, target, "player")
	check(target.current_hp <= 500 - expected and not table._training_hits.is_empty(), "real combat damage reaches dummy health and persistent damage log (HP=%d, expected hit=%d, log=%s)" % [target.current_hp, expected, table._training_hits])
	check(table._training_damage_log.text.contains(str(expected)), "damage log prints actual damage")
	table._spawn_damage_number(target, 0)
	check(not table._damage_numbers.is_empty() and table._training_hits.back().contains("0"), "training shows blocked hits even with ordinary numbers disabled")
	await capture("training-damage")
	GameCurrency._auto_click_rate = 100
	GameCurrency.advance_auto_clicker(100)
	GameCurrency.award_manual_click()
	GameCurrency.add_coins(100)
	GameCurrency.add_xp(100)
	GameCurrency.award_story_win(2)
	for outcome in [GameTable.MatchOutcome.WIN, GameTable.MatchOutcome.LOSS, GameTable.MatchOutcome.DRAW]:
		table._match_reward_granted = false
		table._last_match_outcome = outcome
		table._grant_match_rewards()
		table._grant_match_rewards()
	check(wallet == [GameCurrency.coins, GameCurrency.xp, GameCurrency.level, GameCurrency.story_completed_level], "all training outcomes and passive/manual rewards leave progression unchanged")
	check(before == _profile_bytes(), "training leaves all saved profile files byte-for-byte unchanged")
	table._restart_training()
	check(table._enemy_slots[0].current_hp == 500 and table._training_hits.is_empty(), "restart restores selected cards and clears hit history")
	table._show_main_menu()
	check(not GameCurrency.is_training_session() and not table._training_hud.visible, "leaving training releases income and clears HUD")
	SettingsManager.set_damage_numbers_enabled(true)


func _test_online_rewards() -> void:
	for host in [true, false]:
		for winner in ["player", "enemy", "draw"]:
			table._online_mode = true
			table._online_is_host = host
			table._online_is_spectator = false
			table._local_mode = "training" # stale local selection must never affect online.
			table._match_reward_granted = false
			GameCurrency.level = 100
			GameCurrency.xp = 0
			GameCurrency.coins = 0
			table._apply_online_result(winner)
			var result := "draw" if winner == "draw" else ("win" if (winner == "player") == host else "loss")
			check(GameCurrency.xp == GameCurrency.get_match_xp(result) and GameCurrency.coins == GameCurrency.get_match_coins(result), "host/client online rewards keep their existing amounts")
			table._apply_online_result(winner)
			check(GameCurrency.xp == GameCurrency.get_match_xp(result), "duplicate online results still grant only once")
	check(GameCurrency.story_completed_level == 1, "online results never advance story")
