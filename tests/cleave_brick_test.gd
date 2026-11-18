extends "res://tests/combat_effect_audit_test.gd"

var camera: Camera3D


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	camera = Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 6, 5)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	table = _make_table(camera)
	table.visible = true
	for side: String in ["player", "enemy"]:
		await _check_duel_bricks(side)
	await _check_physics_and_click()
	await _check_blood_contact_and_gui()
	await _check_cleanup_and_lifetime()
	for spectator in [false, true]:
		_check_remote_bricks(spectator)
	table._online_mode = false
	table._reset_online_sync_tracking()
	table._clear_match()
	await get_tree().create_timer(0.8).timeout
	table.queue_free()
	await get_tree().process_frame
	camera.queue_free()
	await get_tree().process_frame
	print("CLEAVE_BRICK_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _check_duel_bricks(side: String) -> void:
	_reset()
	var attacker := _spawn(side, 2, 8, 40, [{"type":"cleave", "side_damage":0.5}])
	var positions: Array[Vector3] = []
	for slot in [1, 2, 3]:
		positions.append(_spawn(_opponent(side), slot, 0, 40).global_position)
	await table._resolve_duel(attacker, table._get_card_from_slot(_opponent(side), 2), side)
	check(table._cleave_bricks.size() == 3, side + " one real Cleave attack drops on center and both occupied neighbors")
	for position in positions:
		check(table._cleave_bricks.any(func(brick): return Vector2(brick.global_position.x, brick.global_position.z).distance_to(Vector2(position.x, position.z)) < 0.06), side + " brick falls vertically onto its actual target")
	check(table.ended_turns.size() == 1, side + " bricks add no extra turn or combat barrier")
	_reset()
	attacker = _spawn(side, 2, 8, 40, [{"type":"cleave"}])
	var edge := _spawn(_opponent(side), 0, 0, 40)
	_spawn(_opponent(side), 1, 0, 40)
	await table._resolve_duel(attacker, edge, side)
	check(table._cleave_bricks.size() == 2, side + " edge Cleave drops only on its two occupied targets")
	_reset()
	attacker = _spawn(side, 2, 8, 40, [{"type":"cleave"}])
	var center := _spawn(_opponent(side), 2, 0, 40, [{"type":"shield_first_hit"}])
	_spawn(_opponent(side), 1, 0, 40, [{"type":"shield_first_hit"}])
	await table._resolve_duel(attacker, center, side)
	check(table._cleave_bricks.size() == 2 and center.current_hp == 40, side + " shields still receive their local brick without dealing extra damage")
	_reset()
	attacker = _spawn(side, 2, 8, 40, [{"type":"cleave"}, {"type":"lava"}])
	center = _spawn(_opponent(side), 2, 0, 40)
	await table._resolve_duel(attacker, center, side)
	check(table._cleave_bricks.is_empty(), side + " Lava supersedes Cleave and never drops bricks")
	_reset()
	attacker = _spawn(side, 2, 8, 40)
	center = _spawn(_opponent(side), 2, 0, 40)
	await table._resolve_duel(attacker, center, side)
	check(table._cleave_bricks.is_empty(), side + " ordinary attacks never drop bricks")


func _check_physics_and_click() -> void:
	_reset()
	var target := _spawn("enemy", 2, 0, 40)
	table._present_cleave_brick(target)
	table._present_cleave_brick(target)
	var brick: RigidBody3D = table._cleave_bricks[0]
	var other: RigidBody3D = table._cleave_bricks[1]
	other.position.x += 1.0
	check(brick.continuous_cd and brick.linear_velocity.y < -4.0, "brick is a real fast-falling rigid body with continuous collision")
	check(brick._materials[0] != other._materials[0], "each brick owns its dissolve material")
	other.freeze = true
	other.linear_velocity = Vector3.ZERO
	other.position.y += 2.0
	var started := Time.get_ticks_msec()
	while not brick.landed and Time.get_ticks_msec() - started < 1000:
		await get_tree().physics_frame
	var impact_ms := Time.get_ticks_msec() - started
	check(brick.landed and impact_ms < 250, "first physical contact occurs during the existing blood burst")
	check(absf(brick.global_position.x - target.global_position.x) < 0.03 and absf(brick.global_position.z - target.global_position.z) < 0.03, "first contact is centered on the card")
	await get_tree().create_timer(0.8).timeout
	check(absf(brick.global_position.y - (target.global_position.y + brick.HALF_HEIGHT)) < 0.025, "brick settles on the card plane instead of falling through the table")
	var rest := brick.global_transform
	check(brick.freeze and brick.linear_velocity.is_zero_approx() and brick.angular_velocity.is_zero_approx(), "settled brick stops simulating instead of rocking on the contact margin")
	await get_tree().create_timer(0.35).timeout
	check(brick.global_transform.is_equal_approx(rest), "resting brick stays exactly still across further physics frames")
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = camera.unproject_position(brick.global_position)
	brick.hide()
	brick._unhandled_input(event)
	check(not brick.kicked, "hidden bricks cannot consume clicks")
	brick.show()
	event.button_index = MOUSE_BUTTON_RIGHT
	brick._unhandled_input(event)
	check(not brick.kicked, "right click does not kick a brick")
	event.button_index = MOUSE_BUTTON_LEFT
	brick._unhandled_input(event)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(brick.kicked and not brick.freeze and brick.linear_velocity.length() > 3.0, "left click wakes the settled brick and launches it using an impulse")
	check(not other.kicked and other.linear_velocity.length() < 0.01, "kicking one brick leaves another local brick alone")
	var first_material: ShaderMaterial = brick._materials[0]
	brick.set_dissolve_progress(0.55)
	check(is_equal_approx(first_material.get_shader_parameter("dissolve_progress"), 0.55) and is_zero_approx(other._materials[0].get_shader_parameter("dissolve_progress")), "tumbling brick dissolves without changing shared model materials")
	check(not JSON.stringify(table._build_online_snapshot()).contains("CleaveBrick"), "cosmetic rigid bodies do not enter match snapshots")


func _check_cleanup_and_lifetime() -> void:
	_reset()
	var target := _spawn("enemy", 2, 0, 40)
	table._present_cleave_brick(target)
	var brick: RigidBody3D = table._cleave_bricks.back()
	brick._landed_at = 0.0
	brick._process(brick.HOLD_DURATION + brick.DISSOLVE_DURATION + 0.1)
	check(brick.is_queued_for_deletion(), "brick frees itself after its hold and slow dissolve")
	table._present_cleave_brick(target)
	brick = table._cleave_bricks.back()
	table._clear_match()
	check(not brick.visible and table._cleave_bricks.is_empty(), "match clear hides and retires every brick immediately")
	await get_tree().process_frame
	check(not is_instance_valid(brick), "cleared bodies are actually freed")
	_reset()
	target = _spawn("enemy", 2, 0, 40)
	table._present_cleave_brick(target)
	brick = table._cleave_bricks.back()
	table._retire_online_battle_presentation()
	check(not brick.visible and table._cleave_bricks.is_empty(), "online exit retires local physics and input")


func _check_blood_contact_and_gui() -> void:
	_reset()
	var probe := Node3D.new()
	probe.set_meta("cleave_blood_probe", true)
	var scene := PackedScene.new()
	scene.pack(probe)
	probe.free()
	table.blood_burst_scene = scene
	var attacker := _spawn("player", 2, 8, 40, [{"type":"cleave"}])
	var target := _spawn("enemy", 2, 0, 1)
	var impact_position := target.global_position + table.blood_spawn_offset
	table._resolve_attack_target_hit(attacker, target, 8, {})
	var brick: RigidBody3D = table._cleave_bricks.back()
	check(target.is_dead() and not brick.landed, "lethal gameplay damage still resolves immediately while the brick falls")
	check(table.get_children().filter(func(node): return node.get_meta("cleave_blood_probe", false)).is_empty(), "Cleave particle emission waits for physical contact")
	target.position.x += 1.0
	var deadline := Time.get_ticks_msec() + 600
	while table.get_children().filter(func(node): return node.get_meta("cleave_blood_probe", false)).is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	var bursts := table.get_children().filter(func(node): return node.get_meta("cleave_blood_probe", false))
	check(brick.landed and bursts.size() == 1 and bursts[0].global_position.is_equal_approx(impact_position), "the blood burst starts at brick contact and keeps the original lethal hit position")
	for burst in bursts:
		burst.queue_free()
	table.blood_burst_scene = null
	# Real viewport event dispatch: a GUI overlay must consume the click before
	# the body's unhandled ray can kick it or touch the card under it.
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = camera.unproject_position(brick.global_position)
	get_viewport().push_input(event, true)
	await get_tree().process_frame
	check(not brick.kicked, "GUI consumes its real mouse event before a brick can intercept it")
	overlay.queue_free()
	await get_tree().process_frame
	event = event.duplicate()
	get_viewport().push_input(event, true)
	await get_tree().physics_frame
	check(brick.kicked, "the same viewport click kicks the brick after the GUI closes")


func _check_remote_bricks(spectator: bool) -> void:
	_reset()
	NetworkManager.current_lobby_id = 987
	NetworkManager._match_in_progress = true
	NetworkManager._participants = {0: {"role":"player"}, 1: {"role":"player"}}
	table._online_mode = true
	table._online_is_spectator = spectator
	table._online_turn_sequence = 1
	var side := "player" if spectator else "enemy"
	var attacker := _spawn(side, 2, 8, 40, [{"type":"cleave"}])
	var target := _spawn(_opponent(side), 2, 0, 40)
	var neighbor := _spawn(_opponent(side), 1, 0, 40)
	var state := target.get_network_state()
	state.current_hp = 32
	table._online_client_attack_contexts[1] = {
		"attacker": attacker, "defender": target,
		"canonical_attacker_side": "player", "attacker_slot": 2,
		"canonical_defender_side": "enemy", "defender_slot": 2,
	}
	table._online_client_attack_phases[1] = 1
	var impact := {
		"attacker_side":"player", "attacker_slot":2, "defender_side":"enemy", "defender_slot":2,
		"attacker_state":attacker.get_network_state(), "defender_state":state, "defender_damage":8,
	}
	table._online_queued_impact_events[1] = impact
	table._try_present_online_impact(1)
	table._online_queued_impact_events[1] = impact
	table._try_present_online_impact(1)
	check(table._cleave_bricks.size() == 1, "remote fighter/spectator presents a primary brick once, including duplicate impact packets")
	table._rpc_play_online_blood(1, 1, 0, "enemy", 1, "cleave_burst", 0.4, false, "", -1, 4, str(neighbor.card_data.instance_id))
	table._rpc_play_online_blood(1, 1, 0, "enemy", 1, "cleave_burst", 0.4, false, "", -1, 4, str(neighbor.card_data.instance_id))
	check(table._cleave_bricks.size() == 2, "secondary damage event creates one independent local brick and deduplicates retransmission")
	table._rpc_play_online_blood(1, 2, 0, "enemy", 1, "cleave_damage", 0.1, false, "", -1, 0, str(neighbor.card_data.instance_id))
	check(table._cleave_bricks.size() == 3, "remote blocked Cleave still presents a brick without inventing blood")
	table._rpc_play_online_blood(1, 3, 0, "enemy", 1, "cleave_burst", 0.4, false, "", -1, 4, "replaced-instance")
	check(table._cleave_bricks.size() == 3, "late secondary effect cannot hit a replacement card")
	table._online_mode = false
