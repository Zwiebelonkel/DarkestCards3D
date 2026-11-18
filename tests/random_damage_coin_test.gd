extends "res://tests/combat_effect_audit_test.gd"

const COIN := preload("res://scenes/effects/RandomDamageCoin.tscn")


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
	await _check_faces()
	for side: String in ["player", "enemy"]:
		await _check_duel_coin(side, [])
		await _check_duel_coin(side, [{"type": "triple_strike"}])
	await _check_cancel()
	for spectator in [false, true]:
		for value: float in [0.75, 2.0]:
			await _check_remote_coin(spectator, value)
	_reset()
	var attacker := _spawn("player", 2, 4, 30)
	var defender := _spawn("enemy", 2, 0, 30)
	await table._resolve_duel(attacker, defender, "player")
	check(table._random_damage_coins.is_empty(), "ordinary attacks never spawn a coin")
	_reset()
	attacker = _spawn("player", 2, 4, 30, [{"type": "random_damage"}])
	defender = _spawn("enemy", 2, 0, 30)
	attacker.stun_next_attack()
	await table._resolve_duel(attacker, defender, "player")
	check(table._random_damage_coins.is_empty() and defender.current_hp == 30, "a skipped stunned attack never tosses a coin")
	table._clear_match()
	table.queue_free()
	table = null
	await get_tree().process_frame
	await get_tree().process_frame
	camera.queue_free()
	await get_tree().process_frame
	_finish.call_deferred()


func _finish() -> void:
	print("RANDOM_DAMAGE_COIN_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _check_faces() -> void:
	var source := (load("res://assets/effects/coin/coin.glb") as PackedScene).instantiate()
	var original_red := ((source.get_node("0_75") as MeshInstance3D).get_active_material(0) as BaseMaterial3D).albedo_color
	for value: float in [0.75, 2.0]:
		var coin := COIN.instantiate()
		add_child(coin)
		coin.set_process(false)
		coin.play_flip(value, Vector3(0, 0.145, 0), Vector3(-3.7, 0.9, 0.35))
		check(not coin.result_revealed and coin.position.x < -3.0, "coin enters from outside the central view")
		coin._process(coin.REVEAL_DURATION - 0.01)
		check(not coin.result_revealed, "the visible result includes a short readable hold")
		coin._process(0.02)
		check(coin.result_revealed and coin.position.is_equal_approx(Vector3(0, 0.145, 0)), "coin settles on the table before revealing its result")
		var local_up: Vector3 = coin.basis.y
		check(local_up.y > 0.99 if value == 0.75 else local_up.y < -0.99, "the correct original model face points up for " + str(value))
		check(coin.get_node("Model/0_75").position.y > 0.115 and coin.get_node("Model/2").position.y < -0.115, "both number meshes clear the opaque coin surface")
		coin.dissolve()
		check(coin._materials.size() == 3 and coin._materials[1].get_shader_parameter("base_color") == original_red, "all three surfaces dissolve while preserving the original face colors")
		check(coin._materials[0].get_shader_parameter("metallic_amount") == 1.0 and not coin._materials[0].get_shader_parameter("unshaded_mode") and coin._materials[0].get_shader_parameter("emission_intensity") == 0.0, "coin uses real metallic reflections without self-illumination")
		coin._process(coin.DISSOLVE_DURATION * 0.5)
		check(is_equal_approx(float(coin._materials[0].get_shader_parameter("dissolve_progress")), 0.5), "dissolve progresses gradually after the reveal")
		coin._process(coin.DISSOLVE_DURATION)
		check(coin.is_queued_for_deletion(), "a finished coin cleans itself up")
		await get_tree().process_frame
	source.free()
	var legacy := CardData.normalize_effect({"type": "random_damage", "min": 0.25, "max": 1.8})
	check(legacy.min == 0.75 and legacy.max == 2.0, "legacy saved effects display the same two sides as combat")


func _check_duel_coin(side: String, extra_effects: Array) -> void:
	_reset()
	var effects: Array = [{"type": "random_damage"}]
	effects.append_array(extra_effects)
	var attacker := _spawn(side, 2, 4, 100, effects)
	var defender := _spawn(_opponent(side), 2, 1, 100)
	var start := attacker.position
	var records: Array[Dictionary] = []
	attacker.attack_impact.connect(func():
		var coin: Node3D = table._random_damage_coins.back()
		records.append({"id": coin.get_instance_id(), "value": coin.multiplier, "ready": coin.result_revealed, "dissolving": coin._dissolving})
	)
	table._resolve_duel(attacker, defender, side)
	check(table._random_damage_coins.size() == 1 and defender.current_hp == 100, side + " choosing a target immediately starts the coin before damage")
	await get_tree().create_timer(0.2).timeout
	check(attacker.position.is_equal_approx(start) and defender.current_hp == 100, side + " attacker waits while the coin is in flight")
	var deadline := Time.get_ticks_msec() + 6000
	while table.ended_turns.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var expected := 0
	var ids := {}
	for record: Dictionary in records:
		expected += roundi(4.0 * float(record.value))
		ids[record.id] = true
		check(record.ready and record.dissolving, side + " strike starts only after the result and overlaps its dissolve")
	var count := CombatResolver.get_hit_count(attacker)
	check(records.size() == count and ids.size() == count, side + " each strike gets exactly one independent coin")
	check(defender.current_hp == 100 - expected and attacker.current_hp == 99, side + " actual damage matches every revealed face; counter remains unmodified")
	await get_tree().create_timer(1.2).timeout
	check(table._random_damage_coins.all(func(coin): return not is_instance_valid(coin)), side + " dissolves finish without delaying the turn")
	# A later turn reuses this same table after its previous coins freed themselves.
	table.ended_turns.clear()
	table._resolve_duel(attacker, defender, side)
	check(table._random_damage_coins.size() == 1 and is_instance_valid(table._random_damage_coins[0]), side + " the next attack prunes expired coins safely")
	# Cancel this extra toss so it cannot overlap the next scenario.
	table._clear_match()
	await get_tree().process_frame
	await get_tree().process_frame


func _check_cancel() -> void:
	_reset()
	var attacker := _spawn("player", 2, 4, 30, [{"type": "random_damage"}])
	var defender := _spawn("enemy", 2, 0, 30)
	table._resolve_duel(attacker, defender, "player")
	await get_tree().create_timer(0.1).timeout
	table._clear_match()
	await get_tree().process_frame
	await get_tree().process_frame
	check(table._random_damage_coins.is_empty() and table.target_hit_records.is_empty(), "clearing the match during a toss cancels both coin and pending damage")


func _check_remote_coin(spectator: bool, value: float) -> void:
	_reset()
	NetworkManager.current_lobby_id = 123
	NetworkManager._match_in_progress = true
	NetworkManager._participants = {1: {"role": "player"}, 2: {"role": "player"}}
	NetworkManager._connected_peer_ids.assign([1])
	table._online_mode = true
	table._online_is_spectator = spectator
	table._online_turn_sequence = 1
	var side := "player" if spectator else "enemy"
	var attacker := _spawn(side, 2, 4, 30, [{"type": "random_damage"}])
	var defender := _spawn(_opponent(side), 2, 0, 30)
	var before := attacker.position
	var contact := {"ready": false, "value": 0.0}
	attacker.attack_impact.connect(func():
		var coin: Node3D = table._random_damage_coins.back()
		contact.ready = coin.result_revealed
		contact.value = coin.multiplier
		# Supply the already-authoritative contact state, as the impact RPC does.
		table._online_applied_impact_sequences[1] = true
		attacker.release_attack_after_impact()
	)
	table._rpc_play_online_attack("player", 2, "enemy", 2, 1, 1, value)
	await get_tree().create_timer(0.2).timeout
	check(attacker.position.is_equal_approx(before), "remote fighter/spectator waits for its coin before moving")
	var deadline := Time.get_ticks_msec() + 3000
	while table._online_client_presentation_depth > 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(contact.ready and contact.value == value, "remote presentation uses the host's exact " + str(value) + " face without rerolling")
	check(table._online_client_presentation_depth == 0 and table._online_client_attack_contexts.is_empty(), "remote coin releases the normal attack presentation barrier")
	_reset()
