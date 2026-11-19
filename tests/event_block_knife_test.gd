extends "res://tests/combat_effect_audit_test.gd"


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	var camera := Camera3D.new()
	add_child(camera)
	table = _make_table(camera)
	for side: String in ["player", "enemy"]:
		_check_pin(side)
	_check_replay_and_refresh()
	_check_restore_and_concealment()
	_check_retirement()
	table._clear_match()
	table.queue_free()
	await get_tree().process_frame
	camera.queue_free()
	await get_tree().process_frame
	print("EVENT_BLOCK_KNIFE_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _check_pin(side: String) -> void:
	_reset()
	var card := _spawn(side, 2, 4, 40)
	card.apply_event_block(2)
	var knife: Node3D = card._event_block_badge
	knife.set_process(false)
	check(knife.visible and knife.phase == knife.Phase.ENTERING, side + " block launches the actual knife into its target")
	check(knife.find_children("*", "Label3D", true, false).is_empty(), side + " blue text and background are replaced completely")
	check(knife.find_children("*", "CollisionObject3D", true, false).is_empty(), side + " cosmetic knife cannot absorb card clicks or alter physics")
	var model := knife.get_node("PinMotion/Orientation/Model") as Node3D
	var tip_in_card := card.to_local(model.to_global(knife.SOURCE_TIP))
	check(tip_in_card.z > 1.0, side + " blade tip starts above the card face")
	knife._process(knife.ENTRY_DURATION + knife.SETTLE_DURATION)
	tip_in_card = card.to_local(model.to_global(knife.SOURCE_TIP))
	check(tip_in_card.distance_to(knife.position) < 0.0001 and tip_in_card.z < -0.29, side + " measured blade tip penetrates through the card into the table")
	var handle_in_card := card.to_local(model.to_global(knife.SOURCE_TIP + Vector3(0, 0, 5.3)))
	var intersection := tip_in_card.lerp(handle_in_card, (0.03 - tip_in_card.z) / (handle_in_card.z - tip_in_card.z))
	check(absf(intersection.x) < 0.35 and absf(intersection.y) < 0.5, side + " the embedded blade crosses the printed face inside the target card")
	var decoration := table.get_node("decortaions/knife") as Node3D
	check(model.global_basis.get_scale().is_equal_approx(decoration.global_basis.get_scale()), side + " knife has exactly the same world size as the table decoration")
	var shaft := (handle_in_card - tip_in_card).normalized()
	check(shaft.dot(Vector3.BACK) > 0.97, side + " knife stands almost upright like the reference image")
	check(knife.phase == knife.Phase.PINNED and knife.motion.transform == Transform3D.IDENTITY, side + " knife finishes its entry in a fixed resting pose")
	var pinned := knife.global_transform
	card.global_position.x += 0.4
	check(is_equal_approx(knife.global_position.x - pinned.origin.x, 0.4), side + " embedded knife follows its own card during rearrangement")
	table._tick_event_blocks(side)
	check(card.event_block_turns == 1 and knife.phase == knife.Phase.PINNED and knife.visible, side + " first completed owner turn keeps the knife embedded")
	table._tick_event_blocks(_opponent(side))
	check(card.event_block_turns == 1 and knife.phase == knife.Phase.PINNED, side + " the other player's turn cannot release the knife")
	table._tick_event_blocks(side)
	check(not card.is_event_blocked() and knife.phase == knife.Phase.LEAVING, side + " second completed owner turn releases the card and withdraws the knife")
	knife._process(knife.EXIT_DURATION * 0.5)
	check(knife.motion.position.z > 0.2 and knife._meshes[0].transparency > 0.0, side + " released knife pulls out and fades")
	knife._process(knife.EXIT_DURATION)
	check(not knife.visible and knife.phase == knife.Phase.INACTIVE, side + " knife is completely gone after withdrawal")


func _check_replay_and_refresh() -> void:
	_reset()
	var card := _spawn("enemy", 2, 4, 40)
	card.apply_event_block(2)
	var knife: Node3D = card._event_block_badge
	knife.set_process(false)
	knife._process(0.12)
	var pose: Transform3D = knife.motion.transform
	var elapsed: float = knife._elapsed
	var snapshot := card.get_network_state()
	card.apply_network_state(snapshot)
	card.apply_network_state(snapshot)
	card.apply_event_block(1)
	check(knife.motion.transform.is_equal_approx(pose) and is_equal_approx(knife._elapsed, elapsed), "replayed snapshots and weaker refreshes do not restart the incoming knife")
	check(card.event_block_turns == 2 and card.find_children("EventBlockBadge", "Node3D", false, false).size() == 1, "refresh never shortens the block or creates a duplicate knife")
	knife._process(1.0)
	card.tick_event_block()
	card.tick_event_block()
	knife._process(knife.EXIT_DURATION * 0.5)
	card.apply_event_block(2)
	knife.set_process(false)
	check(knife.phase == knife.Phase.ENTERING and knife._meshes[0].transparency == 0.0, "new block during withdrawal cancels the exit and throws a complete knife")
	knife._process(1.0)
	check(knife.visible and knife.phase == knife.Phase.PINNED, "interrupted withdrawal cannot hide the newly pinned knife")


func _check_restore_and_concealment() -> void:
	_reset()
	var card := _spawn("enemy", 2, 4, 40)
	card.apply_event_block(2)
	card.tick_event_block()
	var replica := _spawn("player", 2, 4, 40)
	replica.setup(card.export_event_deck_card())
	var knife: Node3D = replica._event_block_badge
	check(replica.event_block_turns == 1 and knife.visible and knife.phase == knife.Phase.PINNED, "stolen/redrawn card restores its remaining block with an embedded knife")
	var snapshot := replica.get_network_state()
	replica.set_stats_hidden(true)
	check(not knife.visible and replica.get_network_state() == snapshot, "viewer concealment hides the knife without changing combat state")
	replica.set_stats_hidden(false)
	check(knife.visible and knife.phase == knife.Phase.PINNED, "revealing stats restores the same embedded knife without another throw")
	var pose: Transform3D = knife.motion.transform
	replica._on_locale_changed()
	check(knife.motion.transform.is_equal_approx(pose) and knife.phase == knife.Phase.PINNED, "locale refresh does not replay or move the knife")


func _check_retirement() -> void:
	_reset()
	var card := _spawn("enemy", 2, 4, 40)
	card.apply_event_block(2)
	var knife: Node3D = card._event_block_badge
	card.begin_death_dissolve()
	check(not knife.visible and knife.phase == knife.Phase.INACTIVE, "confirmed card death hides and stops the knife before its death flight")
	card._update_event_block_badge()
	check(not knife.visible, "late block refresh cannot reveal a knife on a dissolving card")
	_reset()
	card = _spawn("enemy", 2, 4, 40)
	card.apply_event_block(2)
	knife = card._event_block_badge
	card.setup(CardDatabase.get_card("corpse"))
	check(not card.is_event_blocked() and not knife.visible and knife.phase == knife.Phase.INACTIVE, "fresh battle setup clears the previous card's pin immediately")
