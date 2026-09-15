extends Node3D

var _checks := 0
var _failures: Array[String] = []
var _identity := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Run event_cards_test with the isolated match feature test runner.")
		get_tree().quit(1)
		return
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	main.visible = false
	main.set_process(false)
	main.set_physics_process(false)
	for canvas in main.find_children("*", "CanvasLayer", true, false):
		canvas.visible = false
	var table := main.get_node("ScenePivot/GameTable") as GameTable
	table.enemy_turn_delay = 60.0
	table.draw_animation_duration = 0.02
	table.replacement_draw_delay = 0.02
	table.blood_burst_scene = null
	table.blood_decal_scene = null
	_check_draw_rules(table)
	_check_switch(table)
	await _check_switch_hand_click(table)
	_check_strength_and_turn_gate(table)
	await _check_block(table)
	await _check_steel(table)
	await _check_kill_triggers(table)
	await _check_mutual_and_multiple_kills(table)
	await _check_ai_and_blocked_pass(table)
	_check_authority(table)
	table._clear_match()
	_expect(table._event_deck.is_empty() and table._event_discard.is_empty(), "Leaving a match clears both shared event piles")
	_expect(table._player_event_hand.is_empty() and table._enemy_event_hand.is_empty(), "Leaving a match clears both event hands")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	for failure: String in _failures:
		push_error(failure)
	print("EVENT_CARD_TESTS: %s (%d checks)" % ["PASS" if _failures.is_empty() else "FAIL", _checks])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _reset(table: GameTable) -> void:
	table._clear_match()
	table._reset_online_sync_tracking()
	table._online_mode = false
	table._online_is_host = false
	table._online_is_spectator = false
	table._online_action_in_progress = false
	table._local_action_in_progress = false
	table._table_state = GameTable.TableState.PLAYING
	table._current_turn = "player"
	table._initialize_event_deck()


func _data(attack: int = 2, health: int = 10, effects: Array = []) -> Dictionary:
	_identity += 1
	var data := CardDatabase.get_card("corpse").duplicate(true)
	data["instance_id"] = "event-test-%d" % _identity
	data["attack"] = attack
	data["defense"] = health
	data["animated"] = false
	data["effects"] = effects.duplicate(true)
	data["active_effects"] = effects.duplicate(true)
	return data


func _spawn(table: GameTable, side: String, slot: int, data: Dictionary) -> Card3D:
	var deck: Array[Dictionary] = table._player_deck if side == "player" else table._enemy_deck
	deck.append(data)
	table._draw_to_slot(side, slot, false)
	var slots: Array[Card3D] = table._player_slots if side == "player" else table._enemy_slots
	return slots[slot]


func _give(table: GameTable, side: String, event_id: String) -> Dictionary:
	for index in range(table._event_deck.size()):
		if str(table._event_deck[index]["id"]) == event_id:
			var event := table._event_deck[index]
			table._event_deck.remove_at(index)
			var hand: Array[Dictionary] = table._player_event_hand if side == "player" else table._enemy_event_hand
			hand.append(event)
			return event
	_expect(false, "Requested fixture event exists: " + event_id)
	return {}


func _check_draw_rules(table: GameTable) -> void:
	_reset(table)
	_expect(table._event_deck.size() == 24, "The third shared pile contains 24 shuffled events")
	_expect(table._player_event_hand.is_empty() and table._enemy_event_hand.is_empty(), "Building the shared pile alone does not deal the separate opening hands")
	_spawn(table, "player", 0, _data())
	_spawn(table, "enemy", 0, _data())
	_expect(table._event_deck.size() == 24 and table._player_event_hand.is_empty(), "Ordinary combat-card draws never grant event cards")
	table._draw_event_card("player")
	table._draw_event_card("enemy")
	_expect(table._player_event_hand.size() == 1 and table._enemy_event_hand.size() == 1 and table._event_deck.size() == 22, "Both players draw into separate hands from the same pile")
	_expect(table._player_slots[1] == null and table._enemy_slots[1] == null, "An event draw never fills a combat slot")
	_expect(table._player_event_hand[0]["uid"] != table._enemy_event_hand[0]["uid"], "The shared pile cannot award one physical event to both players")


func _check_switch(table: GameTable) -> void:
	_reset(table)
	_spawn(table, "player", 0, _data())
	_spawn(table, "enemy", 0, _data())
	var near := [_data(), _data(), _data()]
	var far := [_data(), _data(), _data()]
	table._player_deck.assign(near)
	table._enemy_deck.assign(far)
	var event := _give(table, "player", "switch")
	_expect(not table._try_play_event("player", event["uid"], 0), "Switch rejects attempts to supply a combat-card target")
	_expect(table._try_play_event("player", event["uid"]), "Switch can be played without a table target")
	_expect(table._player_deck.size() == 3 and table._enemy_deck.size() == 3, "Switch preserves both draw-pile sizes")
	var near_in_far := 0
	var far_in_near := 0
	for card: Dictionary in table._enemy_deck:
		near_in_far += int(near.has(card))
	for card: Dictionary in table._player_deck:
		far_in_near += int(far.has(card))
	_expect(near_in_far == 1 and far_in_near == 1, "Switch exchanges exactly one complete card instance in each direction")
	_expect(table._current_turn == "player" and table._event_discard.size() == 1, "Playing an event discards it and leaves the attack available")
	_reset(table)
	_spawn(table, "player", 0, _data())
	_spawn(table, "enemy", 0, _data())
	event = _give(table, "player", "switch")
	table._player_deck.append(_data())
	_expect(not table._try_play_event("player", event["uid"]), "Switch rejects an empty opponent draw pile")
	_expect(table._player_event_hand.size() == 1 and table._event_discard.is_empty() and not table._event_played_this_turn, "An impossible event stays in hand and does not spend the turn's event")


func _click_event_hand_card(table: GameTable, uid: String) -> void:
	table._refresh_event_hand()
	for card: Control in table._event_hand_ui.get("_cards"):
		if str(card.get("uid")) == uid:
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			# Exercise the real card input handler and both connected UI signals.
			card.call("_gui_input", click)
			return
	_expect(false, "The event to click exists in the real hand UI")


func _check_switch_hand_click(table: GameTable) -> void:
	_reset(table)
	_spawn(table, "player", 0, _data())
	_spawn(table, "enemy", 0, _data())
	var own_draw := _data()
	var enemy_draw := _data()
	table._player_deck.append(own_draw)
	table._enemy_deck.append(enemy_draw)
	var event := _give(table, "player", "switch")
	_click_event_hand_card(table, event["uid"])
	_expect(table._player_deck[0] == enemy_draw and table._enemy_deck[0] == own_draw, "One click on the actual Switch hand card immediately exchanges the draw cards")
	_expect(table._selected_event_uid.is_empty() and table._player_event_hand.is_empty(), "A successful Switch never waits for a table target and leaves the hand immediately")
	await get_tree().create_timer(0.9).timeout
	_expect(table._current_turn == "player" and table._can_local_event_or_attack(), "After the Switch animation, the same player can still attack")
	_reset(table)
	_spawn(table, "player", 0, _data())
	_spawn(table, "enemy", 0, _data())
	table._player_deck.append(_data())
	event = _give(table, "player", "switch")
	_click_event_hand_card(table, event["uid"])
	table._refresh_event_hand()
	_expect(table._selected_event_uid.is_empty() and str(table._event_hand_ui.get("_selected_uid")).is_empty(), "An impossible Switch click never enters table-target selection")
	_expect(table._player_event_hand.size() == 1 and table._event_discard.is_empty() and not table._event_played_this_turn, "An impossible Switch click preserves its card and the turn's event allowance")
	_expect(table._can_local_event_or_attack() and not table._event_notice.is_empty(), "An impossible Switch explains the problem while leaving normal attacks available")
	var block := _give(table, "player", "block")
	_click_event_hand_card(table, block["uid"])
	_expect(table._selected_event_uid == block["uid"] and not table._enemy_slots[0].is_event_blocked(), "Clicking targeted Block still waits for the chosen enemy card")


func _check_strength_and_turn_gate(table: GameTable) -> void:
	for entry in [["strength_120", 1.2], ["strength_150", 1.5], ["strength_200", 2.0]]:
		_reset(table)
		var own := _spawn(table, "player", 0, _data(3, 10))
		own.current_hp = 7
		var enemy := _spawn(table, "enemy", 0, _data())
		var event := _give(table, "player", str(entry[0]))
		var multiplier := float(entry[1])
		_expect(not table._try_play_event("player", event["uid"], 4), "Strength rejects an empty table slot")
		_expect(not table._try_play_event("player", "forged-event", 0), "Unknown event identities cannot be played")
		_expect(table._try_play_event("player", event["uid"], 0), str(entry[0]) + " strengthens a selected allied card")
		_expect(own.attack_value == ceili(3 * multiplier) and own.max_hp == ceili(10 * multiplier) and own.current_hp == ceili(7 * multiplier), "Strength scales current attack, max HP and damaged current HP, rounding up")
		_expect(enemy.attack_value == 2 and enemy.current_hp == 10, "Strength leaves the opposing card unchanged")
		var second := _give(table, "player", "block")
		_expect(not table._try_play_event("player", second["uid"], 0), "Only one event can be played before a turn's attack")
		_expect(table._player_event_hand.size() == 1, "A rejected second event remains in hand")
		var snapshot := own.get_network_state()
		own.apply_network_state(snapshot)
		_expect(own.attack_value == ceili(3 * multiplier) and own.current_hp == ceili(7 * multiplier), "Strength survives card state serialization")


func _check_block(table: GameTable) -> void:
	_reset(table)
	var player := _spawn(table, "player", 0, _data(1, 20))
	var enemy := _spawn(table, "enemy", 0, _data(8, 20))
	var event := _give(table, "player", "block")
	_expect(not table._try_play_event("player", event["uid"], -1), "Block requires an explicit enemy target")
	_expect(table._try_play_event("player", event["uid"], 0) and enemy.is_event_blocked(), "Block marks the selected enemy card")
	_expect(enemy.event_block_turns == 2 and not player.is_event_blocked(), "Block starts at two turns on its target only")
	await table._resolve_duel(enemy, player, "enemy")
	_expect(player.current_hp == 20 and enemy.current_hp == 20, "A blocked attacker cannot resolve a duel")
	await table._resolve_duel(player, enemy, "player")
	_expect(enemy.current_hp == 19 and player.current_hp == 20, "A blocked defender takes damage without counterattacking")
	_expect(table._current_turn == "enemy" and enemy.event_block_turns == 2, "The attack ends the player's turn without consuming an opposing blocked turn")
	table._tick_event_blocks("enemy")
	_expect(enemy.event_block_turns == 1 and enemy.is_event_blocked(), "The first completed enemy turn leaves one blocked turn")
	table._tick_event_blocks("player")
	_expect(enemy.event_block_turns == 1, "The other player's turns do not age the block")
	var snapshot := enemy.get_network_state()
	enemy.apply_network_state(snapshot)
	_expect(enemy.event_block_turns == 1, "Remaining block duration survives card state serialization")
	table._tick_event_blocks("enemy")
	_expect(not enemy.is_event_blocked(), "The second completed enemy turn releases the blocked card")


func _check_steel(table: GameTable) -> void:
	_reset(table)
	_spawn(table, "player", 0, _data())
	var enemy := _spawn(table, "enemy", 0, _data(7, 20, [{"type": "shield_first_hit"}]))
	var stolen_identity := str(enemy.card_data["instance_id"])
	enemy.current_hp = 9
	enemy.attack_value = 11
	enemy._first_hit_shield_available = false
	enemy.set_meta("poison_turns", 2)
	enemy.set_meta("poison_damage", 3)
	enemy.apply_event_block(1)
	var replacement := _data(3, 30)
	table._enemy_deck.append(replacement)
	var event := _give(table, "player", "steel")
	_expect(table._try_play_event("player", event["uid"], 0), "Steel accepts the chosen opponent card even while it is blocked")
	await get_tree().create_timer(0.85).timeout
	_expect(table._player_deck.size() == 1 and table._enemy_deck.is_empty(), "Steel moves one card to the player's draw pile and consumes one enemy replacement")
	_expect(is_instance_valid(table._enemy_slots[0]) and table._enemy_slots[0].card_data["instance_id"] == replacement["instance_id"], "The opponent's empty slot receives the replacement card")
	table._draw_to_slot("player", 1, false)
	var stolen := table._player_slots[1]
	_expect(is_instance_valid(stolen) and str(stolen.card_data["instance_id"]) == stolen_identity, "The stolen physical card returns through the new owner's combat draw pile")
	_expect(stolen.attack_value == 11 and stolen.current_hp == 9 and stolen.max_hp == 20, "Stealing preserves modified attack and existing damage")
	var state := stolen.get_network_state()
	_expect(not bool(state["first_hit_shield_available"]) and int(state["poison_turns"]) == 2 and int(state["poison_damage"]) == 3, "Stealing preserves consumed one-shot effects and poison")
	_expect(stolen.event_block_turns == 1, "Stealing preserves remaining block duration")
	_reset(table)
	_spawn(table, "player", 0, _data())
	_spawn(table, "enemy", 0, _data())
	_spawn(table, "enemy", 1, _data())
	event = _give(table, "player", "steel")
	_expect(table._try_play_event("player", event["uid"], 0), "Steel still works when the opponent cannot draw a replacement")
	await get_tree().create_timer(0.85).timeout
	_expect(table._enemy_slots[0] == null and table._player_deck.size() == 1, "An exhausted enemy draw pile leaves the stolen slot empty")


func _check_kill_triggers(table: GameTable) -> void:
	for has_draw_effect in [false, true]:
		_reset(table)
		var attack_data := _data(20, 30)
		if has_draw_effect:
			attack_data = CardDatabase.get_card("mailman").duplicate(true)
			attack_data["attack"] = 20
			attack_data["defense"] = 30
		var attacker := _spawn(table, "player", 0, attack_data)
		var target := _spawn(table, "enemy", 0, _data(1, 1))
		_spawn(table, "enemy", 1, _data(1, 30))
		table._player_deck.append(_data())
		table._enemy_deck.append(_data())
		await table._resolve_duel(attacker, target, "player")
		_expect(table._player_event_hand.size() == int(has_draw_effect) and table._event_deck.size() == 24 - int(has_draw_effect), "Only a real kill with Draw On Kill grants an event")
		_expect(table._player_slots[1] == null and table._player_deck.size() == 1, "Draw On Kill never grants an extra combat card")
		_expect(table._current_turn == "enemy", "The attack immediately ends its turn")
		if has_draw_effect:
			_expect(not table._try_play_event("player", table._player_event_hand[0]["uid"], 1), "The event earned during an attack waits for the next own turn")
	_reset(table)
	var mailman := _spawn(table, "enemy", 0, _data(20, 30, [{"type": "draw_on_kill"}]))
	var near_target := _spawn(table, "player", 0, _data(1, 1))
	_spawn(table, "player", 1, _data())
	table._current_turn = "enemy"
	await table._resolve_duel(mailman, near_target, "enemy")
	_expect(table._enemy_event_hand.size() == 1 and table._player_event_hand.is_empty(), "An opposing fighter earns its own event hand through the same kill effect")


func _check_mutual_and_multiple_kills(table: GameTable) -> void:
	_reset(table)
	var attacker := _spawn(table, "player", 0, _data(5, 1, [{"type": "draw_on_kill"}]))
	var defender := _spawn(table, "enemy", 0, _data(5, 1, [{"type": "draw_on_kill"}]))
	_spawn(table, "player", 1, _data())
	_spawn(table, "enemy", 1, _data())
	await table._resolve_duel(attacker, defender, "player")
	_expect(table._player_event_hand.size() == 1 and table._enemy_event_hand.size() == 1, "Mutual lethal attacks grant each eligible fighter its own kill event")
	_expect(table._event_deck.size() == 22, "A mutual kill removes exactly two cards from the shared pile")
	_reset(table)
	attacker = _spawn(table, "player", 0, _data(5, 40, [{"type": "lava"}, {"type": "draw_on_kill"}]))
	for index in range(3):
		_spawn(table, "enemy", index, _data(1, 1))
	_spawn(table, "enemy", 4, _data(1, 30))
	await table._resolve_duel(attacker, table._enemy_slots[0], "player")
	_expect(table._player_event_hand.size() == 3 and table._event_deck.size() == 21, "A simultaneous Lava multi-kill grants exactly one event per defeated card")
	var awarded: Dictionary = {}
	for event: Dictionary in table._player_event_hand:
		awarded[event["uid"]] = true
	_expect(awarded.size() == 3 and table._enemy_event_hand.is_empty(), "Multi-kill rewards are distinct events in the attacking fighter's hand")


func _check_ai_and_blocked_pass(table: GameTable) -> void:
	_reset(table)
	var player := _spawn(table, "player", 0, _data(1, 30))
	var enemy := _spawn(table, "enemy", 0, _data(2, 30))
	_give(table, "enemy", "strength_200")
	table._current_turn = "enemy"
	await table._play_enemy_turn(table._match_generation)
	_expect(table._enemy_event_hand.is_empty() and table._event_discard.size() == 1, "The AI plays a useful event from its own hand")
	_expect(enemy.attack_value == 4 and player.current_hp == 26, "The AI strengthens its fighter before using the stronger attack")
	_expect(table._current_turn == "player" and not table._event_played_this_turn, "The AI attack hands over the turn and renews the event allowance")
	_reset(table)
	player = _spawn(table, "player", 0, _data(1, 30))
	enemy = _spawn(table, "enemy", 0, _data(2, 30))
	table._request_event_pass()
	_expect(table._current_turn == "player", "A fighter with an available attacker cannot skip its attack")
	player.apply_event_block(2)
	enemy.apply_event_block(2)
	table._request_event_pass()
	_expect(table._current_turn == "enemy" and player.event_block_turns == 1, "A fully blocked player can pass and consume its first blocked turn")
	await table._play_enemy_turn(table._match_generation)
	_expect(table._current_turn == "player" and enemy.event_block_turns == 1, "A fully blocked AI also passes instead of deadlocking the match")
	table._request_event_pass()
	await table._play_enemy_turn(table._match_generation)
	_expect(table._current_turn == "player" and not player.is_event_blocked() and not enemy.is_event_blocked(), "Passing two blocked turns restores both fighters' attack choices")
	_expect(player.current_hp == 30 and enemy.current_hp == 30, "Passing blocked turns causes no attacks or damage")


func _check_authority(table: GameTable) -> void:
	_reset(table)
	_spawn(table, "player", 0, _data())
	_spawn(table, "enemy", 0, _data())
	var event := _give(table, "player", "block")
	table._online_mode = true
	table._online_is_host = false
	_expect(not table._try_play_event("player", event["uid"], 0), "An online client cannot mutate authoritative event state directly")
	table._online_is_spectator = true
	_expect(not table._try_play_event("player", event["uid"], 0), "A spectator cannot play an event")
	table._online_mode = false
	table._online_is_spectator = false
	_expect(table._player_event_hand.size() == 1 and not table._enemy_slots[0].is_event_blocked(), "Rejected network actions leave the hand and target untouched")


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		_failures.append(description)

