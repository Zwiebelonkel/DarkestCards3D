extends Node3D

var checks := 0
var failures := 0
var _identity := 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func _run() -> void:
	var eimer := CardDatabase.get_card("piss")
	_check(not eimer.is_empty(), "Pisse-Eimer is available from the real card catalog")
	if eimer.is_empty():
		_finish()
		return
	_check(int(eimer.get("attack", 0)) == 1 and int(eimer.get("defense", 0)) == 5, "Pisse-Eimer has one attack and five health")
	_check(str(eimer.get("rarity", "")) == "epic" and CardData.is_combat_card(eimer), "Pisse-Eimer is an epic battle card")
	_check(CardData.has_effect(eimer, "lava"), "Pisse-Eimer's active effect is lava")
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	main.visible = false
	main.set_process(false)
	main.set_physics_process(false)
	for canvas in main.find_children("*", "CanvasLayer", true, false):
		canvas.visible = false
	var table := main.get_node("ScenePivot/GameTable") as GameTable
	table.enemy_turn_delay = 20.0
	table.draw_animation_duration = 0.02
	table.replacement_draw_delay = 0.02
	table.blood_burst_scene = null
	table.blood_decal_scene = null
	for side in ["player", "enemy"]:
		await _check_full_board(table, side)
	await _check_defenses(table)
	await _check_multiple_deaths(table)
	await _check_replacement_immunity(table)
	await _check_retarget_after_main_death(table)
	await _check_lethal_counter(table)
	await _check_cleave_interaction(table)
	await _check_ordinary_duel(table)
	await _check_single_target(table)
	for spectator in [false, true]:
		_check_remote_presentation(table, spectator)
		await _check_remote_attack_animation(table, spectator)
	_check_remote_invalid_targets(table)
	await _check_remote_deaths(table)
	await _check_remote_exit(table)
	table._clear_match()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_finish()


func _finish() -> void:
	print("LAVA_EFFECT_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _data(attack: int = 2, health: int = 10, effects: Array = []) -> Dictionary:
	_identity += 1
	var data: Dictionary = CardDatabase.get_all_cards()[0].duplicate(true)
	data["instance_id"] = "lava-test-%d" % _identity
	data["attack"] = attack
	data["defense"] = health
	data["animated"] = false
	data["effects"] = effects.duplicate(true)
	data["active_effects"] = effects.duplicate(true)
	return data


func _reset(table: GameTable) -> void:
	table._clear_match()
	table._reset_online_sync_tracking()
	table._online_mode = false
	table._online_is_host = false
	table._online_is_spectator = false
	table._table_state = GameTable.TableState.PLAYING


func _spawn(table: GameTable, side: String, slot: int, data: Dictionary) -> Card3D:
	var deck: Array[Dictionary] = table._player_deck if side == "player" else table._enemy_deck
	deck.append(data)
	table._draw_to_slot(side, slot, false)
	var slots: Array[Card3D] = table._player_slots if side == "player" else table._enemy_slots
	return slots[slot]


func _eimer(table: GameTable, side: String, effects: Array = [], attack: int = 1, health: int = 5) -> Card3D:
	var data := CardDatabase.get_card("piss").duplicate(true)
	_identity += 1
	data["instance_id"] = "eimer-test-%d" % _identity
	data["attack"] = attack
	data["defense"] = health
	var active_effects: Array = [{"type": "lava"}]
	active_effects.append_array(effects)
	data["effects"] = active_effects
	data["active_effects"] = active_effects
	return _spawn(table, side, 2, data)


func _targets(table: GameTable, side: String, health: int = 10) -> Array[Card3D]:
	var cards: Array[Card3D] = []
	for index in range(GameTable.HAND_SIZE):
		cards.append(_spawn(table, side, index, _data(2, health)))
	return cards


func _watch_impacts(attacker: Card3D, targets: Array[Card3D]) -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	attacker.attack_impact.connect(func():
		_record_impact.call_deferred(attacker, targets, snapshots, Engine.get_process_frames())
	)
	return snapshots


func _record_impact(attacker: Card3D, targets: Array[Card3D], snapshots: Array[Dictionary], impact_frame: int) -> void:
	var health: Array[int] = []
	for target in targets:
		health.append(target.current_hp if is_instance_valid(target) else -1)
	snapshots.append({
		"target_hp": health,
		"attacker_hp": attacker.current_hp if is_instance_valid(attacker) else -1,
		"same_frame": impact_frame == Engine.get_process_frames(),
	})


func _check_full_board(table: GameTable, side: String) -> void:
	_reset(table)
	var opponent := "enemy" if side == "player" else "player"
	var attacker := _eimer(table, side)
	var ally := _spawn(table, side, 0, _data(4, 20))
	var targets := _targets(table, opponent)
	var impacts := _watch_impacts(attacker, targets)
	await table._resolve_duel(attacker, targets[2], side)
	_check(impacts.size() == 1, side + " lava uses one attack contact for the whole board")
	if impacts.size() == 1:
		_check(bool(impacts[0]["same_frame"]) and impacts[0]["target_hp"] == [9, 9, 9, 9, 9], side + " lava damages all five opponents in the same impact frame")
	_check(attacker.current_hp == 3, side + " lava receives only the selected defender's counterattack")
	_check(ally.current_hp == 20, side + " lava never damages an allied card")
	_check(targets[0].current_hp == 9 and targets[4].current_hp == 9, side + " lava reaches both distant slots")
	_check(targets.all(func(card: Card3D): return card.get_blood_intensity() > 0.0), side + " all damaged enemy cards receive the hit surface effect")


func _check_defenses(table: GameTable) -> void:
	_reset(table)
	var attacker := _eimer(table, "enemy", [], 4, 20)
	var targets: Array[Card3D] = [
		_spawn(table, "player", 0, _data(2, 8, [{"type": "shield_first_hit"}])),
		_spawn(table, "player", 1, _data(2, 8, [{"type": "armor", "value": 0.5}])),
		_spawn(table, "player", 2, _data(2, 8)),
		_spawn(table, "player", 3, _data(2, 8, [{"type": "thorns", "percent": 0.5}])),
		_spawn(table, "player", 4, _data(2, 1, [{"type": "last_stand"}])),
	]
	var impacts := _watch_impacts(attacker, targets)
	await table._resolve_duel(attacker, targets[2], "enemy")
	_check(impacts.size() == 1 and impacts[0]["target_hp"] == [8, 6, 4, 4, 1], "lava respects each target's shield, armor, and last stand at the same contact")
	_check(not bool(targets[0].get_network_state()["first_hit_shield_available"]), "lava consumes only the shield that blocked its target's hit")
	_check(targets[0].get_blood_intensity() == 0.0 and targets[1].get_blood_intensity() > 0.0, "blocked lava stays clean while reduced armor damage stains the target")
	_check(not bool(targets[4].get_network_state()["last_stand_available"]) and table._player_slots[4] == targets[4], "last stand keeps its target in the slot and is consumed once")
	_check(attacker.current_hp == 16, "a secondary target's thorns and the primary counter each resolve once")


func _check_multiple_deaths(table: GameTable) -> void:
	_reset(table)
	var attacker := _eimer(table, "enemy")
	var targets := _targets(table, "player", 1)
	for index in range(3):
		table._player_deck.append(_data(2, 10))
	var impacts := _watch_impacts(attacker, targets)
	await table._resolve_duel(attacker, targets[2], "enemy")
	_check(impacts.size() == 1 and impacts[0]["target_hp"] == [0, 0, 0, 0, 0], "all lethal lava targets reach zero in one impact")
	_check(attacker.current_hp == 3, "a lethal selected defender still retaliates once")
	var survivors: Array[Card3D] = []
	for card in table._player_slots:
		if is_instance_valid(card):
			survivors.append(card)
	_check(survivors.size() == 3 and table._player_deck.is_empty(), "five simultaneous deaths draw exactly the three available replacements")
	_check(survivors.all(func(card: Card3D): return card.current_hp == 10 and not targets.has(card)), "replacement cards enter alive and receive no damage from the completed lava hit")
	_check(not table._has_pending_card_replacements(), "lava awaits all replacement draws before finishing the duel")


func _check_replacement_immunity(table: GameTable) -> void:
	_reset(table)
	var attacker := _eimer(table, "enemy", [{"type": "double_strike"}])
	var targets := _targets(table, "player", 1)
	targets[2].current_hp = 10
	targets[2].max_hp = 10
	for index in range(4):
		table._player_deck.append(_data(2, 10))
	var impacts := _watch_impacts(attacker, targets)
	await table._resolve_duel(attacker, targets[2], "enemy")
	_check(impacts.size() == 2 and targets[2].current_hp == 8, "double strike repeats lava against surviving original targets")
	_check(attacker.current_hp == 3, "double lava receives one primary counter for the entire duel")
	var replacements_unhurt := true
	for index in [0, 1, 3, 4]:
		var card := table._player_slots[index]
		replacements_unhurt = replacements_unhurt and is_instance_valid(card) and card != targets[index] and card.current_hp == 10
	_check(replacements_unhurt and table._player_deck.is_empty(), "a second lava strike excludes replacements drawn after its first impact")


func _check_cleave_interaction(table: GameTable) -> void:
	_reset(table)
	var attacker := _eimer(table, "enemy", [{"type": "cleave"}], 2, 10)
	var targets := _targets(table, "player")
	await table._resolve_duel(attacker, targets[2], "enemy")
	_check(targets.all(func(card: Card3D): return card.current_hp == 8), "lava plus cleave does not damage adjacent cards twice")


func _check_retarget_after_main_death(table: GameTable) -> void:
	_reset(table)
	var attacker := _eimer(table, "enemy", [{"type": "double_strike"}])
	var targets := _targets(table, "player")
	targets[2].current_hp = 1
	table._player_deck.append(_data(2, 10))
	var impacts := _watch_impacts(attacker, targets)
	await table._resolve_duel(attacker, targets[2], "enemy")
	_check(impacts.size() == 2 and targets[0].current_hp == 8 and targets[4].current_hp == 8, "a second lava strike reaches surviving original cards after the main defender dies")
	_check(attacker.current_hp == 3, "retargeting a later lava animation never adds a second counterattack")
	_check(is_instance_valid(table._player_slots[2]) and table._player_slots[2] != targets[2] and table._player_slots[2].current_hp == 10, "retargeted lava still excludes the dead main defender's replacement")


func _check_lethal_counter(table: GameTable) -> void:
	_reset(table)
	var attacker := _eimer(table, "enemy")
	_spawn(table, "enemy", 0, _data(2, 10))
	var targets := _targets(table, "player")
	targets[2].attack_value = 99
	var impacts := _watch_impacts(attacker, targets)
	await table._resolve_duel(attacker, targets[2], "enemy")
	_check(impacts.size() == 1 and impacts[0]["target_hp"] == [9, 9, 9, 9, 9] and int(impacts[0]["attacker_hp"]) == 0, "a lethal counter cannot cancel simultaneous lava damage on the other opponents")
	_check(table._enemy_slots[2] == null and is_instance_valid(table._enemy_slots[0]), "a counter-killed lava attacker leaves its slot without removing an ally")


func _check_ordinary_duel(table: GameTable) -> void:
	_reset(table)
	var attacker := _spawn(table, "enemy", 2, _data(2, 10))
	var targets := _targets(table, "player")
	var impacts := _watch_impacts(attacker, targets)
	await table._resolve_duel(attacker, targets[2], "enemy")
	_check(impacts.size() == 1 and impacts[0]["target_hp"] == [10, 10, 8, 10, 10], "an ordinary attack still hits only its selected defender")
	_check(attacker.current_hp == 8, "an ordinary duel preserves its normal counterattack")


func _check_single_target(table: GameTable) -> void:
	_reset(table)
	var attacker := _eimer(table, "enemy")
	var target := _spawn(table, "player", 4, _data(2, 10))
	await table._resolve_duel(attacker, target, "enemy")
	_check(target.current_hp == 9 and attacker.current_hp == 3, "lava handles a single remaining opponent and empty neighboring slots")


func _remote_board(table: GameTable, spectator: bool = false) -> Dictionary:
	_reset(table)
	NetworkManager.current_lobby_id = 123
	NetworkManager._match_in_progress = true
	NetworkManager._participants = {1: {"role": "player"}, 2: {"role": "player"}}
	NetworkManager._connected_peer_ids.assign([1])
	table._online_mode = true
	table._online_is_spectator = spectator
	table._online_turn_sequence = 1
	var attacker_side := "player" if spectator else "enemy"
	var defender_side := "enemy" if spectator else "player"
	var attacker := _eimer(table, attacker_side)
	var ally := _spawn(table, attacker_side, 0, _data(4, 20))
	var targets := _targets(table, defender_side)
	for card in targets:
		card.set_process(false)
		card.blood_fade_duration = 1.0
	var attacker_state := attacker.get_network_state()
	attacker_state["current_hp"] = 3
	var defender_state := targets[2].get_network_state()
	defender_state["current_hp"] = 9
	var lava_hits: Array[Dictionary] = []
	for index in [0, 1, 3, 4]:
		var state := targets[index].get_network_state()
		state["current_hp"] = 9
		lava_hits.append({
			"side": "enemy", "slot": index, "state": state,
			"damage": 1, "died": false, "damage_intensity": 0.5,
		})
	var impact := {
		"turn_sequence": 1, "attack_sequence": 1,
		"attacker_side": "player", "attacker_slot": 2,
		"defender_side": "enemy", "defender_slot": 2,
		"attacker_state": attacker_state, "defender_state": defender_state,
		"attacker_damage": 2, "defender_damage": 1,
		"damage_intensity": 0.5, "lava_hits": lava_hits,
	}
	# This is the exact context captured by the real attack-animation RPC.
	# Exercise its shared contact presenter without requiring Steam transport.
	table._online_client_attack_contexts[1] = {
		"attacker": attacker, "defender": targets[2],
		"canonical_attacker_side": "player", "attacker_slot": 2,
		"canonical_defender_side": "enemy", "defender_slot": 2,
		"lava_targets": targets.duplicate(),
	}
	table._online_client_attack_phases[1] = 1
	table._online_queued_impact_events[1] = impact
	return {"attacker": attacker, "ally": ally, "targets": targets, "impact": impact, "defender_side": defender_side}


func _check_remote_presentation(table: GameTable, spectator: bool) -> void:
	var board := _remote_board(table, spectator)
	var targets := board["targets"] as Array[Card3D]
	var attacker := board["attacker"] as Card3D
	var label := "spectator" if spectator else "mirrored guest"
	var frame := Engine.get_process_frames()
	table._try_present_online_impact(1)
	_check(Engine.get_process_frames() == frame and targets.all(func(card: Card3D): return card.current_hp == 9), label + " applies every authoritative lava hit in one contact frame")
	_check(attacker.current_hp == 3 and (board["ally"] as Card3D).current_hp == 20, label + " applies the main counter and leaves allies unchanged")
	_check(targets.all(func(card: Card3D): return card.get_blood_intensity() > 0.0), label + " renders hit feedback on all five targets")
	targets[0]._process(0.4)
	var blood_before := targets[0].get_blood_intensity()
	table._online_queued_impact_events[1] = board["impact"]
	table._try_present_online_impact(1)
	_check(is_equal_approx(targets[0].get_blood_intensity(), blood_before) and targets[0].current_hp == 9, label + " ignores duplicate lava packets without replaying damage or blood")


func _check_remote_attack_animation(table: GameTable, spectator: bool) -> void:
	var board := _remote_board(table, spectator)
	var targets := board["targets"] as Array[Card3D]
	var attacker := board["attacker"] as Card3D
	var label := "spectator" if spectator else "mirrored guest"
	# Let the real incoming attack path build its own original-target context
	# and present the already queued authoritative packet at animation contact.
	table._online_client_attack_contexts.clear()
	table._online_client_attack_phases.clear()
	var context_at_contact := {"correct_targets": false}
	attacker.attack_impact.connect(func():
		var context := table._online_client_attack_contexts.get(1, {}) as Dictionary
		context_at_contact["correct_targets"] = context.get("lava_targets", []) == targets
	)
	var impacts := _watch_impacts(attacker, targets)
	await table._rpc_play_online_attack("player", 2, "enemy", 2, 1, 1)
	_check(bool(context_at_contact["correct_targets"]), label + " real attack animation captures the original opposing slot identities")
	_check(impacts.size() == 1 and bool(impacts[0]["same_frame"]) and impacts[0]["target_hp"] == [9, 9, 9, 9, 9], label + " queued lava packet resolves all targets at the real animation contact")
	_check(table._online_client_attack_contexts.is_empty() and table._online_client_presentation_depth == 0 and table._online_queued_impact_events.is_empty(), label + " real attack completes and releases its context and presentation barrier")


func _check_remote_invalid_targets(table: GameTable) -> void:
	for invalid_kind in ["instance", "side", "duplicate", "replacement"]:
		var board := _remote_board(table)
		var impact := board["impact"] as Dictionary
		var targets := board["targets"] as Array[Card3D]
		match invalid_kind:
			"instance":
				impact["lava_hits"][0]["state"]["card_data"]["instance_id"] = "another-owned-copy"
			"side":
				impact["lava_hits"][0]["side"] = "player"
			"duplicate":
				impact["lava_hits"].append(impact["lava_hits"][0].duplicate(true))
			"replacement":
				var old_target := targets[0]
				# Even an identical snapshot must not hit a new node in this slot.
				_spawn(table, "player", 0, old_target.card_data.duplicate(true))
				old_target.queue_free()
		table._try_present_online_impact(1)
		_check((board["attacker"] as Card3D).current_hp == 5 and targets[2].current_hp == 10 and not bool(table._online_applied_impact_sequences.get(1, true)), "invalid lava " + invalid_kind + " rejects the whole packet before any card changes")


func _check_remote_deaths(table: GameTable) -> void:
	var board := _remote_board(table)
	var impact := board["impact"] as Dictionary
	impact["defender_state"]["current_hp"] = 0
	impact["defender_died"] = true
	for hit: Dictionary in impact["lava_hits"]:
		hit["state"]["current_hp"] = 0
		hit["died"] = true
	for index in range(3):
		table._player_deck.append(_data())
	table._try_present_online_impact(1)
	_check(table._player_slots.all(func(card): return card == null), "a lethal online lava packet frees all five opposing slots together")
	await table._wait_for_pending_card_deaths()
	_check(table._player_deck.size() == 3 and table._player_slots.all(func(card): return card == null), "guest lava deaths leave replacement draws to the authoritative host")


func _check_remote_exit(table: GameTable) -> void:
	var board := _remote_board(table)
	var impact := (board["impact"] as Dictionary).duplicate(true)
	table._online_active_exit_sequence = 1
	table._clear_match()
	await get_tree().process_frame
	# The queued context now contains freed card references, as after a match
	# cinematic. The exit guard must run before examining any of those objects.
	table._try_present_online_impact(1)
	table._rpc_play_online_impact(impact)
	_check(table._online_applied_impact_sequences.is_empty() and table._pending_card_deaths.is_empty(), "late lava packets cannot access retired cards or start death jobs during exit")
	_check(table._player_slots.all(func(card): return card == null) and table._enemy_slots.all(func(card): return card == null), "late lava presentation cannot rebuild either board after cinematic cleanup")
	table._retire_online_battle_presentation()
	table._try_present_online_impact(1)
	_check(table._online_client_attack_contexts.is_empty() and table._online_queued_impact_events.is_empty(), "retiring online presentation clears queued lava contexts and packets")
	table._online_mode = false
	table._reset_online_sync_tracking()
	NetworkManager.leave_lobby()
