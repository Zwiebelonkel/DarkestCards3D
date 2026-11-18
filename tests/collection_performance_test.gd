extends Node3D

var failures := 0
var baseline := false


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	print(("PASS " if condition else "FAIL ") + message)
	if not condition:
		failures += 1


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	baseline = OS.get_cmdline_user_args().has("--baseline")
	AudioServer.set_bus_mute(0, true)
	GameCurrency.set_process(false)
	CollectionManager.clear_profile_state()
	DeckManager.clear_profile_state()
	var ids: Array[String] = []
	for data: Dictionary in CardDatabase.get_combat_cards():
		if str(data.get("rarity", "")) != "secret" and CollectionManager.can_obtain_card(str(data["id"])):
			ids.append(str(data["id"]))
	for index in range(5000):
		var card_id := ids[index % ids.size()]
		var instance := CardData.create_instance(card_id, 1, [], index % 137 == 0)
		CollectionManager.collection.instances.append(instance)
		CollectionManager.collection.cards[card_id] = int(CollectionManager.collection.cards.get(card_id, 0)) + 1
	CollectionManager.save_collection()
	var screen := (load("res://scenes/ui/CollectionScreen.tscn") as PackedScene).instantiate() as CollectionScreen
	screen.camera = screen.get_node("Camera3D")
	screen.spawn_duration = 0.01
	screen.spawn_stagger = 0.0
	var started := Time.get_ticks_usec()
	add_child(screen)
	print("BENCH initial_collection_ms=", (Time.get_ticks_usec() - started) / 1000.0, " instances=5000 types=", ids.size())
	await get_tree().create_timer(0.1).timeout
	var original_cards := screen._base_positions.keys()
	started = Time.get_ticks_usec()
	screen.refresh_collection()
	print("BENCH unchanged_refresh_ms=", (Time.get_ticks_usec() - started) / 1000.0)
	if not baseline:
		check(screen._base_positions.keys() == original_cards, "unchanged refresh reuses every 3D card")
	var pack: Array[Dictionary] = []
	for index in range(5):
		pack.append(CardData.create_instance(ids[index], 1, [], true))
	var notifications: Array = []
	var on_changed := func(changed: Array[String]) -> void: notifications.append(changed.duplicate())
	CollectionManager.collection_changed.connect(on_changed)
	var saves_before := int(CollectionManager.get("save_attempts"))
	started = Time.get_ticks_usec()
	if baseline:
		for instance: Dictionary in pack:
			CollectionManager.add_card_instance(instance)
	else:
		var batch: Dictionary = CollectionManager.add_card_instances(pack)
		var added: Array = batch["instances"]
		check(added.size() == 5, "batch stores all five exact rolled instances")
	print("BENCH collect_five_ms=", (Time.get_ticks_usec() - started) / 1000.0)
	started = Time.get_ticks_usec()
	screen.refresh_collection()
	print("BENCH acquired_refresh_ms=", (Time.get_ticks_usec() - started) / 1000.0)
	if not baseline:
		check(notifications.size() == 1 and notifications[0].size() == 5, "one pack publishes one change notification")
		check(int(CollectionManager.get("save_attempts")) == saves_before + 1, "one pack writes one collection snapshot")
		check(screen._base_positions.keys() == original_cards, "additional copies preserve all collection nodes")
		var replay: Dictionary = CollectionManager.add_card_instances(pack)
		check(replay["success"] and replay["instances"].is_empty() and notifications.size() == 1, "replaying a collected pack is a successful no-op without another notification")
		var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CollectionManager.SAVE_PATH))
		check(saved.instances.size() == 5005, "all awarded copies are persisted before the batch returns")
		var display: Dictionary = CollectionManager.get_display_cards(ids)
		check(ids.all(func(card_id: String) -> bool: return display[card_id] == CollectionManager.get_display_card(card_id)), "bulk display preserves Holo selection for every card type")
		var returned: Dictionary = display[ids[0]]
		returned["is_holo"] = false
		check(CardData.is_holo(CollectionManager.get_display_card(ids[0])), "bulk display dictionaries cannot change saved Holo flags")
		var copies := CollectionManager.get_deck_card_data([ids[0], ids[0], ids[0]])
		check(copies.size() == 3 and copies[0] == CollectionManager.get_display_card(ids[0], 0) and copies[1] == CollectionManager.get_display_card(ids[0], 1) and copies[2] == CollectionManager.get_display_card(ids[0], 2), "deck occurrences retain distinct copies in Holo-first acquisition order")
		var before_failure := CollectionManager.collection.duplicate(true)
		var saved_bytes := FileAccess.get_file_as_bytes(CollectionManager.SAVE_PATH)
		var temporary_path := CollectionManager.SAVE_PATH + ".tmp"
		check(DirAccess.make_dir_absolute(temporary_path) == OK, "failure fixture blocks the temporary save destination")
		var retry_pack := [CardData.create_instance(ids[0]), CardData.create_instance(ids[1])]
		var failed: Dictionary = CollectionManager.add_card_instances(retry_pack)
		check(not failed["success"] and failed["instances"].is_empty(), "a failed batch awards no cards and reports the storage failure")
		check(CollectionManager.collection == before_failure and FileAccess.get_file_as_bytes(CollectionManager.SAVE_PATH) == saved_bytes and notifications.size() == 1, "a failed save preserves ownership, discoveries, file contents and notifications")
		DirAccess.remove_absolute(temporary_path)
		check(CollectionManager.add_card_instances(retry_pack)["instances"].size() == 2, "retry stores the original rolled copies once after storage recovers")
		await _check_incremental_changes(screen, original_cards)
	CollectionManager.collection_changed.disconnect(on_changed)
	screen.queue_free()
	await get_tree().process_frame
	print("COLLECTION_PERFORMANCE_TESTS: " + ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)


func _check_incremental_changes(screen: CollectionScreen, original_cards: Array) -> void:
	screen.row_scroll_duration = 0.01
	screen._scroll_row("common", -1)
	await get_tree().create_timer(0.03).timeout
	var scroll_offset: float = screen._row_scroll_offsets.common
	var existing_pose: Transform3D = (screen._row_cards.common[0] as Card3D).transform
	CollectionManager.add_card_instances([CardData.create_instance("usb_stick")])
	screen.refresh_collection()
	check(original_cards.all(func(card: Card3D) -> bool: return screen._base_positions.has(card)) and screen._row_cards.secret.size() == 1, "a new card type appends without rebuilding existing types")
	check(is_equal_approx(screen._row_scroll_offsets.common, scroll_offset) and (screen._row_cards.common[0] as Card3D).transform.is_equal_approx(existing_pose), "acquisition preserves the row scroll offset and existing card pose")
	var removed: Card3D = screen._row_cards.common.back()
	var removed_id := str(removed.card_data.id)
	CollectionManager.collection.cards.erase(removed_id)
	CollectionManager.collection.instances = CollectionManager.collection.instances.filter(func(instance: Dictionary) -> bool: return instance.card_id != removed_id)
	screen.refresh_collection()
	check(not screen._base_positions.has(removed) and screen._row_cards.common.has(original_cards.filter(func(card: Card3D) -> bool: return str(card.card_data.id) != removed_id and screen._card_rarities.get(card) == "common")[0]), "losing the last copy removes only that card's node")
	await get_tree().process_frame
