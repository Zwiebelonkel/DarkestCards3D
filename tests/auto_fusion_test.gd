extends "res://tests/card_fusion_test.gd"

var nested_results: Array = []
var try_nested := false


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		push_error("Run only in an isolated project.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	CollectionManager.collection_changed.connect(func(ids: Array[String]):
		changes.append(ids.duplicate())
		if try_nested:
			nested_results.append(CollectionManager.auto_fuse_card_instances())
			nested_results.append(CollectionManager.fuse_card_instances([]))
	)
	_reset()
	var deck_copy := _add("corpse", 1, true)
	DeckManager.battle_deck = ["corpse"]
	DeckManager.deck_instance_ids = deck_copy.duplicate()
	DeckManager.starting_deck_indices = [0]
	var protected_ids := deck_copy.duplicate()
	protected_ids.append_array(_add("usb_stick", 1))
	protected_ids.append_array(_add("clicker", 1))
	protected_ids.append_array(_add("starting_hand_1", 1))
	protected_ids.append_array(_add("developer", 1))
	var protected: Array = []
	for identity: String in protected_ids:
		protected.append(_candidate(identity)["instance"].duplicate(true))
	_add_cascade(5)
	CollectionManager.collection["metadata"]["auto_test"] = "preserved"
	CollectionManager.save_collection()
	var coins_before := GameCurrency.get_coin_cents()
	try_nested = true
	var result := CollectionManager.auto_fuse_card_instances()
	try_nested = false
	check(result.get("ok", false) and int(result.get("fusion_count", 0)) == 6, "one Auto Fuse recursively advances through all six upgrade tiers")
	check(result["instances"].size() == 1 and CardDatabase.get_card(result["instances"][0]["card_id"])["rarity"] == "exotic", "recursion ends at Exotic and never generates a Secret")
	check(CollectionManager.get_card_instances().size() == protected_ids.size() + 1, "all eligible groups are consumed exactly once with one final reward")
	for instance: Dictionary in protected:
		check(_candidate(str(instance["instance_id"]))["instance"] == instance, "protected copy preserves its exact identity, Holo, level and effects")
	check(DeckManager.deck_instance_ids == deck_copy and DeckManager.battle_deck == ["corpse"] and DeckManager.starting_deck_indices == [0], "deck and starting-hand bindings remain unchanged")
	check(GameCurrency.get_coin_cents() == coins_before, "Auto Fuse charges no additional coins")
	check(changes.size() == 1 and nested_results.size() == 2 and not nested_results[0]["ok"] and not nested_results[1]["ok"], "only one final notification is emitted and reentrant fusion is rejected")
	for id: String in changes[0]:
		check(CollectionManager.has_discovered_card(id), "intermediate and final card discoveries survive recursive consumption")
	_check_counts()
	var committed := CollectionManager.collection.duplicate(true)
	CollectionManager.load_collection()
	check(CollectionManager.collection == JSON.parse_string(JSON.stringify(committed)), "entire cascade and unrelated metadata survive a reload")
	var saved := FileAccess.get_file_as_string(CollectionManager.SAVE_PATH)
	changes.clear()
	seed(724)
	var expected_random := randi()
	seed(724)
	result = CollectionManager.auto_fuse_card_instances()
	check(result["ok"] and result["fusion_count"] == 0 and result["instances"].is_empty(), "running again with no groups is a harmless no-op")
	check(changes.is_empty() and FileAccess.get_file_as_string(CollectionManager.SAVE_PATH) == saved and randi() == expected_random, "no-op cannot reroll, notify or rewrite the save")

	# Many outputs from one tier must be recursively consumed in the same run.
	_reset()
	_add("corpse", 125)
	result = CollectionManager.auto_fuse_card_instances()
	check(result["ok"] and result["fusion_count"] == 31 and CollectionManager.get_card_instances().size() == 1, "125 common copies recursively produce 25, then 5, then 1 reward")
	check(CardDatabase.get_card(result["instances"][0]["card_id"])["rarity"] == "epic", "recursive groups always advance exactly one rarity")
	_check_counts()

	for required in [4, 3]:
		_reset()
		_add("fusion_upgrade_1", 1)
		if required == 3:
			_add("fusion_upgrade_2", 1)
		_add_cascade(required)
		result = CollectionManager.auto_fuse_card_instances()
		check(CollectionManager.get_fusion_requirement() == required and result["fusion_count"] == 6 and result["instances"].size() == 1, "every recursive step honors fusion upgrade requirement %d" % required)
		check(CollectionManager.get_amount("fusion_upgrade_1") == 1 and (required != 3 or CollectionManager.get_amount("fusion_upgrade_2") == 1), "permanent fusion upgrades are never ingredients")
		_check_counts()

	_reset()
	_add("corpse", 26)
	DeckManager.battle_deck = ["corpse"]
	DeckManager.deck_instance_ids.clear()
	result = CollectionManager.auto_fuse_card_instances()
	check(result["fusion_count"] == 6 and CollectionManager.get_amount("corpse") == 1 and DeckManager.deck_instance_ids.size() == 1, "legacy decks reserve their exact copy before automatic selection")

	_reset()
	_add("corpse", 29, true)
	CollectionManager.save_collection()
	var before := CollectionManager.collection.duplicate(true)
	saved = FileAccess.get_file_as_string(CollectionManager.SAVE_PATH)
	var temporary := CollectionManager.SAVE_PATH + ".fusion.tmp"
	check(DirAccess.make_dir_absolute(temporary) == OK, "force the final atomic save to fail")
	result = CollectionManager.auto_fuse_card_instances()
	check(not result["ok"] and CollectionManager.collection == before and changes.is_empty(), "failed save keeps every original card across all planned recursive steps")
	check(FileAccess.get_file_as_string(CollectionManager.SAVE_PATH) == saved and not CollectionManager._fusion_in_progress, "failure preserves the committed save and releases the transaction lock")
	check(DirAccess.remove_absolute(temporary) == OK, "restore the save location")
	result = CollectionManager.auto_fuse_card_instances()
	check(result["ok"] and result["fusion_count"] == 6 and CollectionManager.get_amount("corpse") == 4, "retry consumes free Holos and keeps incomplete groups")
	_check_counts()

	_reset()
	_add("corpse", 5)
	var old_cards := CardDatabase.cards.duplicate(true)
	CardDatabase.cards = CardDatabase.cards.filter(func(card: Dictionary): return str(card.get("rarity", "")) != "uncommon")
	before = CollectionManager.collection.duplicate(true)
	result = CollectionManager.auto_fuse_card_instances()
	check(result["ok"] and result["fusion_count"] == 0 and CollectionManager.collection == before, "a missing next-tier pool never consumes inputs or skips a rarity")
	CardDatabase.cards = old_cards
	print("AUTO_FUSION_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _add_cascade(required: int) -> void:
	for index in range(CollectionManager.FUSION_RARITIES.size() - 1):
		var rarity: String = CollectionManager.FUSION_RARITIES[index]
		for card: Dictionary in CardDatabase.get_cards_by_rarity(rarity):
			if CardData.is_combat_card(card) and card.get("random_reward", true):
				_add(str(card["id"]), required if index == 0 else required - 1)
				break


func _check_counts() -> void:
	var amounts := {}
	var identities := {}
	for instance: Dictionary in CollectionManager.get_card_instances():
		var id := str(instance["card_id"])
		amounts[id] = int(amounts.get(id, 0)) + 1
		identities[str(instance["instance_id"])] = true
	check(amounts == CollectionManager.collection["cards"] and identities.size() == CollectionManager.get_card_instances().size(), "quantities match physical copies and every identity remains unique")
