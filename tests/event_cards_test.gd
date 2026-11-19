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
	await _check_stacked_hand(table)
	_check_strength_and_turn_gate(table)
	await _check_heal(table)
	await _check_rearrange(table)
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
	await get_tree().create_timer(0.3).timeout
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


func _check_rearrange(table: GameTable) -> void:
	_reset(table)
	var a := _spawn(table, "player", 0, _data(7, 30, [{"type": "shield_first_hit"}]))
	var b := _spawn(table, "player", 3, _data(4, 40))
	var enemy := _spawn(table, "enemy", 0, _data())
	a.consume_first_hit_shield()
	a.take_damage(12)
	a.apply_poison(2, 3)
	a.apply_event_block(2)
	var before := a.get_network_state()
	var event := _give(table, "player", "rearrange_event")
	_expect(not table._try_play_event("player", event["uid"], 0) and not table._try_play_event("player", event["uid"], 0, 0) and not table._try_play_event("player", event["uid"], 0, 2), "Rearrange rejects missing, identical and empty targets")
	_click_event_hand_card(table, event["uid"])
	table._on_event_target_clicked("enemy", 0)
	_expect(table._rearrange_first_card == null and table._player_event_hand.size() == 1, "Rearrange cannot select an enemy card")
	table._on_event_target_clicked("player", 0)
	_expect(table._rearrange_first_card == a and a._is_selected and table._player_slots[0] == a, "The first allied click highlights a card without moving or consuming it")
	table._on_event_target_clicked("player", 0)
	_expect(table._player_event_hand.size() == 1 and table._rearrange_first_card == a, "Clicking the same card twice keeps the selection and event")
	table._cancel_event_selection()
	_expect(table._rearrange_first_card == null and not a._is_selected and table._player_event_hand.size() == 1, "Cancelling restores the first card without spending Rearrange")
	_click_event_hand_card(table, event["uid"])
	table._on_event_target_clicked("player", 0)
	table._on_event_target_clicked("player", 3)
	_expect(table._player_slots[0] == b and table._player_slots[3] == a and table._enemy_slots[0] == enemy, "Two allied clicks swap exactly those nodes and leave the enemy row intact")
	_expect(a.get_network_state() == before, "Rearrange preserves damage, poison, block and consumed protection")
	_expect(table._player_event_hand.is_empty() and table._event_discard.size() == 1 and table._current_turn == "player", "Rearrange consumes one event and preserves the attack turn")
	await get_tree().create_timer(0.9).timeout
	_expect(a.global_position.is_equal_approx(table._get_slot_marker("player", 3).global_position) and b.global_position.is_equal_approx(table._get_slot_marker("player", 0).global_position), "Both cards finish their movement at the new table markers")
	a.clear_selected_immediate()
	_expect(a.global_position.is_equal_approx(table._get_slot_marker("player", 3).global_position), "Later selection cleanup cannot return a moved card to its old position")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	b.area.input_event.emit(table.table_camera, click, Vector3.ZERO, Vector3.UP, 0)
	_expect(table._selected_player_card == b, "Clicking a moved card selects the card at its new slot")
	_expect(a.died.get_connections().size() == 1 and a.died.get_connections()[0]["callable"].get_bound_arguments() == ["player", 3], "Death and replacement callbacks follow the new slot")
	var replacement := _data()
	table._player_deck.append(replacement)
	a.take_damage(a.current_hp)
	table._remove_dead_card(a)
	await table._wait_for_pending_card_deaths()
	_expect(table._player_slots[0] == b and is_instance_valid(table._player_slots[3]) and table._player_slots[3].card_data["instance_id"] == replacement["instance_id"], "A moved card's death draws its replacement into the new slot")
	_reset(table)
	_spawn(table, "player", 0, _data())
	a = _spawn(table, "enemy", 1, _data())
	b = _spawn(table, "enemy", 4, _data())
	_give(table, "enemy", "rearrange_event")
	table._current_turn = "enemy"
	await table._play_enemy_event()
	_expect(table._enemy_slots[1] == b and table._enemy_slots[4] == a and table._enemy_event_hand.is_empty(), "The AI can swap two of its living cards")


func _check_heal(table: GameTable) -> void:
	_reset(table)
	var card := _spawn(table, "player", 0, _data(7, 20, [{"type": "shield_first_hit"}]))
	var enemy := _spawn(table, "enemy", 0, _data(4, 30))
	var event := _give(table, "player", "heal_event")
	_expect(not table._try_play_event("player", event["uid"], 0), "Heal rejects a full-health card without wasting the event")
	_expect(table._player_event_hand.size() == 1 and not table._event_played_this_turn, "An unnecessary Heal preserves the hand and event allowance")
	_expect(not table._try_play_event("player", event["uid"], -1) and not table._try_play_event("player", event["uid"], 4), "Heal requires a living explicit target")
	card.consume_first_hit_shield()
	card.apply_event_strength(1.5)
	card.take_damage(23)
	card.apply_poison(2, 3)
	card.apply_event_block(2)
	card.apply_curse(2)
	var hp_before := card.current_hp
	_click_event_hand_card(table, event["uid"])
	_expect(table._selected_event_uid == event["uid"] and card.current_hp == hp_before, "Clicking Heal waits for the chosen allied card")
	table._on_event_target_clicked("enemy", 0)
	_expect(card.current_hp == hp_before and enemy.current_hp == 30 and table._player_event_hand.size() == 1, "Heal cannot target an opposing card")
	table._on_event_target_clicked("player", 0)
	_expect(card.current_hp == 30 and card.max_hp == 30 and card.attack_value == 9, "Heal restores the buffed maximum HP and preserves modified attack")
	_expect(not card._first_hit_shield_available and card.event_block_turns == 2 and card.get_meta("poison_turns") == 3, "Heal leaves poison, block and consumed protection unchanged")
	_expect(table._player_event_hand.is_empty() and table._event_discard.size() == 1 and table._current_turn == "player", "Heal consumes one event while leaving the attack available")
	var second := _give(table, "player", "heal_event")
	card.take_damage(1)
	_expect(not table._try_play_event("player", second["uid"], 0) and card.current_hp == 29, "A second Heal cannot bypass the one-event rule")
	await get_tree().create_timer(0.9).timeout
	_expect(table._can_local_event_or_attack(), "Attacking is available after Heal's reveal")
	_reset(table)
	_spawn(table, "player", 0, _data())
	var full := _spawn(table, "enemy", 0, _data(3, 40))
	var wounded := _spawn(table, "enemy", 1, _data(3, 50))
	wounded.take_damage(49)
	_give(table, "enemy", "heal_event")
	table._current_turn = "enemy"
	await table._play_enemy_event()
	_expect(full.current_hp == 40 and wounded.current_hp == 50 and table._enemy_event_hand.is_empty(), "The AI uses Heal on a wounded ally and skips full-health cards")
	_reset(table)
	card = _spawn(table, "player", 0, _data(2, 20))
	_spawn(table, "enemy", 0, _data())
	card.take_damage(10)
	table._piss_hidden_turns["player"] = 2
	table._refresh_piss_visibility()
	event = _give(table, "player", "heal_event")
	_expect(table._try_play_event("player", event["uid"], 0) and card.current_hp == 20 and card.defense_label.text.is_empty() and card._stat_puddles.visible, "Heal restores real health while Piss puddles still conceal the values")
	_expect(table._damage_numbers.is_empty(), "Heal does not expose a floating value during Piss")
	_reset(table)
	card = _spawn(table, "player", 0, _data())
	_spawn(table, "enemy", 0, _data())
	card.take_damage(10)
	event = _give(table, "player", "heal_event")
	_expect(not table._try_play_event("player", event["uid"], 0) and card.is_dead(), "Heal cannot resurrect a dead card")


func _check_draw_rules(table: GameTable) -> void:
	_reset(table)
	_expect(table._event_deck.size() == EventDeck.DECK_SIZE, "The third shared pile contains 31 shuffled events")
	_expect(table._player_event_hand.is_empty() and table._enemy_event_hand.is_empty(), "Building the shared pile alone does not deal the separate opening hands")
	_spawn(table, "player", 0, _data())
	_spawn(table, "enemy", 0, _data())
	_expect(table._event_deck.size() == EventDeck.DECK_SIZE and table._player_event_hand.is_empty(), "Ordinary combat-card draws never grant event cards")
	table._draw_event_card("player")
	table._draw_event_card("enemy")
	_expect(table._player_event_hand.size() == 1 and table._enemy_event_hand.size() == 1 and table._event_deck.size() == EventDeck.DECK_SIZE - 2, "Both players draw into separate hands from the same pile")
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
	_expect(table._event_switch_cards.size() == 2 and not table._can_local_event_or_attack(), "A real Switch click launches two face-down cards while attacks wait for the reveal")
	var flying := table._event_switch_cards.duplicate()
	var near := table._get_stack_top_position("player")
	var far := table._get_stack_top_position("enemy")
	await get_tree().create_timer(0.3).timeout
	_expect(flying[0].global_position.distance_to(near) > 0.5 and flying[1].global_position.distance_to(far) > 0.5, "Both Switch cards visibly travel away from their source piles")
	_expect(flying[0].global_position.distance_to(flying[1].global_position) > 0.8, "Switch uses separate flight lanes so both exchanged cards stay visible")
	table._rebuild_stack_visual("player")
	table._rebuild_stack_visual("enemy")
	_expect(not table._player_stack_visuals[0].visible and not table._enemy_stack_visuals[0].visible, "Rebuilding piles during Switch keeps their in-flight top cards hidden")
	await get_tree().create_timer(0.6).timeout
	_expect(table._event_switch_cards.is_empty() and table._player_stack_visuals[0].visible and table._enemy_stack_visuals[0].visible, "The fast exchange restores both complete piles and removes flying cards")
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


func _check_stacked_hand(table: GameTable) -> void:
	_reset(table)
	_spawn(table, "player", 0, _data())
	_spawn(table, "enemy", 0, _data())
	table._player_deck.append(_data())
	table._enemy_deck.append(_data())
	var first_switch := _give(table, "player", "switch")
	_give(table, "player", "block")
	var strength := _give(table, "player", "strength_120")
	var second_switch := _give(table, "player", "switch")
	_give(table, "player", "strength_150")
	var second_block := _give(table, "player", "block")
	_give(table, "player", "strength_200")
	var third_switch := _give(table, "player", "switch")
	var original_hand := table._player_event_hand.duplicate(true)
	table._refresh_event_hand()
	var hand_ui: Variant = table._event_hand_ui
	_expect(hand_ui._cards.size() == 5 and table._player_event_hand == original_hand, "Interleaved identical events share five visual stacks without changing the eight physical cards")
	var switch_stack: Variant = hand_ui._cards[0]
	_expect(switch_stack.instances.size() == 3 and switch_stack.uid == first_switch["uid"], "The Switch stack contains all three copies and exposes one actual UID")
	_expect(hand_ui._cards[2].data["id"] == "strength_120" and hand_ui._cards[3].data["id"] == "strength_150" and hand_ui._cards[4].data["id"] == "strength_200", "All three strength multipliers remain separate stacks in first-occurrence order")
	table._on_event_selected(str(second_block["uid"]))
	table._refresh_event_hand()
	_expect(hand_ui._cards[1].uid == second_block["uid"] and hand_ui._cards[1]._selected, "Selecting a non-front copy keeps its exact UID and highlights the shared stack")
	_click_event_hand_card(table, str(second_block["uid"]))
	table._refresh_event_hand()
	_expect(table._selected_event_uid.is_empty() and not hand_ui._cards[1]._selected, "Clicking the selected stack cancels targeting without spending either copy")
	# Even a future variant reusing an ID must not merge a different effect.
	var variant_hand := original_hand.duplicate(true)
	var modified := strength.duplicate(true)
	modified["uid"] = "different-strength-copy"
	modified["multiplier"] = 1.3
	variant_hand.append(modified)
	hand_ui.configure(variant_hand, true)
	_expect(hand_ui._cards.size() == 6, "Matching names and IDs do not stack events whose effect data differs")
	table._refresh_event_hand()
	_click_event_hand_card(table, str(first_switch["uid"]))
	table._refresh_event_hand()
	_expect(table._player_event_hand.size() == 7 and table._event_discard.size() == 1 and table._event_discard[0]["uid"] == first_switch["uid"], "Clicking a three-card stack plays and discards exactly one physical event")
	_expect(hand_ui._cards.size() == 5 and hand_ui._cards[0].instances.size() == 2 and hand_ui._cards[0].uid == second_switch["uid"], "The remaining Switch copies stay stacked with an updated count and playable UID")
	_expect(table._event_from_hand("player", str(third_switch["uid"])) == third_switch, "The third physical copy remains available in the authoritative hand")
	_click_event_hand_card(table, str(second_switch["uid"]))
	_expect(table._player_event_hand.size() == 7 and table._event_discard.size() == 1, "A stack cannot bypass the one-event-per-turn rule")
	await get_tree().create_timer(0.9).timeout
	table._event_played_this_turn = false
	table._refresh_event_hand()
	table._on_event_selected(str(second_block["uid"]))
	_expect(table._try_play_event("player", str(second_block["uid"]), 0), "A targeted event can play the exact selected copy from a stack")
	table._refresh_event_hand()
	_expect(hand_ui._cards[1].instances.size() == 1 and table._event_from_hand("player", str(second_block["uid"])).is_empty(), "Playing one targeted copy leaves the other as a single card")
	await get_tree().create_timer(0.9).timeout


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
		var attacker := _spawn(table, "player", 0, _data(20, 30))
		var effects: Array = [{"type":"draw_on_death"}] if has_draw_effect else []
		var target := _spawn(table, "enemy", 0, _data(1, 1, effects))
		_spawn(table, "enemy", 1, _data(1, 30))
		table._player_deck.append(_data())
		table._enemy_deck.append(_data())
		await table._resolve_duel(attacker, target, "player")
		_expect(table._enemy_event_hand.size() == int(has_draw_effect) and table._player_event_hand.is_empty() and table._event_deck.size() == EventDeck.DECK_SIZE - int(has_draw_effect), "Only the dying card's Draw On Death grants its owner an event")
		_expect(table._player_slots[1] == null and table._player_deck.size() == 1, "Draw On Death never grants an extra combat card")
		_expect(table._current_turn == "enemy", "The attack immediately ends its turn")
	_reset(table)
	var mailman := _spawn(table, "enemy", 0, _data(1, 1, [{"type":"draw_on_death"}]))
	var near_target := _spawn(table, "player", 0, _data(20, 30))
	_spawn(table, "enemy", 1, _data())
	await table._resolve_duel(near_target, mailman, "player")
	_expect(table._enemy_event_hand.size() == 1 and table._player_event_hand.is_empty(), "The opposing deceased fighter earns its own event hand")



func _check_mutual_and_multiple_kills(table: GameTable) -> void:
	_reset(table)
	var attacker := _spawn(table, "player", 0, _data(5, 1, [{"type": "draw_on_death"}]))
	var defender := _spawn(table, "enemy", 0, _data(5, 1, [{"type": "draw_on_death"}]))
	_spawn(table, "player", 1, _data())
	_spawn(table, "enemy", 1, _data())
	await table._resolve_duel(attacker, defender, "player")
	_expect(table._player_event_hand.size() == 1 and table._enemy_event_hand.size() == 1, "Mutual deaths grant each eligible fighter its own death event")
	_expect(table._event_deck.size() == EventDeck.DECK_SIZE - 2, "A mutual kill removes exactly two cards from the shared pile")
	_reset(table)
	attacker = _spawn(table, "player", 0, _data(5, 40, [{"type": "lava"}]))
	for index in range(3):
		_spawn(table, "enemy", index, _data(1, 1, [{"type":"draw_on_death"}]))
	_spawn(table, "enemy", 4, _data(1, 30))
	await table._resolve_duel(attacker, table._enemy_slots[0], "player")
	_expect(table._enemy_event_hand.size() == 3 and table._event_deck.size() == EventDeck.DECK_SIZE - 3, "A simultaneous Lava multi-kill grants exactly one event per deceased effect carrier")
	var awarded: Dictionary = {}
	for event: Dictionary in table._enemy_event_hand:
		awarded[event["uid"]] = true
	_expect(awarded.size() == 3 and table._player_event_hand.is_empty(), "Multi-kill rewards are distinct events in the deceased fighters' hand")


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

