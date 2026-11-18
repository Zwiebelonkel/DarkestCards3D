extends "res://tests/combat_effect_audit_test.gd"

const SYRINGE := preload("res://scenes/effects/PoisonSyringe.tscn")


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 6, 5)
	camera.look_at(Vector3.ZERO)
	table = _make_table(camera)
	_check_animation()
	for side: String in ["player", "enemy"]:
		await _check_application(side)
		await _check_blocked_and_ticks(side)
	await _check_cleanup()
	for spectator in [false, true]:
		_check_remote(spectator)
	# Let the final contact's existing status/blood tweens and positional sound
	# finish before retiring the scene used by this short fixture.
	await get_tree().create_timer(1.35).timeout
	table._retire_online_battle_presentation()
	table._online_mode = false
	table._reset_online_sync_tracking()
	table.target_hit_records.clear()
	table._clear_match()
	table.queue_free()
	table = null
	await get_tree().process_frame
	await get_tree().process_frame
	camera.queue_free()
	await get_tree().process_frame
	_finish.call_deferred()


func _finish() -> void:
	print("POISON_SYRINGE_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _check_animation() -> void:
	_reset()
	var card := _spawn("enemy", 2, 0, 30)
	table._present_poison_application(card)
	var syringe: Node3D = table._poison_syringes[0]
	syringe.set_process(false)
	check(is_equal_approx(syringe.DURATION, 1.0), "full injection lasts one readable second")
	check(syringe.pivot.position.y > 1.0, "syringe enters from above")
	var plunger_start: Vector3 = syringe.plunger.position
	var barrel := syringe.get_node("InjectionPivot/Model/spritze") as MeshInstance3D
	syringe._apply_pose(syringe.ENTRY_DURATION)
	var needle_tip := barrel.to_global(Vector3(0, 1.844923, 0))
	check(needle_tip.distance_to(card.global_position + syringe.TIP_OFFSET) < 0.001, "the imported needle tip reaches the card surface with a shallow puncture")
	var barrel_before := barrel.global_transform
	syringe._apply_pose(syringe.ENTRY_DURATION + syringe.PRESS_DURATION)
	check(syringe.plunger.position.is_equal_approx(plunger_start + syringe.PLUNGER_TRAVEL), "the separate original kolben pushes fully into the barrel")
	check(barrel.global_transform.is_equal_approx(barrel_before), "only the plunger moves during injection")
	check(not (barrel.get_active_material(0) as BaseMaterial3D).emission_enabled, "the original textured syringe has no added glow")
	card.position.x += 0.25
	syringe._apply_pose(syringe.ENTRY_DURATION)
	check(absf(syringe.position.x - card.position.x) < 0.001, "injection follows its actual target card")
	syringe._apply_pose(syringe.ENTRY_DURATION + syringe.PRESS_DURATION + syringe.EXIT_DURATION * 0.5)
	check(syringe.pivot.position.y > 0.4, "the syringe immediately retreats upward after pressing")
	syringe._process(syringe.DURATION + 0.001)
	check(syringe.animation_finished and not syringe.pivot.visible, "the model is completely gone at the end of its one-second animation")
	_reset()


func _check_application(side: String) -> void:
	_reset()
	var attacker := _spawn(side, 2, 1, 100, [{"type": "poison", "damage": 3, "turns": 3}, {"type": "triple_strike"}])
	var target := _spawn(_opponent(side), 2, 0, 100)
	await table._resolve_duel(attacker, target, side)
	check(target.has_meta("poison_turns") and target.current_hp == 97, side + " real attack still applies poison and all three hits")
	check(table._poison_syringes.size() == 1, side + " multi-strike injects each newly poisoned target exactly once")
	check(table.ended_turns.size() == 1, side + " cosmetic injection adds no combat barrier or extra turn")
	await get_tree().create_timer(0.3).timeout
	check(table._poison_syringes.all(func(item): return is_instance_valid(item) and not item.animation_finished and item.pivot.visible), side + " the turn has ended while the readable injection continues")
	await get_tree().create_timer(0.8).timeout
	check(table._poison_syringes.all(func(item): return not is_instance_valid(item) or item.animation_finished), side + " visual injection finishes independently after one second")
	# A fresh attack may poison that same card again and must get another injection.
	table._present_poison_application(target)
	check(is_instance_valid(table._poison_syringes.back()), side + " later poison applications can create a fresh syringe")


func _check_blocked_and_ticks(side: String) -> void:
	_reset()
	var attacker := _spawn(side, 2, 4, 30, [{"type": "poison"}])
	var target := _spawn(_opponent(side), 2, 0, 30, [{"type": "shield_first_hit"}])
	await table._resolve_duel(attacker, target, side)
	check(not target.has_meta("poison_turns") and table._poison_syringes.is_empty(), side + " a fully shielded hit never injects")
	_reset()
	attacker = _spawn(side, 2, 0, 30, [{"type": "poison"}])
	target = _spawn(_opponent(side), 2, 0, 30)
	await table._resolve_duel(attacker, target, side)
	check(not target.has_meta("poison_turns") and table._poison_syringes.is_empty(), side + " zero damage never injects")
	target.apply_poison(3, 3)
	await table._apply_start_turn_effects(_opponent(side))
	check(target.current_hp == 27 and table._poison_syringes.is_empty(), side + " periodic poison damage retains its ordinary effect without another injection")
	target.apply_network_state(target.get_network_state())
	check(table._poison_syringes.is_empty(), side + " replaying a poison snapshot never injects")


func _check_cleanup() -> void:
	_reset()
	var target := _spawn("enemy", 2, 0, 30)
	table._present_poison_application(target)
	var syringe: Node3D = table._poison_syringes.back()
	table._clear_match()
	await get_tree().process_frame
	check(not is_instance_valid(syringe) and table._poison_syringes.is_empty(), "clearing a match removes its in-flight syringe")
	_reset()
	target = _spawn("enemy", 2, 0, 30)
	table._present_poison_application(target)
	syringe = table._poison_syringes.back()
	target.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(not is_instance_valid(syringe) or syringe.is_queued_for_deletion(), "a freed target cancels its injection safely")
	_reset()
	target = _spawn("enemy", 2, 0, 30, [{"type": "last_stand"}])
	table._present_poison_application(target)
	syringe = table._poison_syringes.back()
	var survival := CombatResolver.apply_damage_with_survival(target, 100)
	check(not survival.died and syringe.pivot.visible and not syringe.is_queued_for_deletion(), "a saved lethal hit keeps the living card's syringe visible")
	CombatResolver.apply_damage_with_survival(target, 100)
	table._remove_dead_card(target, false, Vector3(INF, INF, INF), false)
	check(not syringe.pivot.visible and syringe.is_queued_for_deletion(), "confirmed death hides the syringe synchronously before the card's death flight")
	await get_tree().process_frame
	check(not is_instance_valid(syringe), "the dead card's syringe is freed without waiting for its remaining animation")
	while not table._pending_card_deaths.is_empty():
		await get_tree().process_frame


func _check_remote(spectator: bool) -> void:
	_reset()
	table._online_mode = true
	table._online_is_spectator = spectator
	table._online_turn_sequence = 1
	var side := "player" if spectator else "enemy"
	var attacker := _spawn(side, 2, 1, 30, [{"type": "poison"}, {"type": "lava"}])
	var target := _spawn(_opponent(side), 2, 0, 30)
	var extra := _spawn(_opponent(side), 0, 0, 30)
	var state := target.get_network_state()
	state.current_hp = 29
	state["poison_turns"] = 3
	state["poison_damage"] = 3
	var extra_state := extra.get_network_state()
	extra_state.current_hp = 29
	extra_state["poison_turns"] = 3
	extra_state["poison_damage"] = 3
	table._online_client_attack_contexts[1] = {
		"attacker": attacker, "defender": target,
		"canonical_attacker_side": "player", "attacker_slot": 2,
		"canonical_defender_side": "enemy", "defender_slot": 2,
		"lava_targets": (table._player_slots if side == "enemy" else table._enemy_slots).duplicate(),
	}
	table._online_client_attack_phases[1] = 1
	var impact := {
		"turn_sequence": 1, "attack_sequence": 1,
		"attacker_side": "player", "attacker_slot": 2,
		"defender_side": "enemy", "defender_slot": 2,
		"attacker_state": attacker.get_network_state(), "defender_state": state,
		"defender_damage": 1, "poison_applied": true,
		"lava_hits": [{"side": "enemy", "slot": 0, "state": extra_state, "damage": 1, "poison_applied": true}],
	}
	table._online_queued_impact_events[1] = impact
	table._try_present_online_impact(1)
	check(table._poison_syringes.size() == 2, "remote fighter/spectator injects the primary and additional poisoned targets")
	table._online_queued_impact_events[1] = impact
	table._try_present_online_impact(1)
	check(table._poison_syringes.size() == 2, "duplicate remote impact packets never replay the syringes")
