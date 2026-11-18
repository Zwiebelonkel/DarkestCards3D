extends Node

var checks := 0
var failures := 0
var changes: Array = []
var serial := 0


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Use the isolated match-feature runner to protect player saves.")
		get_tree().quit(1)
		return
	CollectionManager.collection_changed.connect(func(ids: Array[String]): changes.append(ids.duplicate()))
	_reset()
	var tiers := CollectionManager.FUSION_RARITIES
	for index in range(tiers.size() - 1):
		check(CollectionManager.get_next_fusion_rarity(tiers[index]) == tiers[index + 1], "fusion advances exactly one rarity: " + tiers[index])
	check(CollectionManager.get_next_fusion_rarity("exotic").is_empty() and CollectionManager.get_next_fusion_rarity("invalid").is_empty(), "highest and unknown rarities have no upgrade")
	check(CollectionManager.get_next_fusion_rarity(" COMMON ") == "uncommon", "rarity normalization matches collection data")
	var common_ids := _add("corpse", 6)
	var selected: Array = common_ids.slice(0, 5)
	var before := CollectionManager.collection.duplicate(true)
	seed(371809)
	var next_random := randi()
	seed(371809)
	check(not CollectionManager.fuse_card_instances(selected.slice(0, 4))["ok"], "fewer than five copies cannot fuse")
	check(not CollectionManager.fuse_card_instances(common_ids)["ok"], "more than five copies cannot fuse")
	check(not CollectionManager.fuse_card_instances([selected[0], selected[0], selected[1], selected[2], selected[3]])["ok"], "the same physical copy cannot be selected twice")
	check(not CollectionManager.fuse_card_instances([selected[0], selected[1], selected[2], selected[3], "missing"])["ok"], "unowned copies cannot be consumed")
	check(not CollectionManager.fuse_card_instances([selected[0], selected[1], selected[2], selected[3], 7])["ok"], "instance identities are validated without coercion")
	check(CollectionManager.collection == before and changes.is_empty() and randi() == next_random, "invalid requests preserve cards, notifications and reward randomness")
	var uncommon := _add("chicken", 1)
	check(not CollectionManager.fuse_card_instances([selected[0], selected[1], selected[2], selected[3], uncommon[0]])["ok"], "mixed rarities cannot fuse")
	var holo := _add("bat", 1, true)
	DeckManager.battle_deck = ["bat", "corpse"]
	DeckManager.deck_instance_ids = [holo[0], selected[0]]
	check(not _candidate(holo[0])["eligible"] and not _candidate(selected[0])["eligible"], "exact deck instances are protected, including a Holo")
	check(_candidate(common_ids[5])["eligible"], "spare copies of a deck card remain eligible")
	check(not CollectionManager.fuse_card_instances(selected)["ok"], "backend revalidates deck membership at fusion")
	DeckManager.battle_deck = ["corpse"]
	DeckManager.deck_instance_ids.clear()
	check(not _candidate(selected[0])["eligible"] and DeckManager.deck_instance_ids == [selected[0]], "legacy deck bindings are resolved before offering sacrificial cards")
	DeckManager.battle_deck.clear()
	DeckManager.deck_instance_ids.clear()
	var special := _add("clicker", 1)
	var secret := _add("slot_room_key", 1)
	var highest := _add("red_light_figure", 1)
	for instance_id in [special[0], secret[0], highest[0]]:
		var entry := _candidate(instance_id)
		check(not entry["eligible"] and not str(entry["disabled_reason"]).is_empty(), "protected card remains visible with an explanation: " + str(entry["card_id"]))
		check(not CollectionManager.fuse_card_instances([selected[0], selected[1], selected[2], selected[3], instance_id])["ok"], "protected card cannot be consumed through the API")
	var saved_cards := CardDatabase.cards.duplicate(true)
	var saved_by_id := CardDatabase.cards_by_id.duplicate(true)
	for category in ["event", "combat"]:
		var fixture := {"id": "fusion_protected_" + category, "rarity": "common", "category": category, "random_reward": false}
		CardDatabase.cards.append(fixture)
		CardDatabase.cards_by_id[fixture["id"]] = fixture
		# Event cards cannot be acquired anymore; inject a legacy/imported copy
		# to keep testing the forge's independent protection boundary.
		var protected := CardData.create_instance(str(fixture["id"]))
		CollectionManager.collection["instances"].append(protected)
		CollectionManager.collection["cards"][str(fixture["id"])] = 1
		var candidate := _candidate(str(protected["instance_id"]))
		if category == "event":
			check(candidate.is_empty(), "legacy event copies are excluded from the collectible inventory before fusion")
		else:
			check(not candidate.is_empty() and not candidate["eligible"], "secret combat inputs remain protected")
	var all_candidates := CollectionManager.get_fusion_candidates()
	check(all_candidates.size() == CollectionManager.get_card_instances().size(), "the forge can show every owned copy, including unavailable cards")
	var holo_entry := _candidate(holo[0])
	check(CardData.is_holo(holo_entry["card_data"]) and holo_entry["card_data"]["instance_id"] == holo[0], "candidate display preserves exact Holo metadata")
	holo_entry["instance"]["level"] = 900
	holo_entry["card_data"]["name"] = "modified"
	check(CollectionManager.get_instances_for_card("bat")[0]["level"] == 1 and CardDatabase.get_card("bat")["name"] != "modified", "UI candidate dictionaries cannot mutate collection or database")
	for card: Dictionary in CollectionManager.get_fusion_pool("common"):
		check(card["rarity"] == "uncommon" and CardData.is_combat_card(card) and card.get("random_reward", true) != false, "reward pool contains only obtainable next-tier combat cards")
	var secret_reward := {"id": "fusion_secret_reward", "rarity": "uncommon", "random_reward": false}
	CardDatabase.cards = [secret_reward, CardDatabase.get_card("clicker_upgrade")]
	CardDatabase.cards_by_id["fusion_secret_reward"] = secret_reward
	check(CollectionManager.get_fusion_pool("common").is_empty(), "secret and special cards cannot become random fusion rewards")
	before = CollectionManager.collection.duplicate(true)
	check(not CollectionManager.fuse_card_instances(selected)["ok"] and CollectionManager.collection == before, "empty next-tier pool preserves every input instead of falling back to another rarity")
	CardDatabase.cards = saved_cards
	CardDatabase.cards_by_id = saved_by_id
	_reset()
	selected = _add("corpse", 2)
	selected.append_array(_add("bat", 2))
	selected.append_array(_add("joe", 1))
	var retained := _add("corpse", 1, true)
	_add("starting_hand_1", 1)
	DeckManager.battle_deck = ["corpse"]
	DeckManager.deck_instance_ids = [retained[0]]
	DeckManager.starting_deck_indices = [0]
	DeckManager.save_deck()
	CollectionManager.collection["metadata"] = {"slot_room_unlocked": true, "unrelated": "preserved"}
	CollectionManager.save_collection()
	before = CollectionManager.collection.duplicate(true)
	var before_file := FileAccess.get_file_as_string(CollectionManager.SAVE_PATH)
	var temporary_path := str(CollectionManager.SAVE_PATH) + ".fusion.tmp"
	check(DirAccess.make_dir_absolute(temporary_path) == OK, "fixture can force an unwritable temporary save")
	var failed := CollectionManager.fuse_card_instances(selected)
	check(not failed["ok"] and CollectionManager.collection == before and changes.is_empty(), "save failure rolls back both consumed inputs and output without notifications")
	check(FileAccess.get_file_as_string(CollectionManager.SAVE_PATH) == before_file, "failed fusion preserves the previously committed save byte for byte")
	check(DirAccess.remove_absolute(temporary_path) == OK, "fixture restores the save location after injected failure")
	var coins_before := GameCurrency.get_coin_cents()
	var result := CollectionManager.fuse_card_instances(selected)
	check(result["ok"] and result["next_rarity"] == "uncommon", "five copies of different card types but identical rarity produce one higher card")
	check(CollectionManager.get_card_instances().size() == before["instances"].size() - 4 and GameCurrency.get_coin_cents() == coins_before, "fusion exchanges five for one without a currency fee")
	check(CollectionManager.get_instances_for_card("corpse").size() == 1 and CollectionManager.get_instances_for_card("corpse")[0]["instance_id"] == retained[0], "only the explicitly selected copies disappear; the retained deck Holo survives")
	check(CollectionManager.get_amount("bat") == 0 and not CollectionManager.get_owned_cards().has("bat") and CollectionManager.get_amount(str(result["instance"]["card_id"])) == 1, "card quantity index matches removed and added instances")
	check(changes.size() == 1 and changes[0].has("corpse") and changes[0].has("bat") and changes[0].has("joe") and changes[0].has(result["instance"]["card_id"]), "one collection notification includes every changed card type")
	check(result["instance"]["level"] == 1 and result["instance"].has("is_holo") and result["instance"]["instance_id"] == result["card_data"]["instance_id"], "reward has fresh normal instance metadata and matching reveal data")
	check(DeckManager.get_deck_cards() == ["corpse"] and DeckManager.deck_instance_ids == retained and DeckManager.get_starting_deck_indices() == [0], "saved deck and selected starting hand keep their exact owned copy")
	var committed := CollectionManager.collection.duplicate(true)
	check(not CollectionManager.fuse_card_instances(selected)["ok"] and CollectionManager.collection == committed and changes.size() == 1, "duplicate strike callback cannot consume inputs or grant a reward twice")
	CollectionManager.load_collection()
	# JSON reload normalizes integers to floats; compare persisted values with
	# the same normalization while retaining every identity and effect value.
	check(CollectionManager.collection == JSON.parse_string(JSON.stringify(committed)) and CollectionManager.is_slot_room_unlocked() and CollectionManager.collection["metadata"]["unrelated"] == "preserved", "all five removals, exact reward and unrelated metadata survive reload together")
	check(not FileAccess.file_exists(temporary_path), "successful fusion leaves no pending temporary save")
	for index in range(1, tiers.size() - 1):
		_reset()
		var input_pool := CardDatabase.get_cards_by_rarity(tiers[index])
		var input_id := ""
		for card: Dictionary in input_pool:
			if CardData.is_combat_card(card):
				input_id = str(card["id"])
				break
		var tier_result := CollectionManager.fuse_card_instances(_add(input_id, 5))
		check(tier_result["ok"] and tier_result["card_data"]["rarity"] == tiers[index + 1], "real reward uses immediately next rarity for " + tiers[index])
	print("CARD_FUSION_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _reset() -> void:
	CollectionManager.collection = {"cards": {}, "instances": []}
	DeckManager.battle_deck.clear()
	DeckManager.deck_instance_ids.clear()
	DeckManager.starting_deck_indices.clear()
	CollectionManager.save_collection()
	changes.clear()


func _add(card_id: String, amount: int, holo: bool = false) -> Array[String]:
	var ids: Array[String] = []
	for index in range(amount):
		var instance := CardData.create_instance(card_id, 1, [], holo)
		serial += 1
		instance["instance_id"] = "fusion_test_%d" % serial
		var stored := CollectionManager._store_card_instance(instance)
		check(not stored.is_empty(), "fixture owns " + card_id)
		if not stored.is_empty():
			ids.append(str(stored["instance_id"]))
	return ids


func _candidate(instance_id: String) -> Dictionary:
	for entry: Dictionary in CollectionManager.get_fusion_candidates():
		if entry["instance_id"] == instance_id:
			return entry
	return {}
