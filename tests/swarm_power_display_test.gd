extends Node

var checks := 0
var failures := 0
var identity := 0
var output := "res://docs/validation/swarm-power-display"
var table: GameTable
var closeup: Camera3D


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + description)
	if not condition:
		failures += 1


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Use the isolated match fixture; player saves must remain untouched.")
		get_tree().quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	AudioServer.set_bus_mute(0, true)
	GameCurrency.set_process(false)
	Localization.set_locale("en")
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.greeting_enabled = false
	main.wakeup_blur_duration = 0.01
	get_tree().root.add_child(main)
	await get_tree().process_frame
	main.set_process(false)
	main.mouse_tilt_strength = 0.0
	table = main.get_node("ScenePivot/GameTable") as GameTable
	table._clear_match()
	table._table_state = GameTable.TableState.PLAYING
	table._current_turn = "player"
	table.menu_root.hide()
	table.matchmaking_screen.hide()
	table.match_hud.show_for_match(false)
	table.draw_animation_duration = 0.02
	table.replacement_draw_delay = 0.01
	table.blood_burst_scene = null
	table.blood_decal_scene = null
	closeup = Camera3D.new()
	main.add_child(closeup)
	closeup.projection = Camera3D.PROJECTION_ORTHOGONAL
	closeup.size = 1.55
	var first := _spawn("player", 1)
	await _settle()
	check(first.attack_label.text == "2" and first.defense_label.text == "6" and not first.swarm_multiplier_label.visible, "a single Ant keeps its standard 2/6 values without a multiplier")
	_focus(first)
	await _capture("01-single")
	var second := _spawn("player", 2)
	await _settle()
	check(_factor(first, 2) and _factor(second, 2), "drawing a second identical ally updates both cards to x2")
	check(first.attack_value == 2 and second.attack_value == 2 and first.max_hp == 6 and second.max_hp == 6, "the display does not multiply gameplay attack or health a second time")
	_focus(second)
	await _capture("02-pair")
	var chick := _spawn("player", 3, "chick")
	await _settle()
	check(_factor(first, 2) and not chick.swarm_multiplier_label.visible, "a different Swarm species neither joins the Ant swarm nor gains its bonus")
	var third := _spawn("enemy", 2)
	await _settle()
	check(_factor(first, 3) and _factor(second, 3) and _factor(third, 3), "identical opponents contribute to the same x3 factor, matching combat rules")
	check(CombatResolver.get_attack_damage(first, table._count_identical_on_board("ant")) == 6, "the displayed base 2 x3 matches six outgoing damage")
	_focus(second)
	await _capture("03-trio-closeup")
	closeup.clear_current()
	table._move_camera_to_match_view()
	await get_tree().create_timer(0.85).timeout
	await _capture("04-match-table")
	first.apply_curse(1)
	check(first.attack_label.text == "1" and _factor(first, 3) and CombatResolver.get_attack_damage(first, 3) == 3, "a curse updates the base attack while retaining the correct factor")
	first.apply_event_strength(2.0)
	check(first.attack_label.text == "2" and first.defense_label.text == "12" and _factor(first, 3), "strength events retain the suffix and only apply their own HP scaling")
	first.set_stats_hidden(true)
	check(not first.swarm_multiplier_label.visible, "hidden stats also hide the Swarm multiplier")
	first.set_stats_hidden(false)
	check(_factor(first, 3), "revealing unchanged stats restores the Swarm suffix")
	Localization.set_locale("de")
	check(_factor(first, 3) and first.attack_label.text == "2", "changing language preserves the multiplier and current battle stats")
	await _check_mirrors()
	third.take_damage(100)
	table._remove_dead_card(third, false, Vector3(INF, INF, INF), false)
	await _settle()
	check(_factor(first, 2) and _factor(second, 2), "a confirmed enemy death reduces both remaining multipliers")
	check(not third.swarm_multiplier_label.visible, "the dying card does not leave its suffix floating above the dissolve")
	second.take_damage(100)
	table._remove_dead_card(second, false, Vector3(INF, INF, INF), false)
	await _settle()
	check(not first.swarm_multiplier_label.visible and first.attack_label.text == "2", "returning to one living copy removes the multiplier")
	_spawn("player", 2)
	await _settle()
	check(_factor(first, 2), "a replacement draw restores the multiplier on the survivor")
	await table._wait_for_pending_card_deaths()
	table._clear_match()
	for side: String in ["player", "enemy"]:
		for slot in range(GameTable.HAND_SIZE):
			_spawn(side, slot)
	await _settle()
	for card: Card3D in table._player_slots + table._enemy_slots:
		check(_factor(card, 10) and card.attack_label.text == "2" and card.defense_label.text == "6", "a full board displays x10 without changing the printed base/HP")
	_focus(table._player_slots[2])
	await _capture("05-ten-copies")
	table._clear_match()
	var young := _spawn("player", 1, "chick")
	var growing := _spawn("player", 2, "chick")
	await _settle()
	check(_factor(young, 2) and _factor(growing, 2), "two real Chicks display their own Swarm factor")
	table._prepare_chick_turn()
	growing.set_meta("chick_survived_turns", 9)
	await table._advance_chick_growth()
	await _settle()
	check(not young.swarm_multiplier_label.visible and str(table._player_slots[2].card_data.id) == "chicken" and not table._player_slots[2].swarm_multiplier_label.visible, "Chick growth removes the former copy and its Swarm suffix")
	table._clear_match()
	main.queue_free()
	await _settle()
	print("SWARM_POWER_DISPLAY_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _spawn(side: String, slot: int, id: String = "ant") -> Card3D:
	identity += 1
	var data := CardDatabase.get_card(id).duplicate(true)
	data["instance_id"] = "swarm-display-%d" % identity
	var deck: Array[Dictionary] = table._player_deck if side == "player" else table._enemy_deck
	deck.append(data)
	table._draw_to_slot(side, slot, false)
	var card := table._get_card_from_slot(side, slot)
	card.description_label.skip()
	return card


func _factor(card: Card3D, value: int) -> bool:
	return card.swarm_multiplier_label.visible and card.swarm_multiplier_label.text == "×%d" % value


func _settle() -> void:
	# Exercise the production table refresh, without calling its helper directly.
	await get_tree().process_frame
	await get_tree().process_frame


func _focus(card: Card3D) -> void:
	closeup.global_position = card.global_position + Vector3(0, 2.5, 0.65)
	closeup.look_at(card.global_position, Vector3.FORWARD)
	closeup.make_current()


func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(get_tree().root.get_texture().get_image().save_png(output.path_join(filename + ".png")) == OK, "rendered " + filename)


func _check_mirrors() -> void:
	var snapshot := table._build_online_snapshot()
	for spectator: bool in [false, true]:
		var mirror := (load("res://scenes/table/GameTable.tscn") as PackedScene).instantiate() as GameTable
		mirror.table_camera = table.table_camera
		get_tree().root.add_child(mirror)
		mirror.hide()
		mirror._table_state = GameTable.TableState.PLAYING
		mirror._online_is_spectator = spectator
		var near_side := "player" if spectator else "enemy"
		var far_side := "enemy" if spectator else "player"
		mirror._reconcile_online_slots("player", snapshot[near_side + "_slots"], false)
		mirror._reconcile_online_slots("enemy", snapshot[far_side + "_slots"], false)
		await _settle()
		var near := mirror._get_card_from_slot("player", 1 if spectator else 2)
		var far := mirror._get_card_from_slot("enemy", 2 if spectator else 1)
		check(_factor(near, 3) and _factor(far, 3), ("spectator" if spectator else "invited player") + " reconstructs the factor from mirrored board state")
		mirror._reconcile_online_slots("player", snapshot[near_side + "_slots"], false)
		await _settle()
		check(_factor(near, 3) and mirror._serialize_online_slots(mirror._player_slots) == snapshot[near_side + "_slots"], "repeated snapshots retain the suffix without changing canonical combat state")
		mirror._clear_match()
		mirror.queue_free()
		await _settle()
