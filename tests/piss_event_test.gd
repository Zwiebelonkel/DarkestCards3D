extends Node3D

var checks := 0
var failures := 0
var identity := 0
var main: MainScene
var table: GameTable
var measurements: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
	print(("PASS " if condition else "FAIL ") + description)


func _reset() -> void:
	table._clear_match()
	table._online_mode = false
	table._online_is_host = false
	table._online_is_spectator = false
	table._table_state = GameTable.TableState.PLAYING
	table._current_turn = "player"
	table._initialize_event_deck()
	for slot in range(5):
		_spawn("player", slot)
		_spawn("enemy", slot)


func _spawn(side: String, slot: int) -> Card3D:
	identity += 1
	var data := CardDatabase.get_card("corpse").duplicate(true)
	data["instance_id"] = "piss-test-%d" % identity
	data["attack"] = 7
	data["defense"] = 90
	data["animated"] = false
	data["effects"] = [{"type": "lifesteal", "value": 0.25}]
	data["active_effects"] = data["effects"].duplicate(true)
	var deck := table._player_deck if side == "player" else table._enemy_deck
	deck.append(data)
	table._draw_to_slot(side, slot, false)
	return table._get_card_from_slot(side, slot)


func _give(side: String) -> Dictionary:
	for event: Dictionary in table._event_deck:
		if event["id"] == "piss_event":
			table._event_deck.erase(event)
			table._event_hand(side).append(event)
			return event
	check(false, "Piss is available in the match deck")
	return {}


func _all_hidden(hidden: bool) -> bool:
	for card: Card3D in table._player_slots + table._enemy_slots:
		if not is_instance_valid(card) or card.stats_hidden != hidden:
			return false
		if hidden and (not card.attack_label.text.is_empty() or not card.defense_label.text.is_empty()
			or not is_instance_valid(card._stat_puddles) or not card._stat_puddles.visible
			or not card.get_available_effects().is_empty() or card.effect_icon_1.visible
			or card._combat_indicators.visible):
			return false
	return true


func _finish_turn(next: String) -> void:
	# Enemy delay stays pending; its generation guard prevents stale AI work.
	table._end_turn_to(next)
	await get_tree().process_frame
	await get_tree().process_frame


func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://piss-event-" + name + ".png")


func _measure_frames(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var times: Array[float] = []
	var draws := 0.0
	for frame in range(30):
		await get_tree().process_frame
		times.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	times.sort()
	var total := 0.0
	for sample in times:
		total += sample
	measurements[label] = {"samples": times.size(), "average_process_ms": total / times.size(),
		"p95_process_ms": times[ceili(times.size() * 0.95) - 1], "average_draw_calls": draws / times.size()}


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		push_error("Run with isolated match-feature saves.")
		get_tree().quit(1)
		return
	AudioServer.set_bus_mute(0, true)
	get_tree().root.size = Vector2i(1280, 720)
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.greeting_enabled = false
	add_child(main)
	main.set_process(false)
	main.mouse_tilt_strength = 0.0
	table = main.get_node("ScenePivot/GameTable") as GameTable
	table.enemy_turn_delay = 0.5
	table.draw_animation_duration = 0.01
	table.menu_root.hide()
	table.matchmaking_screen.hide()
	table.match_hud.show_for_match(false)
	table._move_camera_to_match_view()
	await get_tree().create_timer(0.8).timeout
	var definitions := EventDeck.definitions().filter(func(event: Dictionary) -> bool: return event["id"] == "piss_event")
	check(definitions.size() == 1 and definitions[0]["rarity"] == "legendary" and definitions[0]["copies"] == 1 and definitions[0]["target"] == "none", "one targetless legendary Piss joins the existing events")
	check(CardDatabase.get_card("piss")["name"] == "Pisse-Eimer", "the collectible Piss Bucket remains a separate combat card")
	check(CardDatabase.is_collectible_card("piss"), "Piss Bucket stays eligible for collection, packs and the journal")
	_reset()
	var event := _give("player")
	check(not table._try_play_event("player", event["uid"], 0) and table._player_event_hand.size() == 1, "Piss rejects a target without consuming the event")
	table._refresh_event_hand()
	for hand_card: Control in table._event_hand_ui.get("_cards"):
		if str(hand_card.get("uid")) == str(event["uid"]):
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			hand_card.call("_gui_input", click)
	check(table._player_event_hand.is_empty() and table._selected_event_uid.is_empty() and table._event_discard.size() == 1, "one real hand click immediately plays Piss without target selection")
	check(_all_hidden(false) and table._piss_hidden_turns["enemy"] == 2 and table._piss_hidden_turns["player"] == 0, "the caster still sees all ten cards while the opponent receives two turns of blindness")
	check(table._current_turn == "player" and table._event_played_this_turn, "Piss preserves the current attack and spends the turn's event allowance")
	check(table._event_piss_stream.active and table._event_piss_stream.particles.emitting and table._event_piss_stream.piss_sfx.playing, "the event starts the existing yellow stream and audio")
	check(table.to_local(table._event_piss_stream.source_position).z > 0, "a local caster's stream starts on the near side")
	await get_tree().create_timer(0.3).timeout
	await _capture("legendary-card")
	await get_tree().create_timer(0.6).timeout
	check(table._can_local_event_or_attack(), "the caster can attack after the event reveal")
	await _finish_turn("enemy")
	check(table._piss_hidden_turns["enemy"] == 2, "ending the caster's turn does not consume the opponent's first blinded turn")
	await _finish_turn("player")
	check(table._piss_hidden_turns["enemy"] == 1, "the first opposing turn consumes exactly one turn")

	_reset()
	table.menu_root.hide()
	table.matchmaking_screen.hide()
	table.match_hud.show_for_match(false)
	(main.get_node("WorldEnvironment") as WorldEnvironment).environment.glow_enabled = false
	var visor := main.get_node("CameraPivot/CameraTilt/Camera3D/LevelProgress")
	visor.set_process(false)
	visor.set_expanded(false)
	table._move_camera_to_match_view()
	await get_tree().create_timer(0.8).timeout
	await _measure_frames("before")
	await _capture("before")
	var card := table._player_slots[0]
	table._on_effect_card_hovered(card)
	await get_tree().create_timer(0.2).timeout
	check(table._effect_overview.visible, "the normal hover displays live card effects before Piss")
	event = _give("enemy")
	table._current_turn = "enemy"
	table._local_action_in_progress = true
	await table._play_enemy_event()
	check(_all_hidden(true), "an AI Piss conceals both players' stats, effect icons and status counts")
	check(not table._effect_overview.visible and card.description_label.text == "?", "an already-open hover and card description cannot reveal hidden values")
	check(table.to_local(table._event_piss_stream.source_position).z < 0, "an opposing caster's stream starts on the far side")
	var stream = table._event_piss_stream
	check(stream.trajectory_position(stream.flight_seconds).distance_to(stream.target_position) < 0.001, "the ballistic stream lands at its table target")
	var surface := table.get_node("table/Cube") as MeshInstance3D
	var landing := surface.to_local(stream.target_position)
	var bounds := surface.get_aabb()
	check(absf(landing.y - bounds.end.y) < 0.001 and landing.x > bounds.position.x and landing.x < bounds.end.x and landing.z > bounds.position.z and landing.z < bounds.end.z, "the circling landing stays on the actual tabletop")
	await _measure_frames("stream_hidden")
	await _capture("stream-hidden")
	var state_before := card.get_network_state()
	card.apply_event_strength(1.5)
	card.apply_curse(2)
	card.take_damage(11)
	card.heal(3)
	card.apply_event_block(2)
	card.apply_poison(1, 2)
	card.apply_network_state(card.get_network_state())
	check(card.attack_value == 9 and card.current_hp == 127 and card.attack_label.text.is_empty() and card.defense_label.text.is_empty() and card._stat_puddles.visible and not card._event_block_badge.visible, "damage, healing, curse, strength, block and snapshots update real stats beneath the yellow puddles")
	check(not state_before.has("stats_hidden") and not card.export_event_deck_card().has("stats_hidden"), "viewer concealment never becomes a card's transferable combat state")
	table._spawn_damage_number(card, 10)
	table._spawn_healing_number(card, 10)
	check(table._damage_numbers.is_empty(), "floating damage and healing numbers remain concealed")
	var old_locale := Localization.get_locale()
	for locale: String in Localization.SUPPORTED_LOCALES:
		Localization.set_locale(locale)
		var translated := EventDeck.get_display_description(definitions[0])
		check(card.attack_label.text.is_empty() and card._stat_puddles.visible and card.description_label.text == "?" and not translated.is_empty()
			and (locale == "de" or translated != definitions[0]["description"]), "language changes preserve concealment and translate Piss: " + locale)
	Localization.set_locale(old_locale)
	var old := table._enemy_slots[4]
	table._enemy_slots[4] = null
	old.queue_free()
	var replacement := _spawn("enemy", 4)
	check(replacement.stats_hidden and replacement.attack_label.text.is_empty() and replacement._stat_puddles.visible, "newly drawn cards inherit the viewer's yellow puddles")
	await _finish_turn("player")
	check(table._piss_hidden_turns["player"] == 2 and _all_hidden(true), "blindness starts with two complete affected-player turns")
	for own: Card3D in table._player_slots:
		own.apply_event_block(2)
	table._request_event_pass()
	await get_tree().process_frame
	await get_tree().process_frame
	check(table._piss_hidden_turns["player"] == 1 and _all_hidden(true), "passing the first fully blocked affected turn keeps every card concealed")
	await _finish_turn("player")
	check(table._piss_hidden_turns["player"] == 1 and _all_hidden(true), "the other side's turn cannot shorten blindness")
	table._request_event_pass()
	await get_tree().process_frame
	await get_tree().process_frame
	check(table._piss_hidden_turns["player"] == 0 and _all_hidden(false), "all values return after the second affected turn")
	check(card.attack_label.text == str(card.attack_value) and card.defense_label.text == str(card.current_hp) and not card._stat_puddles.visible and card.effect_icon_1.visible, "restoration removes puddles and reveals the latest real values and available effects")
	await _capture("restored")
	table._piss_hidden_turns["player"] = 1
	table._refresh_piss_visibility()
	table._event_played_this_turn = false
	table._local_action_in_progress = false
	table._current_turn = "enemy"
	table._enemy_event_hand.append(event)
	check(table._try_play_event("enemy", event["uid"]) and table._piss_hidden_turns["player"] == 2, "a later Piss refreshes an existing duration to two turns")
	table._online_is_spectator = true
	table._refresh_piss_visibility()
	check(_all_hidden(false), "spectators retain the normal table view")
	table._online_is_spectator = false
	table._refresh_piss_visibility()
	card.begin_death_dissolve()
	check(not card._stat_puddles.visible, "confirmed card death removes the yellow stat puddles before its dissolve")
	card._update_hp_label()
	check(not card._stat_puddles.visible, "a late HP update cannot restore puddles on a dissolving card")
	table._clear_match()
	check(table._piss_hidden_turns["player"] == 0 and table._piss_hidden_turns["enemy"] == 0 and not stream.active and not stream.particles.visible and not stream.piss_sfx.playing, "match cleanup clears duration, particles and audio immediately")
	check(not main._satan_stream.active, "the separate hub stream remains idle throughout the event")
	# Let cancelled turn continuations release their retained resources.
	await get_tree().create_timer(0.6).timeout
	main.queue_free()
	await get_tree().create_timer(0.3).timeout
	if not measurements.is_empty():
		var report := FileAccess.open("res://piss-event-performance.json", FileAccess.WRITE)
		report.store_string(JSON.stringify(measurements, "\t"))
		report.close()
	print("PISS_EVENT_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
