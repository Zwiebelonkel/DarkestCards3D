extends Node3D

var checks := 0
var failures := 0
var table: GameTable
var _identity := 0


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		push_error("Run egg_hatch_test through the isolated match feature runner.")
		get_tree().quit(1)
		return
	CollectionManager.collection = {"cards": {}, "instances": []}
	CollectionManager.save_collection()
	GameCurrency.set_process(false)
	DeckManager.battle_deck.clear()
	DeckManager.deck_instance_ids.clear()
	DeckManager.starting_deck_indices.clear()
	CardUpgradeManager.upgrades.clear()
	CardUpgradeManager.add_attack("chick", 20)
	CardUpgradeManager.add_attack("chicken", 20)
	var save_before := FileAccess.get_file_as_string(CollectionManager.SAVE_PATH)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 10, 8)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	table = (load("res://scenes/table/GameTable.tscn") as PackedScene).instantiate() as GameTable
	table.table_camera = camera
	table.replacement_draw_delay = 0.05
	table.draw_animation_duration = 0.12
	table.enemy_turn_delay = 20.0
	table.blood_burst_scene = null
	table.blood_decal_scene = null
	add_child(table)
	await get_tree().process_frame
	check(CollectionManager.get_amount("chick") == 0 and DeckManager.get_deck_cards().is_empty(), "fixture owns no Chick and has no saved Chick in its deck")
	_check_hatch_probability()
	await _check_protected_eggs()
	for side in ["player", "enemy"]:
		await _check_maturation(side, false)
		await _check_maturation(side, true)
		await _check_death_before_maturation(side)
	for side in ["player", "enemy"]:
		await _check_unowned_hatch(side)
		await _check_last_egg_poison(side)
		await _check_failed_hatch(side, false)
		await _check_failed_hatch(side, true)
	await _check_lava_hatches()
	await _check_mutual_egg_death()
	await _check_thorns_hatch()
	await _check_remote_and_reset()
	check(CollectionManager.get_card_instances().is_empty() and CollectionManager.get_amount("chick") == 0 and DeckManager.get_deck_cards().is_empty(), "hatching never grants persistent collection or saved-deck cards")
	check(FileAccess.get_file_as_string(CollectionManager.SAVE_PATH) == save_before, "all hatch paths leave the saved collection unchanged")
	table._clear_match()
	table.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("EGG_HATCH_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _reset() -> void:
	table._clear_match()
	table._reset_online_sync_tracking()
	table._online_mode = false
	table._online_is_host = false
	table._online_is_spectator = false
	table._table_state = GameTable.TableState.PLAYING
	table._current_turn = "player"
	_seed_hatches(true, 3)


func _seed_hatches(hatches: bool, count: int = 1) -> void:
	var probe := RandomNumberGenerator.new()
	for candidate in range(10000):
		probe.seed = candidate
		var matches := true
		for roll in range(count):
			if (probe.randf() < 0.25) != hatches:
				matches = false
				break
		if matches:
			table._egg_hatch_rng.seed = candidate
			return
	check(false, "deterministic hatch fixture finds a suitable seed")


func _check_hatch_probability() -> void:
	_reset()
	var egg := _spawn("player", 0, _data("eg"))
	var before := table._egg_hatch_rng.state
	check(table._get_death_replacement_data(egg).is_empty() and table._egg_hatch_rng.state == before, "a living Egg consumes no hatch roll")
	egg.take_damage(999)
	table._egg_hatch_rng.seed = 9152026
	var hatched := 0
	for trial in range(10000):
		if not table._get_death_replacement_data(egg).is_empty():
			hatched += 1
	check(GameTable.EGG_HATCH_CHANCE == 0.25 and hatched >= 2350 and hatched <= 2650, "10,000 seeded independent Egg deaths hatch approximately 25 percent (%d)" % hatched)
	var ordinary := _spawn("player", 1, _data("corpse"))
	ordinary.take_damage(999)
	before = table._egg_hatch_rng.state
	check(table._get_death_replacement_data(ordinary).is_empty() and table._egg_hatch_rng.state == before, "non-Egg deaths consume no hatch roll")
	table._online_mode = true
	table._online_is_host = false
	check(table._get_death_replacement_data(egg).is_empty() and table._egg_hatch_rng.state == before, "remote peers cannot roll an Egg hatch even through the replacement helper")
	_reset()


func _check_protected_eggs() -> void:
	_reset()
	for protection in ["last_stand", "grave_return"]:
		var egg := _spawn("player", 0, _data("eg", 0, 10, [{"type": protection}]))
		var before := table._egg_hatch_rng.state
		egg.set_meta("poison_turns", 1)
		egg.set_meta("poison_damage", 999)
		await table._apply_start_turn_effects("player")
		check(table._player_slots[0] == egg and not egg.is_dead() and table._get_death_replacement_data(egg).is_empty() and table._egg_hatch_rng.state == before, protection + " prevents real lethal poison before any Egg hatch roll")
		_reset()


func _check_failed_hatch(side: String, empty_deck: bool) -> void:
	_reset()
	_seed_hatches(false)
	var opponent := "enemy" if side == "player" else "player"
	_spawn(opponent, 1, _data("corpse", 0, 30))
	var egg := _spawn(side, 2, _data("eg"))
	var reserve := _data("bat")
	if not empty_deck:
		_deck(side).append(reserve)
	egg.take_damage(999)
	table._remove_dead_card(egg, false)
	var rolled_state := table._egg_hatch_rng.state
	table._remove_dead_card(egg, false)
	check(table._egg_hatch_rng.state == rolled_state, side + " a duplicate failed-hatch death cannot reroll")
	await _wait_until(func(): return not table._has_pending_card_replacements())
	if empty_deck:
		check(_slots(side)[2] == null and _deck(side).is_empty() and table._check_game_over(), side + " the last Egg can fail to hatch and ends the match when its draw pile is empty")
	else:
		check(is_instance_valid(_slots(side)[2]) and str(_slots(side)[2].card_data.get("instance_id")) == reserve["instance_id"] and _deck(side).is_empty(), side + " a failed hatch draws the normal next card exactly once")


func _data(card_id: String, attack: int = -1, health: int = -1, effects: Array = []) -> Dictionary:
	_identity += 1
	var data := CardDatabase.get_card(card_id).duplicate(true)
	data["instance_id"] = "egg-test-%d" % _identity
	data["card_id"] = card_id
	data["level"] = 1
	data["is_holo"] = false
	if attack >= 0:
		data["attack"] = attack
	if health >= 0:
		data["defense"] = health
	if not effects.is_empty():
		data["effects"] = effects.duplicate(true)
		data["active_effects"] = effects.duplicate(true)
	return data


func _slots(side: String) -> Array[Card3D]:
	return table._player_slots if side == "player" else table._enemy_slots


func _deck(side: String) -> Array[Dictionary]:
	return table._player_deck if side == "player" else table._enemy_deck


func _spawn(side: String, slot: int, data: Dictionary) -> Card3D:
	_deck(side).append(data)
	table._draw_to_slot(side, slot, false)
	var card := _slots(side)[slot]
	card.attack_out_duration = 0.03
	card.attack_hit_duration = 0.02
	card.attack_return_duration = 0.03
	return card


func _wait_until(predicate: Callable, timeout_msec: int = 4000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())


func _is_chick(card: Card3D) -> bool:
	return is_instance_valid(card) and str(card.card_data.get("id")) == "chick" and not card.is_dead()


func _is_chicken(card: Card3D) -> bool:
	return is_instance_valid(card) and str(card.card_data.get("id")) == "chicken" and not card.is_dead()


func _check_maturation(side: String, hatched: bool) -> void:
	_reset()
	var source := "hatched" if hatched else "drawn"
	var label := side + " " + source + " Chick"
	var opponent := "enemy" if side == "player" else "player"
	_spawn(opponent, 0, _data("corpse", 0, 30))
	# The current turn already started before this card arrives; that partial
	# turn must not count toward five complete rounds on the board.
	table._prepare_chick_turn()
	if hatched:
		var egg := _spawn(side, 2, _data("eg"))
		egg.take_damage(999)
		table._remove_dead_card(egg, false)
		check(await _wait_until(func(): return _is_chick(_slots(side)[2]) and not table._has_pending_card_replacements()), label + " enters its original slot after Egg dies")
	else:
		_spawn(side, 2, _data("chick", 8, 30))
	var chick := _slots(side)[2]
	check(_is_chick(chick), label + " begins as a living Chick")
	if not _is_chick(chick):
		return
	await table._advance_chick_growth()
	check(_slots(side)[2] == chick and int(chick.get_network_state().get("chick_survived_turns", -1)) == 0, label + " does not count the partial arrival turn")
	for completed_turn in range(1, 10):
		table._prepare_chick_turn()
		await table._advance_chick_growth()
		check(_slots(side)[2] == chick and _is_chick(chick) and int(chick.get_meta("chick_survived_turns", -1)) == completed_turn, label + " remains Chick after completed turn %d of ten" % completed_turn)
		await table._advance_chick_growth()
		check(int(chick.get_meta("chick_survived_turns", -1)) == completed_turn, label + " cannot age twice for completed turn %d" % completed_turn)
	# Poison, damage, combat buffs, finish and level belong to the young
	# instance. Its replacement must start fresh, using the catalog Chicken.
	chick.attack_value = 99
	chick.max_hp = 40
	chick.current_hp = 4
	chick.card_data["level"] = 8
	chick.card_data["is_holo"] = true
	chick.card_data["effects"] = [{"type": "armor"}]
	chick.card_data["active_effects"] = [{"type": "armor"}]
	chick.set_meta("poison_turns", 2)
	chick.set_meta("poison_damage", 1)
	chick._skip_next_attack = true
	chick.apply_event_block(3)
	var prior_identity := str(chick.card_data.get("instance_id", ""))
	var died_signals: Array = []
	chick.died.connect(func(dead: Card3D): died_signals.append(dead))
	_deck(side).append(_data("bat"))
	table._rebuild_stack_visual(side)
	var deck_before := _deck(side).duplicate(true)
	var pile_count := (table._player_stack_visuals if side == "player" else table._enemy_stack_visuals).size()
	var death_count := table._card_death_sequence
	var event_state := {"player": table._player_event_hand.duplicate(true), "enemy": table._enemy_event_hand.duplicate(true), "deck": table._event_deck.duplicate(true), "discard": table._event_discard.duplicate(true)}
	var persistent_before := _persistent_state()
	var files_before := _save_bytes()
	table._prepare_chick_turn()
	# Use the real turn transition for the tenth completion. Returning to the
	# player's turn avoids waiting for a synthetic enemy AI action in this test.
	table._current_turn = "enemy"
	await table._end_turn_to("player")
	var chicken := _slots(side)[2]
	check(_is_chicken(chicken) and chicken != chick and table._current_turn == "player", label + " evolves exactly at five full rounds through the real turn transition")
	if not _is_chicken(chicken):
		return
	check(chicken.global_position.is_equal_approx(table._get_slot_marker(side, 2).global_position) and chicken.scale.is_equal_approx(Vector3.ONE), label + " becomes Chicken in the same physical slot with its completed growth animation")
	check(chicken.attack_value == 3 and chicken.max_hp == 10 and chicken.current_hp == 10 and CardData.has_effect(chicken.card_data, "last_stand") and chicken._last_stand_available and not CardData.has_effect(chicken.card_data, "armor") and not CardData.has_effect(chicken.card_data, "swarm_power"), label + " becomes a fresh base 3/10 Chicken with ready Last Stand and no inherited buffs or upgrades")
	check(int(chicken.card_data.get("level", 0)) == 1 and not CardData.is_holo(chicken.card_data) and not chicken.has_meta("poison_turns") and not chicken.has_meta("poison_damage") and not chicken.has_meta("chick_survived_turns") and not chicken._skip_next_attack and chicken.event_block_turns == 0, label + " clears level, Holo, poison, growth age, stun and event block on evolution")
	check(not str(chicken.card_data.get("instance_id", "")).is_empty() and str(chicken.card_data.get("instance_id", "")) != prior_identity, label + " receives a new battle-only Chicken identity")
	check(_deck(side) == deck_before and (table._player_stack_visuals if side == "player" else table._enemy_stack_visuals).size() == pile_count, label + " evolves without consuming, reordering or animating a deck draw")
	check(died_signals.is_empty() and table._card_death_sequence == death_count and not table._has_pending_card_replacements(), label + " evolution produces no death signal, death job or replacement barrier")
	check({"player": table._player_event_hand, "enemy": table._enemy_event_hand, "deck": table._event_deck, "discard": table._event_discard} == event_state, label + " evolution grants no kill-event reward and changes no event pile")
	check(_persistent_state() == persistent_before and _save_bytes() == files_before, label + " evolution preserves collection, saved deck, upgrades, wallet and every profile file")


func _check_death_before_maturation(side: String) -> void:
	_reset()
	var chick := _spawn(side, 2, _data("chick"))
	for completed_turn in range(9):
		table._prepare_chick_turn()
		await table._advance_chick_growth()
	table._prepare_chick_turn()
	chick.take_damage(999)
	await table._advance_chick_growth()
	check(_slots(side)[2] == chick and chick.is_dead() and int(chick.get_meta("chick_survived_turns", -1)) == 9, side + " Chick killed before its tenth completion never evolves or resurrects")
	var pending := _data("corpse")
	_deck(side).append(pending)
	table._remove_dead_card(chick, false)
	await _wait_until(func(): return not table._has_pending_card_replacements())
	check(is_instance_valid(_slots(side)[2]) and str(_slots(side)[2].card_data.get("instance_id", "")) == str(pending["instance_id"]) and _deck(side).is_empty(), side + " young Chick death draws the normal next card exactly once")
	table._prepare_chick_turn()
	await table._advance_chick_growth()
	check(not _is_chicken(_slots(side)[2]), side + " a replacement never inherits the dead Chick's pending maturation")


func _persistent_state() -> Dictionary:
	return {"collection": CollectionManager.collection.duplicate(true), "upgrades": CardUpgradeManager.upgrades.duplicate(true), "deck": DeckManager.battle_deck.duplicate(), "ids": DeckManager.deck_instance_ids.duplicate(), "starting": DeckManager.starting_deck_indices.duplicate(), "coins": GameCurrency.get_coin_cents(), "level": GameCurrency.level, "xp": GameCurrency.xp}


func _save_bytes() -> Dictionary:
	var result := {}
	var paths: Array[String] = [SaveSlots.REGISTRY_PATH, SettingsManager.CONFIG_PATH]
	for slot in range(1, 4):
		for file_name: String in SaveSlots.PROFILE_FILES:
			paths.append(SaveSlots.get_slot_directory(slot).path_join(file_name))
	for path in paths:
		result[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	return result


func _check_unowned_hatch(side: String) -> void:
	_reset()
	var pending_one := _data("corpse")
	var pending_two := _data("bat")
	_deck(side).append_array([pending_one, pending_two])
	var egg_data := _data("eg")
	egg_data["level"] = 8
	egg_data["is_holo"] = true
	var egg := _spawn(side, 2, egg_data)
	egg.set_meta("poison_turns", 2)
	egg.set_meta("poison_damage", 50)
	table._rebuild_stack_visual(side)
	var pile_count := (table._player_stack_visuals if side == "player" else table._enemy_stack_visuals).size()
	var pending_before := _deck(side).duplicate(true)
	check(egg.take_damage(999), side + " Egg takes actual lethal damage")
	table._remove_dead_card(egg, false)
	var rolled_state := table._egg_hatch_rng.state
	table._remove_dead_card(egg, false)
	check(table._egg_hatch_rng.state == rolled_state, side + " duplicate successful-hatch death cannot reroll")
	check(_slots(side)[2] == null and table._pending_card_deaths.size() == 1, side + " duplicate removal clears only one slot and schedules one replacement")
	check(await _wait_until(func(): return is_instance_valid(_slots(side)[2])), side + " Egg produces a replacement without owning Chick")
	var chick := _slots(side)[2]
	check(_is_chick(chick) and chick != egg, side + " replacement is a newly created Chick")
	if not _is_chick(chick):
		return
	check(chick.global_position.is_equal_approx(table._get_slot_marker(side, 2).global_position), side + " Chick appears directly in the original slot")
	check(_deck(side) == pending_before and (table._player_stack_visuals if side == "player" else table._enemy_stack_visuals).size() == pile_count, side + " hatching preserves draw order, deck count and the visible pile")
	var chick_id := str(chick.card_data.get("instance_id", ""))
	check(not chick_id.is_empty() and chick_id != str(egg_data["instance_id"]) and not chick_id.begins_with("egg-test-"), side + " Chick receives a fresh battle-only identity")
	check(chick.attack_value == 1 and chick.max_hp == 6 and chick.current_hp == 6 and CardData.has_effect(chick.card_data, "swarm_power") and not CardData.has_effect(chick.card_data, "last_stand"), side + " Chick uses its real catalog stats and Swarm without collection upgrades or premature Last Stand")
	check(int(chick.card_data.get("level")) == 1 and not CardData.is_holo(chick.card_data) and not chick.has_meta("poison_turns"), side + " Chick does not inherit Egg level, Holo finish or poison")
	check(await _wait_until(func(): return not table._has_pending_card_replacements()), side + " in-slot hatch animation releases the replacement barrier")
	check(chick.scale.is_equal_approx(Vector3.ONE) and not chick.area.input_event.get_connections().is_empty(), side + " fully hatched Chick has normal scale and battle input")
	chick.take_damage(999)
	table._remove_dead_card(chick, false)
	await _wait_until(func(): return not table._has_pending_card_replacements())
	var ordinary := _slots(side)[2]
	check(is_instance_valid(ordinary) and str(ordinary.card_data.get("instance_id")) == str(pending_two["instance_id"]) and _deck(side).size() == 1, side + " an actually dead Chick draws the next ordinary deck card exactly once")


func _check_last_egg_poison(side: String) -> void:
	_reset()
	var opponent := "enemy" if side == "player" else "player"
	var egg := _spawn(side, 4, _data("eg"))
	_spawn(opponent, 1, _data("corpse", 0, 30))
	egg.set_meta("poison_turns", 1)
	egg.set_meta("poison_damage", 999)
	await table._apply_start_turn_effects(side)
	var chick := _slots(side)[4]
	check(_is_chick(chick) and _deck(side).is_empty() and not table._check_game_over(), side + " poisoned final Egg hatches with an empty deck and prevents premature game over")
	if not _is_chick(chick):
		return
	chick.set_meta("poison_turns", 1)
	chick.set_meta("poison_damage", 999)
	await table._apply_start_turn_effects(side)
	check(_slots(side)[4] == null and table._check_game_over(), side + " losing the last Chick with an empty deck ends the match normally")
	check(table._last_match_outcome == (GameTable.MatchOutcome.LOSS if side == "player" else GameTable.MatchOutcome.WIN), side + " final Chick death preserves the correct win/loss result")


func _check_lava_hatches() -> void:
	_reset()
	var eggs: Array[Card3D] = []
	for slot in [0, 2, 4]:
		eggs.append(_spawn("player", slot, _data("eg", 0, 1)))
	var attacker := _spawn("enemy", 2, _data("corpse", 4, 30, [{"type": "lava"}]))
	table._player_deck.append(_data("bat"))
	var deck_before := table._player_deck.duplicate(true)
	await table._resolve_duel(attacker, eggs[1], "enemy")
	var identities := {}
	for slot in [0, 2, 4]:
		var chick := table._player_slots[slot]
		check(_is_chick(chick) and chick.global_position.is_equal_approx(table._player_slot_markers[slot].global_position), "simultaneous lava death hatches Egg in slot %d" % slot)
		if _is_chick(chick):
			identities[str(chick.card_data.get("instance_id", ""))] = true
	check(identities.size() == 3 and not identities.has(""), "simultaneously hatched Chicks have distinct new identities")
	check(table._player_deck == deck_before and not table._game_over, "multiple simultaneous Egg deaths consume no ordinary replacements or end the match")


func _check_mutual_egg_death() -> void:
	_reset()
	var attacker := _spawn("enemy", 3, _data("eg", 5, 1))
	var defender := _spawn("player", 1, _data("eg", 5, 1))
	await table._resolve_duel(attacker, defender, "enemy")
	var both_hatched := _is_chick(table._enemy_slots[3]) and _is_chick(table._player_slots[1])
	check(both_hatched, "lethal attack and lethal counter each hatch their Egg on its own side")
	check(both_hatched and not table._game_over and table._enemy_slots[3].current_hp == 6 and table._player_slots[1].current_hp == 6, "mutual final-Egg deaths continue with two undamaged Chicks")


func _check_thorns_hatch() -> void:
	_reset()
	var attacker := _spawn("enemy", 0, _data("eg", 4, 1))
	var defender := _spawn("player", 0, _data("corpse", 0, 20, [{"type": "thorns", "percent": 1.0}]))
	await table._resolve_duel(attacker, defender, "enemy")
	check(_is_chick(table._enemy_slots[0]) and defender.current_hp == 16, "thorns kills an attacking Egg and hatches Chick after its completed hit")


func _check_remote_and_reset() -> void:
	_reset()
	var remote_egg := _spawn("enemy", 2, _data("eg"))
	table._enemy_deck.append(_data("corpse"))
	remote_egg.take_damage(999)
	table._remove_dead_card(remote_egg, false, Vector3(INF, INF, INF), false)
	await _wait_until(func(): return not table._has_pending_card_replacements())
	check(table._enemy_slots[2] == null and table._enemy_deck.size() == 1, "remote death presentation waits for the authoritative Chick snapshot")
	_reset()
	var egg := _spawn("player", 0, _data("eg"))
	egg.take_damage(999)
	table._remove_dead_card(egg, false)
	_reset()
	var new_match_card := _spawn("player", 0, _data("corpse"))
	await get_tree().create_timer(0.3).timeout
	check(table._player_slots[0] == new_match_card and table._pending_card_deaths.is_empty(), "reset cancels pending Egg hatches without overwriting a new match's slot")
