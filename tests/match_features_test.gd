extends Node

var failures := 0
@onready var root: Window = get_tree().root

func _ready() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene := load("res://scenes/main/Main.tscn") as PackedScene
	var main := scene.instantiate()
	root.add_child(main)
	await get_tree().process_frame
	var table := main.get_node("ScenePivot/GameTable") as GameTable
	GameCurrency.reset_progression()
	_check_fractional_balance_labels()
	var first_card: Dictionary = CardDatabase.get_all_cards()[0].duplicate(true)
	first_card["instance_id"] = "near"
	var second_card := first_card.duplicate(true)
	second_card["instance_id"] = "far"
	NetworkManager.current_lobby_id = 99
	NetworkManager._match_in_progress = true
	NetworkManager._connected_peer_ids.assign([1, 2])
	NetworkManager._participants = {
		1: {"role": "player", "name": "Host"},
		2: {"role": "player", "name": "Gast"},
		3: {"role": "spectator", "name": "Zuschauer"},
	}
	table._online_mode = true
	table._online_is_host = false
	table._online_is_spectator = true
	table._online_turn_sequence = 1
	var snapshot := {
		"current_turn": "player", "turn_sequence": 1,
		"player_slots": [{"card_data": first_card}, null, null, null, null],
		"enemy_slots": [{"card_data": second_card}, null, null, null, null],
		"player_deck_count": 2, "enemy_deck_count": 3,
		"game_over": false, "action_in_progress": false,
	}
	table._apply_online_state_now(snapshot)
	check(table._player_deck.size() == 2 and table._enemy_deck.size() == 3, "spectator deck counts preserve host sides")
	check(str(table._player_slots[0].card_data.get("instance_id")) == "near", "spectator sees host cards on host side")
	check(str(table._enemy_slots[0].card_data.get("instance_id")) == "far", "spectator sees guest cards on guest side")
	check(table._canonical_side_to_local("player") == "player", "spectator attack coordinates preserve host sides")
	check(table._match_status_message.contains("Host"), "spectator retains correct current fighter state")
	check(not table._is_online_opponent(3), "spectator cannot authorize fighter commands or ACKs")
	table._move_camera_to_match_view()
	await get_tree().create_timer(0.85).timeout
	var camera_transform := table.table_camera.global_transform
	check(camera_transform.basis.z.dot(Vector3.UP) > 0.999, "spectator camera looks vertically down")
	for marker: Marker3D in [table._player_slot_markers[0], table._enemy_slot_markers[4], table.player_deck_marker, table.enemy_deck_marker]:
		check(root.get_visible_rect().has_point(table.table_camera.unproject_position(marker.global_position)), "overhead view includes " + str(marker.get_path()))
	check(table._spectator_leave_button.visible, "spectator has a leave control during combat")
	check(table.get_node_or_null("StatusLabel") == null, "3D status label has been removed")
	check(table.get_node_or_null("OnlineCanvas/MatchStatusPanel") == null, "2D match status panel has been removed")
	check(table.get_node_or_null("OnlineCanvas/LevelProgress") == null, "flat XP panel has been removed")
	var progress := main.get_node("CameraPivot/CameraTilt/Camera3D/LevelProgress") as Node3D
	check(progress.get_parent() == table.table_camera, "3D level visor follows active shared camera")
	progress.set_process(false)
	progress._notification(NOTIFICATION_WM_WINDOW_FOCUS_IN)
	progress._notification(NOTIFICATION_WM_MOUSE_ENTER)
	progress.set_expanded(false)
	await get_tree().create_timer(0.6).timeout
	check(progress.visible and not progress.is_expanded() and progress.get_node("LeftHinge").is_visible_in_tree(), "folded 3D progress keeps its hinge visible")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://spectator-view.png")
	progress.set_pointer_position(Vector2(640, 2))
	await get_tree().create_timer(0.08).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://level-visor-opening.png")
	await get_tree().create_timer(0.5).timeout
	check(progress.visible and progress.is_expanded(), "top-edge pointer unfolds 3D progress")
	await _check_coin_clicker(progress, "spectator view")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://level-visor-open.png")
	progress.set_pointer_position(Vector2(640, 650))
	await get_tree().create_timer(0.6).timeout
	check(progress.visible and not progress.is_expanded(), "leaving the top region folds progress while preserving the hinge")
	progress.set_process(true)
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	table._on_card_clicked(table.table_camera, click, Vector3.ZERO, Vector3.UP, 0, "player", 0)
	table._select_player_card(0)
	check(table._selected_player_card == null, "spectator card clicks cannot select or attack")
	click.button_index = MOUSE_BUTTON_RIGHT
	table._on_card_clicked(table.table_camera, click, Vector3.ZERO, Vector3.UP, 0, "player", 0)
	check(table._inspected_card == null, "spectator keeps overhead view on right click")
	table._apply_online_result("player")
	check(GameCurrency.level == 1 and GameCurrency.xp == 0 and GameCurrency.coins == 20, "spectator gets no result XP or money")
	table._game_over = true
	table._table_state = GameTable.TableState.GAME_OVER
	var spectator_result := table._match_status_message
	table._on_online_session_closed("Online-Match beendet.")
	check(table._match_status_message == spectator_result, "completed spectator result survives host exit")
	table._online_is_spectator = false
	table._apply_online_state_now(snapshot)
	check(table._player_deck.size() == 3 and table._enemy_deck.size() == 2, "fighter client still receives mirrored deck counts")
	check(str(table._player_slots[0].card_data.get("instance_id")) == "far", "fighter client still receives its own near cards")
	await get_tree().create_timer(0.5).timeout
	table._match_reward_granted = false
	table._apply_online_result("enemy")
	table._apply_online_result("enemy")
	check(GameCurrency.level == 2 and GameCurrency.xp == 0 and GameCurrency.coins == 55, "repeated winning snapshots grant match coins, XP and level bonus exactly once")
	var expected_reward := Localization.format_text("%s · +%d XP · +%d Soul Coins", [Localization.localized_arg("Sieg!"), 100, 10]) + Localization.format_text("\nLevel %d! +%d Soul Coins", [2, 25])
	check(table._match_status_message == expected_reward, "result retains match coins, XP and level bonus without a status label")
	table._online_is_spectator = true
	table._leave_spectator_match()
	check(not table._online_mode and table._table_state == GameTable.TableState.MENU, "spectator exits independently to table menu")
	_check_match_rewards(table)
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var menu := (load("res://scenes/main/MainMenu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await get_tree().process_frame
	check(menu.get_node_or_null("ProfileCanvas") == null, "main menu has no remaining flat profile overlay")
	var menu_progress := menu.get_node("Camera3D/LevelProgress") as Node3D
	menu_progress.set_process(false)
	menu_progress._notification(NOTIFICATION_WM_WINDOW_FOCUS_IN)
	menu_progress._notification(NOTIFICATION_WM_MOUSE_ENTER)
	menu_progress.set_pointer_position(Vector2(640, 2))
	await get_tree().create_timer(0.7).timeout
	check(menu_progress.visible and menu_progress.is_expanded(), "same 3D visor opens in the main menu")
	await _check_coin_clicker(menu_progress, "main menu")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://level-visor-main-menu.png")
	menu.settings_menu.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	check(menu_progress.visible and not menu_progress.is_expanded(), "settings fold the visor and preserve its hinge without interrupting menu input")
	menu.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("MATCH_FEATURE_TESTS: " + ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)


func _check_match_rewards(table: GameTable) -> void:
	# Both fighter perspectives receive the same result amounts, including
	# when the final snapshot is repeated by the coordinated exit protocol.
	for is_host: bool in [true, false]:
		for outcome: Dictionary in [
			{"name": "win", "coins": 10, "xp": 100},
			{"name": "draw", "coins": 5, "xp": 50},
			{"name": "loss", "coins": 2, "xp": 25},
		]:
			GameCurrency.reset_progression(false)
			GameCurrency.level = 2
			table._online_mode = true
			table._online_is_spectator = false
			table._online_is_host = is_host
			table._match_reward_granted = false
			var winner := "draw"
			if outcome["name"] == "win":
				winner = "player" if is_host else "enemy"
			elif outcome["name"] == "loss":
				winner = "enemy" if is_host else "player"
			table._apply_online_result(winner)
			table._apply_online_result(winner)
			var context := "host=%s, %s" % [is_host, outcome["name"]]
			check(GameCurrency.coins == 20 + int(outcome["coins"]) and GameCurrency.xp == outcome["xp"] and GameCurrency.level == 2, context + ": result pays coins and XP exactly once without a level-up")
			table._show_main_menu()
			table._apply_online_result(winner)
			check(GameCurrency.coins == 20 + int(outcome["coins"]) and GameCurrency.xp == outcome["xp"], context + ": menu cleanup during exit cannot enable a second payout")
	table._online_mode = false
	table._online_is_host = false
	for outcome: Dictionary in [
		{"name": "win", "coins": 10, "xp": 100},
		{"name": "draw", "coins": 5, "xp": 50},
		{"name": "loss", "coins": 2, "xp": 25},
	]:
		GameCurrency.reset_progression(false)
		GameCurrency.level = 2
		table._clear_match()
		table._match_reward_granted = false
		table._table_state = GameTable.TableState.PLAYING
		if outcome["name"] == "win":
			table._player_deck.append({})
		elif outcome["name"] == "loss":
			table._enemy_deck.append({})
		check(table._check_game_over(), str(outcome["name"]) + ": offline board determines the completed result")
		table._check_game_over()
		table._grant_match_rewards()
		check(GameCurrency.coins == 20 + int(outcome["coins"]) and GameCurrency.xp == outcome["xp"] and GameCurrency.level == 2, str(outcome["name"]) + ": offline result pays coins and XP once despite repeated completion calls")
	GameCurrency.reset_progression()
	table._show_main_menu()


func _check_fractional_balance_labels() -> void:
	var shop := (load("res://scenes/PackShopUI.tscn") as PackedScene).instantiate() as PackShopUI
	var upgrade := (load("res://scenes/UpgradeUI.tscn") as PackedScene).instantiate() as UpgradeUI
	shop.hide()
	upgrade.hide()
	root.add_child(shop)
	root.add_child(upgrade)
	GameCurrency.add_coins(0.14)
	check(shop.balance_label.text == Localization.decimal(20.14), "pack shop updates fractional balance through the currency signal")
	check(upgrade.balance_label.text == Localization.format_text("%s SOUL COINS", [Localization.decimal(20.14)]), "upgrade screen updates fractional balance through the currency signal")
	GameCurrency.spend_coins(0.14)
	check(shop.balance_label.text == Localization.decimal(20.0) and upgrade.balance_label.text == Localization.format_text("%s SOUL COINS", [Localization.decimal(20.0)]), "balance labels preserve two decimal places at whole amounts")
	shop.queue_free()
	upgrade.queue_free()


func _check_coin_clicker(progress: Node3D, context: String) -> void:
	var button := progress.get_node("Hinge/CoinButton") as MeshInstance3D
	var camera := progress.get_parent() as Camera3D
	var pointer := camera.unproject_position(button.to_global(button.get_aabb().get_center()))
	var original_coins := GameCurrency.get_coins()
	var original_cents := GameCurrency.get_coin_cents()
	var original_level := GameCurrency.get_level()
	var original_xp := GameCurrency.get_xp()
	var original_collection: Dictionary = CollectionManager.collection.duplicate(true)
	var changed_card_ids: Array[String] = []
	CollectionManager.collection = {"cards": {}, "instances": []}
	CollectionManager.collection_changed.emit(changed_card_ids)
	check(progress.coins_per_click == 0 and Localization.text(progress.coin_button_label.text) == Localization.text("Gesperrt\nClicker-Karte nötig"), context + ": missing Clicker card locks the button")
	_push_mouse_button(pointer, MOUSE_BUTTON_LEFT, true)
	_push_mouse_button(pointer, MOUSE_BUTTON_LEFT, false)
	check(GameCurrency.get_coins() == original_coins, context + ": locked clicker grants no coins")
	CollectionManager.add_card("clicker_upgrade")
	_push_mouse_button(pointer, MOUSE_BUTTON_LEFT, true)
	_push_mouse_button(pointer, MOUSE_BUTTON_LEFT, false)
	check(progress.coins_per_click == 0 and GameCurrency.get_coins() == original_coins, context + ": upgrade without unlock card cannot pay")
	CollectionManager.collection = {"cards": {}, "instances": []}
	CollectionManager.add_card("clicker")
	check(is_equal_approx(progress.coins_per_click, 0.02) and progress.coin_button_label.text == Localization.format_text("+%s Münzen", [Localization.decimal(0.02)]), context + ": acquiring Clicker unlocks the open visor at 0.02 Soul Coins")
	check(root.get_visible_rect().has_point(pointer), context + ": coin button projects inside the screen")
	check(_push_mouse_button(pointer, MOUSE_BUTTON_LEFT, true), context + ": coin press consumes real viewport input before table picking")
	check(GameCurrency.get_coin_cents() == original_cents + 2, context + ": one left press grants exactly two cents")
	check(_push_mouse_button(pointer, MOUSE_BUTTON_LEFT, false), context + ": coin release is also consumed")
	check(GameCurrency.get_coin_cents() == original_cents + 2, context + ": releasing the button grants no extra coins")
	check(_push_mouse_button(pointer, MOUSE_BUTTON_RIGHT, true), context + ": right click cannot inspect cards behind the visor")
	_push_mouse_button(pointer, MOUSE_BUTTON_RIGHT, false)
	check(GameCurrency.get_coin_cents() == original_cents + 2, context + ": right clicks grant no coins")
	for click_index in range(4):
		_push_mouse_button(pointer, MOUSE_BUTTON_LEFT, true)
		_push_mouse_button(pointer, MOUSE_BUTTON_LEFT, false)
	check(GameCurrency.get_coin_cents() == original_cents + 10, context + ": five rapid clicks grant exactly ten cents")
	check(GameCurrency.get_level() == original_level and GameCurrency.get_xp() == original_xp, context + ": clicking preserves level and XP")
	var saved := ConfigFile.new()
	check(saved.load(GameCurrency.save_path) == OK and int(saved.get_value("currency", "coin_cents", -1)) == original_cents + 10, context + ": clicker cents persist exactly in the isolated profile")
	var label := progress.get_node("Hinge/CoinLabel") as Label3D
	check(label.text == Localization.format_text("%s Soul Coins", [GameCurrency.format_coins()]), context + ": physical balance label immediately includes both decimal places")
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://level-visor-clicker-unlocked-%s.png" % context.replace(" ", "-"))
	var frame := progress.get_node("Hinge/Frame") as MeshInstance3D
	var frame_pointer := camera.unproject_position(frame.to_global(frame.get_aabb().get_center()))
	check(_push_mouse_button(frame_pointer, MOUSE_BUTTON_LEFT, true), context + ": the rest of the panel blocks clicks into the table")
	_push_mouse_button(frame_pointer, MOUSE_BUTTON_LEFT, false)
	check(GameCurrency.get_coin_cents() == original_cents + 10, context + ": clicking outside the coin button grants no coins")
	get_tree().paused = true
	_push_mouse_button(pointer, MOUSE_BUTTON_LEFT, true)
	_push_mouse_button(pointer, MOUSE_BUTTON_LEFT, false)
	check(GameCurrency.get_coin_cents() == original_cents + 10, context + ": paused visor cannot grant coins")
	get_tree().paused = false
	progress.set_enabled(false)
	_push_mouse_button(pointer, MOUSE_BUTTON_LEFT, true)
	_push_mouse_button(pointer, MOUSE_BUTTON_LEFT, false)
	check(GameCurrency.get_coin_cents() == original_cents + 10, context + ": folded disabled visor cannot grant coins")
	progress.set_enabled(true)
	progress.set_expanded(true)
	await get_tree().create_timer(0.6).timeout
	CollectionManager.add_card("clicker_upgrade")
	CollectionManager.add_card("clicker_upgrade")
	check(is_equal_approx(progress.coins_per_click, 0.04) and progress.coin_button_label.text == Localization.format_text("+%s Münzen", [Localization.decimal(0.04)]), context + ": two owned upgrades immediately raise the click to 0.04 Soul Coins")
	_push_mouse_button(pointer, MOUSE_BUTTON_LEFT, true)
	_push_mouse_button(pointer, MOUSE_BUTTON_LEFT, false)
	check(GameCurrency.get_coin_cents() == original_cents + 14, context + ": upgraded click credits exactly four more cents")
	CollectionManager.add_card("clicker")
	check(is_equal_approx(progress.coins_per_click, 0.04), context + ": another unlock grant cannot increase the click payout")
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://level-visor-clicker-upgraded-%s.png" % context.replace(" ", "-"))
	CollectionManager.collection = original_collection
	CollectionManager.save_collection()
	CollectionManager.collection_changed.emit(changed_card_ids)
	check(is_equal_approx(progress.coins_per_click, (2 + CollectionManager.get_clicker_upgrade_count()) * 0.01 if CollectionManager.is_clicker_unlocked() else 0.0), context + ": changing the inventory restores the correct lock and payout")
	# Keep the existing match reward assertions independent of clicker earnings.
	if GameCurrency.get_coins() > original_coins:
		GameCurrency.spend_coins(GameCurrency.get_coins() - original_coins)


func _push_mouse_button(pointer: Vector2, button_index: MouseButton, pressed: bool) -> bool:
	var event := InputEventMouseButton.new()
	event.position = pointer
	event.global_position = pointer
	event.button_index = button_index
	event.pressed = pressed
	root.push_input(event, true)
	return root.is_input_handled()
