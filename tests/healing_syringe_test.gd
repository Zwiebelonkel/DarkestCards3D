extends "res://tests/combat_effect_audit_test.gd"

const SYRINGE := preload("res://scenes/effects/PoisonSyringe.tscn")


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	var camera := Camera3D.new()
	add_child(camera)
	table = _make_table(camera)
	_check_random_yaw()
	for side: String in ["player", "enemy"]:
		await _check_regeneration(side)
		await _check_neighbor_heal(side)
		_check_heal_event(side)
	for spectator in [false, true]:
		_check_remote(spectator)
	await _check_cleanup()
	table._online_mode = false
	NetworkManager.current_lobby_id = 0
	NetworkManager._match_in_progress = false
	NetworkManager._participants.clear()
	table._clear_match()
	await get_tree().create_timer(1.35).timeout
	table.queue_free()
	await get_tree().process_frame
	camera.queue_free()
	await get_tree().process_frame
	print("HEALING_SYRINGE_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _check_random_yaw() -> void:
	_reset()
	var target := _spawn("enemy", 2, 0, 30)
	var table_rng: int = table._rng.state
	var card_rng: int = target._rng.state
	var angles := {}
	var pitch := INF
	for seed_value in range(1, 9):
		var syringe := SYRINGE.instantiate()
		table.add_child(syringe)
		syringe._random.seed = seed_value
		syringe.play_on(target)
		syringe.set_process(false)
		angles[roundi(syringe.injection_yaw * 1000.0)] = true
		var yaw: float = syringe.injection_yaw
		syringe._apply_pose(syringe.ENTRY_DURATION)
		var barrel := syringe.get_node("InjectionPivot/Model/spritze") as MeshInstance3D
		var tip := barrel.to_global(Vector3(0, 1.844923, 0))
		check(tip.distance_to(target.global_position + syringe.TIP_OFFSET) < 0.001, "random yaw keeps the needle tip fixed on its card: seed %d" % seed_value)
		var inclination := barrel.global_basis.y.normalized().dot(Vector3.DOWN)
		if not is_finite(pitch):
			pitch = inclination
		check(is_equal_approx(inclination, pitch), "random yaw preserves the original puncture inclination: seed %d" % seed_value)
		syringe._apply_pose(syringe.ENTRY_DURATION + syringe.PRESS_DURATION * 0.5)
		check(is_equal_approx(syringe.injection_yaw, yaw) and absf(sin(syringe.rotation.y - yaw)) < 0.001, "yaw stays constant while the plunger presses: seed %d" % seed_value)
		syringe.cancel()
	check(angles.size() >= 6, "individual injections receive varied Y rotations over the full circle")
	check(table._rng.state == table_rng and target._rng.state == card_rng, "cosmetic yaw never consumes the table or card RNG")


func _check_regeneration(side: String) -> void:
	_reset()
	var target := _spawn(side, 2, 0, 30, [{"type":"regeneration", "value":3}])
	target.take_damage(10)
	await table._apply_start_turn_effects(side)
	check(target.current_hp == 23 and table._poison_syringes.size() == 1 and table._poison_syringes[0].is_for(target), side + " real regeneration heals and injects its own card once")
	check(not target.has_meta("poison_turns"), side + " healing presentation does not apply poison")
	target.heal(30)
	await table._apply_start_turn_effects(side)
	check(table._poison_syringes.size() == 1, side + " full-HP regeneration does not create a zero-healing injection")


func _check_neighbor_heal(side: String) -> void:
	_reset()
	var healer := _spawn(side, 2, 0, 30, [{"type":"neighbor_heal", "value":4}])
	var left := _spawn(side, 1, 0, 30)
	var right := _spawn(side, 3, 0, 30)
	var far := _spawn(side, 0, 0, 30)
	left.take_damage(2)
	right.take_damage(10)
	far.take_damage(10)
	await table._apply_start_turn_effects(side)
	check(left.current_hp == 30 and right.current_hp == 24 and far.current_hp == 20, side + " neighbor healing preserves actual capped HP gains and adjacency")
	check(table._poison_syringes.size() == 2 and table._poison_syringes.any(func(item): return item.is_for(left)) and table._poison_syringes.any(func(item): return item.is_for(right)), side + " each healed neighbor receives its own injection")
	check(not table._poison_syringes.any(func(item): return item.is_for(healer) or item.is_for(far)), side + " healer source and nonadjacent card do not receive an injection")


func _check_heal_event(side: String) -> void:
	_reset()
	table._current_turn = side
	var target := _spawn(side, 2, 0, 30)
	target.take_damage(11)
	var event := {}
	for candidate: Dictionary in table._event_deck:
		if candidate.get("id") == "heal_event":
			event = candidate
			break
	table._event_deck.erase(event)
	table._event_hand(side).append(event)
	check(table._try_play_event(side, str(event.get("uid", "")), 2), side + " production Heal event accepts the injured ally")
	check(target.current_hp == 30 and table._poison_syringes.size() == 1 and table._poison_syringes[0].is_for(target), side + " Heal event restores HP and injects exactly its selected card")
	check(table._event_discard.size() == 1 and table.ended_turns.is_empty(), side + " injection does not consume an extra event or the attack turn")
	var count := table._poison_syringes.size()
	table._present_healing(target, 0, false)
	check(table._poison_syringes.size() == count, side + " zero healing never injects")


func _check_remote(spectator: bool) -> void:
	_reset()
	NetworkManager.current_lobby_id = 987
	NetworkManager._match_in_progress = true
	NetworkManager._participants = {0:{"role":"player"}, 1:{"role":"player"}}
	table._online_mode = true
	table._online_is_spectator = spectator
	table._online_turn_sequence = 5
	var target := _spawn("enemy" if spectator else "player", 2, 0, 30)
	var identity := str(target.card_data.instance_id)
	var hp := target.current_hp
	table._rpc_play_online_blood(5, 1, 0, "enemy", 2, "heal", 1.0, false, "", -1, 4, identity)
	table._rpc_play_online_blood(5, 1, 0, "enemy", 2, "heal", 1.0, false, "", -1, 4, identity)
	check(table._poison_syringes.size() == 1 and target.current_hp == hp, "remote fighter/spectator injects a real healing event once without changing HP twice")
	target.apply_network_state(target.get_network_state())
	table._rpc_play_online_blood(5, 2, 0, "enemy", 2, "heal", 1.0, false, "", -1, 4, "old-instance")
	table._rpc_play_online_blood(4, 3, 0, "enemy", 2, "heal", 1.0, false, "", -1, 4, identity)
	check(table._poison_syringes.size() == 1, "snapshots, stale turns and replaced-card healing do not replay injections")
	SettingsManager.set_damage_numbers_enabled(false)
	table._rpc_play_online_blood(5, 4, 0, "enemy", 2, "heal", 1.0, false, "", -1, 3, identity)
	check(table._poison_syringes.size() == 2, "local number preference does not suppress the healing injection")
	SettingsManager.set_damage_numbers_enabled(true)
	table._online_mode = false


func _check_cleanup() -> void:
	_reset()
	var target := _spawn("enemy", 2, 0, 30)
	table._present_healing(target, 3, false)
	var syringe: Node3D = table._poison_syringes.back()
	target.take_damage(30)
	table._remove_dead_card(target, false, Vector3(INF, INF, INF), false)
	check(not syringe.pivot.visible and syringe.is_queued_for_deletion(), "confirmed death cancels a healing injection before the card flies away")
	_reset()
	target = _spawn("enemy", 2, 0, 30)
	table._present_healing(target, 3, false)
	syringe = table._poison_syringes.back()
	table._clear_match()
	await get_tree().process_frame
	check(not is_instance_valid(syringe) and table._poison_syringes.is_empty(), "match clear frees healing injections through the shared lifecycle")
	_reset()
	target = _spawn("enemy", 2, 0, 30)
	table._present_healing(target, 3, false)
	syringe = table._poison_syringes.back()
	table._retire_online_battle_presentation()
	await get_tree().process_frame
	check(not is_instance_valid(syringe) and table._poison_syringes.is_empty(), "online retirement frees healing injections")
