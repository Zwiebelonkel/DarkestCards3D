extends "res://tests/combat_effect_audit_test.gd"


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	AudioServer.set_bus_mute(0, true)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 6, 5)
	camera.look_at(Vector3.ZERO)
	table = _make_table(camera)
	mirror = _make_table(camera)
	await get_tree().process_frame
	_check_new_catalog()
	for side: String in ["player", "enemy"]:
		await _check_sacrifice(side)
		await _check_suffering_ticks(side)
		await _check_neighbor_cure(side)
		await _check_death_draw(side)
		await _check_death_poison_spread(side)
	await _capture_status()
	await _drain_death_animations()
	for finished_table: AuditTable in [table, mirror]:
		finished_table._clear_match()
		finished_table.target_hit_records.clear()
		finished_table.thorns_hit_records.clear()
	await get_tree().process_frame
	table.queue_free()
	mirror.queue_free()
	table = null
	mirror = null
	await get_tree().process_frame
	await get_tree().process_frame
	print("ETERNAL_SUFFERING_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _check_new_catalog() -> void:
	var credit := CardDatabase.get_card("credit_card")
	check(CardData.get_active_effects(credit) == [{"type":"eternal_suffering"}], "Credit Card has exactly its new innate suffering effect")
	check(CardDatabase.get_all_cards().filter(func(card: Dictionary): return CardData.has_effect(card, "eternal_suffering")).size() == 1, "no other authored card carries Eternal Suffering")
	check(not EffectDatabase.get_effect("eternal_suffering").is_empty() and EffectDatabase.get_rollable_effects().all(func(effect: Dictionary): return str(effect.type) != "eternal_suffering"), "suffering is documented but excluded from the random effect pool")
	check(CardData.create_instance("corpse", 1, [{"type":"eternal_suffering"}]).effects.is_empty(), "instance rewards cannot grant the innate-only effect")
	check(not CardUpgradeManager.add_effect("corpse", {"type":"eternal_suffering"}), "upgrades cannot purchase Eternal Suffering")
	for legacy: String in ["deck_burn", "draw_on_kill"]:
		check(CardData.normalize_effect({"type":legacy, "name":"Old", "amount":9}) == {"type":"draw_on_death"}, "legacy draw effect migrates without its obsolete rules: " + legacy)
	check(CardData._normalize_effects([{"type":"draw_on_kill"}, {"type":"draw_on_death"}]).size() == 1, "old and new death-draw aliases cannot double the effect")
	check(EffectPresentation.get_icon_path({"type":"eternal_suffering"}) == "res://assets/effects/eternalSuffering.png", "presentation uses the supplied suffering icon")
	var accepted := NetworkManager._sanitize_remote_card({"card_id":"credit_card", "active_effects":[{"type":"eternal_suffering", "damage":50}]})
	check(CardData.get_effect(accepted, "eternal_suffering") == {"type":"eternal_suffering"}, "online Credit Card keeps only canonical innate parameters")
	var rejected := NetworkManager._sanitize_remote_card({"card_id":"corpse", "active_effects":[{"type":"eternal_suffering"}]})
	check(not CardData.has_effect(rejected, "eternal_suffering"), "remote cards cannot forge the Credit Card's innate effect")


func _check_sacrifice(side: String) -> void:
	for protection: String in ["shield_first_hit", "last_stand", "grave_return"]:
		_reset()
		_keep_match_alive(side)
		var credit := _spawn(side, 2, 1, 50, [{"type":"eternal_suffering"}, {"type":protection}], "credit_card")
		var target := _spawn(_opponent(side), 2, 0, 30, [{"type":"shield_first_hit"}])
		var state_at_contact: Array[Dictionary] = []
		credit.attack_impact.connect(func(): state_at_contact.append(target.get_network_state()), CONNECT_DEFERRED | CONNECT_ONE_SHOT)
		await table._resolve_duel(credit, target, side)
		check(table._get_card_from_slot(side, 2) == null and target.current_hp == 30 and target.eternal_suffering_damage == 1, side + " sacrifice bypasses own " + protection + " and transfers through the target shield")
		check(state_at_contact.size() == 1 and int(state_at_contact[0].eternal_suffering_damage) == 1, side + " suffering is already transferred in the attack contact frame")
		check(target.get_node("CombatIndicators/EternalSuffering").visible, side + " target immediately displays its red suffering status")
		_check_online_mirror(side + " suffering contact")
	_reset()
	_keep_match_alive(side)
	var afflicted := _spawn(side, 2, 2, 30)
	afflicted.apply_eternal_suffering()
	var next_target := _spawn(_opponent(side), 2, 0, 30)
	await table._resolve_duel(afflicted, next_target, side)
	check(afflicted.current_hp == 30 and next_target.current_hp == 28 and next_target.eternal_suffering_damage == 0, side + " afflicted targets attack normally without sacrificing or spreading the curse")


func _check_suffering_ticks(side: String) -> void:
	_reset()
	_keep_match_alive(side)
	var target := _spawn(side, 2, 0, 100, [{"type":"armor", "value":0.95}, {"type":"shield_first_hit"}])
	target.apply_eternal_suffering()
	var expected_hp := 100
	for damage: int in [1, 3, 5, 7]:
		await table._apply_start_turn_effects(_opponent(side))
		check(target.current_hp == expected_hp, side + " opponent turn never advances suffering")
		await table._apply_start_turn_effects(side)
		expected_hp -= damage
		check(target.current_hp == expected_hp and target.eternal_suffering_damage == damage + 2 and target._first_hit_shield_available, side + " suffering deals unmitigated " + str(damage) + " then increases by two")
	target.heal(2)
	target.apply_eternal_suffering()
	check(target.eternal_suffering_damage == 9, side + " ordinary healing and reapplication cannot remove or restart suffering")
	_check_online_mirror(side + " escalating suffering")
	var state := target.get_network_state()
	var stolen := _spawn(_opponent(side), 0, 0, 10)
	stolen.setup(target.export_event_deck_card())
	check(stolen.get_network_state() == state and stolen.eternal_suffering_damage == 9, side + " stolen-card redraw preserves the accumulated suffering")
	for save: String in ["last_stand", "grave_return"]:
		_reset()
		_keep_match_alive(side)
		target = _spawn(side, 2, 0, 10, [{"type":save}, {"type":"draw_on_death"}])
		target.take_damage(9)
		target.apply_eternal_suffering()
		await table._apply_start_turn_effects(side)
		check(not target.is_dead() and target.eternal_suffering_damage == 3 and table._event_hand(side).is_empty(), side + " " + save + " delays death without cleansing suffering or awarding a death draw")


func _check_neighbor_cure(side: String) -> void:
	for healer_slot: int in [1, 3]:
		_reset()
		_keep_match_alive(side)
		var target := _spawn(side, 2, 0, 10)
		target.take_damage(9)
		target.apply_eternal_suffering()
		target.advance_eternal_suffering()
		target.advance_eternal_suffering()
		_spawn(side, healer_slot, 0, 30, [{"type":"neighbor_heal", "value":2}])
		await table._apply_start_turn_effects(side)
		check(target.current_hp == 3 and target.eternal_suffering_damage == 0, side + " neighbor in slot " + str(healer_slot) + " cures before a lethal suffering tick")
		await get_tree().create_timer(0.2).timeout
		check(not target.get_node("CombatIndicators/EternalSuffering").visible, side + " neighbor cure removes the status indicator")
	_reset()
	_keep_match_alive(side)
	var target := _spawn(side, 2, 0, 30, [{"type":"regeneration", "value":3}])
	_spawn(side, 0, 0, 30, [{"type":"neighbor_heal", "value":2}])
	target.apply_eternal_suffering()
	await table._apply_start_turn_effects(side)
	check(target.eternal_suffering_damage == 3 and target.current_hp == 29, side + " regeneration and a nonadjacent healer cannot cleanse suffering")
	_spawn(side, 3, 0, 30, [{"type":"neighbor_heal", "value":0}])
	await table._apply_start_turn_effects(side)
	check(target.eternal_suffering_damage == 5, side + " a zero-strength healing effect cannot cleanse suffering")


func _check_death_draw(side: String) -> void:
	for cause: String in ["hit", "poison", "suffering", "sacrifice"]:
		_reset()
		_keep_match_alive(side)
		var effects: Array = [{"type":"draw_on_death"}]
		if cause == "sacrifice":
			effects.append({"type":"eternal_suffering"})
		var victim := _spawn(side, 2, 2, 1, effects)
		var opponent := _spawn(_opponent(side), 2, 9, 30)
		if cause == "poison":
			victim.apply_poison(3, 1)
			await table._apply_start_turn_effects(side)
		elif cause == "suffering":
			victim.apply_eternal_suffering()
			await table._apply_start_turn_effects(side)
		elif cause == "sacrifice":
			await table._resolve_duel(victim, opponent, side)
		else:
			await table._resolve_duel(opponent, victim, _opponent(side))
		check(table._get_card_from_slot(side, 2) == null and table._event_hand(side).size() == 1 and table._event_hand(_opponent(side)).is_empty(), side + " " + cause + " death grants exactly one event to the deceased card's owner")
		if is_instance_valid(victim):
			table._award_event_for_death(victim)
			table._remove_dead_card(victim)
		check(table._event_hand(side).size() == 1, side + " repeated death cleanup cannot duplicate the draw")
	_reset()
	_keep_match_alive(side)
	var attacker := _spawn(side, 2, 9, 30, [{"type":"draw_on_death"}])
	var target := _spawn(_opponent(side), 2, 0, 1)
	await table._resolve_duel(attacker, target, side)
	check(table._event_hand(side).is_empty(), side + " killing another card no longer triggers the old draw-on-kill rule")


func _check_death_poison_spread(side: String) -> void:
	for cause: String in ["hit", "suffering", "poison", "thorns"]:
		_reset()
		_keep_match_alive(side)
		var victim := _spawn(side, 2, 5, 5)
		victim.apply_eternal_suffering()
		victim.advance_eternal_suffering()
		victim.advance_eternal_suffering()
		var left := _spawn(side, 1, 0, 30, [{"type":"shield_first_hit"}])
		var right := _spawn(side, 3, 0, 30)
		var enemy := _spawn(_opponent(side), 2, 9, 30, [{"type":"thorns", "percent":1.0}] if cause == "thorns" else [])
		if cause == "suffering":
			await table._apply_start_turn_effects(side)
		elif cause == "poison":
			victim.apply_poison(9, 1)
			# Kill by poison after surviving the suffering tick: current value 7.
			victim.current_hp = 10
			await table._apply_start_turn_effects(side)
		elif cause == "thorns":
			await table._resolve_duel(victim, enemy, side)
		else:
			await table._resolve_duel(enemy, victim, _opponent(side))
		var expected := 7 if cause == "poison" else 5
		check(table._get_card_from_slot(side, 2) == null and int(left.get_meta("poison_damage", 0)) == expected and int(right.get_meta("poison_damage", 0)) == expected, side + " " + cause + " death spreads the current suffering value to both neighbors")
		check(int(left.get_meta("poison_turns", 0)) == 3 and int(right.get_meta("poison_turns", 0)) == 3 and left.current_hp == 30 and right.current_hp == 30, side + " fresh death poison lasts three turns without an immediate or slot-dependent tick")
		check(left.eternal_suffering_damage == 0 and right.eternal_suffering_damage == 0 and not enemy.has_meta("poison_turns") and not table._get_card_from_slot(side, 4).has_meta("poison_turns"), side + " death spread gives ordinary poison only to adjacent allies")
		_check_online_mirror(side + " death poison " + cause)
		await table._apply_start_turn_effects(side)
		check(left.current_hp == 30 - expected and right.current_hp == 30 - expected and left._first_hit_shield_available, side + " death poison ticks normally through shields on the next own turn")
		if is_instance_valid(victim):
			table._award_event_for_death(victim)
			table._remove_dead_card(victim)
		check(int(left.get_meta("poison_turns", 0)) == 2 and int(right.get_meta("poison_turns", 0)) == 2, side + " duplicate death resolution never refreshes the spread")
		# One poisoned neighbor now dies. Its poison must not spread further.
		right.current_hp = 1
		await table._apply_start_turn_effects(side)
		check(table._get_card_from_slot(side, 3) == null and not table._get_card_from_slot(side, 4).has_meta("poison_turns"), side + " a neighbor dying from the spread cannot propagate poison again")
	_reset()
	_keep_match_alive(side)
	var saved := _spawn(side, 2, 0, 5, [{"type":"last_stand"}])
	var adjacent := _spawn(side, 1, 0, 30)
	saved.apply_eternal_suffering()
	saved.current_hp = 1
	await table._apply_start_turn_effects(side)
	check(saved.current_hp == 1 and not adjacent.has_meta("poison_turns"), side + " surviving a lethal suffering tick does not trigger the death spread")
	saved.cleanse_eternal_suffering_from_neighbor()
	saved.take_damage(9)
	table._remove_dead_card(saved)
	check(not adjacent.has_meta("poison_turns"), side + " a cured card dying later has no poison death spread")
	for edge: int in [0, 4]:
		_reset()
		var source := _spawn(side, edge, 0, 1)
		var neighbor := _spawn(side, 1 if edge == 0 else 3, 0, 20)
		var far := _spawn(side, 2, 0, 20)
		source.apply_eternal_suffering()
		source.take_damage(1)
		table._remove_dead_card(source)
		check(int(neighbor.get_meta("poison_damage", 0)) == 1 and not far.has_meta("poison_turns"), side + " board edge " + str(edge) + " spreads only to its single direct neighbor")


func _capture_status() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Use a separate camera so the table's still-finishing hit-shake tweens
	# cannot move the close-up view during visual validation.
	var camera := Camera3D.new()
	add_child(camera)
	camera.make_current()
	camera.position = Vector3(0, 0.05, 4)
	camera.look_at(Vector3(0, 0.05, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.4
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("181319")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.9
	get_world_3d().environment = environment
	var credit := (load("res://scenes/table/Card3D.tscn") as PackedScene).instantiate() as Card3D
	add_child(credit)
	credit.position.x = -0.55
	credit.setup(CardDatabase.get_card("credit_card"))
	var target := (load("res://scenes/table/Card3D.tscn") as PackedScene).instantiate() as Card3D
	add_child(target)
	target.position.x = 0.55
	target.setup(CardDatabase.get_card("corpse"))
	target.apply_eternal_suffering()
	target.apply_poison(3, 3)
	target.stun_next_attack()
	for tick in range(4):
		target.advance_eternal_suffering()
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png("res://eternal-suffering-active.png") == OK, "rendered the supplied seal and escalating red status")
	# Simulate raised artwork covering the entire icon row, closer to the
	# camera than the status geometry. The icons must still draw on top.
	var occluding_art := QuadMesh.new()
	occluding_art.size = Vector2(0.78, 0.55)
	target.card_image.mesh = occluding_art
	target.card_image.position.z = 0.18
	var art_material := StandardMaterial3D.new()
	art_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	art_material.albedo_color = Color("253abf")
	target.card_image.material_override = art_material
	await RenderingServer.frame_post_draw
	var rendered := get_viewport().get_texture().get_image()
	for type: String in ["poison", "stun"]:
		var badge := target.get_node("CombatIndicators/" + type.to_pascal_case()) as Node3D
		var point := camera.unproject_position(badge.to_global(Vector3(0.067, 0, 0)))
		var pixel := rendered.get_pixelv(Vector2i(point.round()))
		check(pixel.g > pixel.b * 1.3 and (type != "poison" or pixel.g > pixel.r * 1.3), "rendered " + type + " remains visibly above raised opaque card artwork")
	check(rendered.save_png("res://status-badges-over-artwork.png") == OK, "rendered status badges above occluding artwork")
	target.cleanse_eternal_suffering_from_neighbor()
	await get_tree().create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png("res://eternal-suffering-cleansed.png") == OK, "rendered the cleansed card without the status")
	credit.queue_free()
	target.queue_free()
