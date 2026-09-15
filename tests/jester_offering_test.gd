extends Node

class FailingCollection extends "res://scripts/autoload/CollectionManager.gd":
	var refuse_saves := false
	func _save_collection_snapshot(snapshot: Dictionary, suffix: String = ".tmp") -> bool:
		return false if refuse_saves else super._save_collection_snapshot(snapshot, suffix)

var checks := 0
var failures := 0
var changes: Array = []


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func _reset() -> void:
	CollectionManager.clear_profile_state()
	DeckManager.clear_profile_state()
	CardUpgradeManager.clear_profile_state()
	CollectionManager.save_collection()
	changes.clear()


func _add(card_id: String, identity: String, holo: bool = false, level: int = 1) -> Dictionary:
	return CollectionManager.add_card_instance({"card_id": card_id, "instance_id": identity, "is_holo": holo, "level": level, "effects": []})


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/") or not str(SaveSlots.SAVE_ROOT).begins_with("res://test-user/"):
		push_error("Run jester_offering_test using the isolated match-feature runner.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	CollectionManager.collection_changed.connect(func(ids: Array[String]): changes.append(ids.duplicate()))
	_check_candidates_and_protection()
	_check_atomic_completion()
	_check_discovery_reward_pool()
	_check_holo_only()
	_check_save_failures()
	_check_slots()
	print("JESTER_OFFERING_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _check_candidates_and_protection() -> void:
	_reset()
	check(CollectionManager.get_jester_offering_state() == {"offered": [], "completed": false, "reward_instance": {}}, "new profile starts with neither grave offered and no reward")
	check(not CollectionManager.get_jester_offering_candidate("chick")["ok"], "missing Chick has no sacrifice candidate")
	_add("chick", "candidate-holo", true, 4)
	_add("chick", "candidate-normal", false, 3)
	_add("harald", "candidate-harald")
	CardUpgradeManager.upgrades["chick"] = {"attack_bonus": 3, "health_bonus": 4, "effects": [{"type":"regeneration","value":3}], "removed_base_effect_indices": []}
	var upgrades_before := CardUpgradeManager.upgrades.duplicate(true)
	var candidate := CollectionManager.get_jester_offering_candidate("chick")
	var data: Dictionary = candidate["card_data"]
	var base := CardDatabase.get_card("chick")
	check(candidate["ok"] and candidate["instance"]["instance_id"] == "candidate-normal" and not CardData.is_holo(data), "free normal copy is preferred even when a Holo was acquired first")
	check(data["attack"] == int(base["attack"]) + 3 and data["defense"] == int(base["defense"]) + 4 and data["instance_id"] == "candidate-normal" and data["level"] == 3, "confirmation receives upgraded stats and the precise offered copy's identity and level")
	candidate["instance"]["level"] = 999
	candidate["card_data"]["attack"] = 999
	check(CollectionManager.get_instances_for_card("chick")[1]["level"] == 3 and CardUpgradeManager.upgrades == upgrades_before, "preview dictionaries are detached and cannot change owned copies or upgrades")
	_add("starting_hand_1", "candidate-hand")
	DeckManager.battle_deck.assign(["chick"])
	DeckManager.deck_instance_ids.assign(["candidate-normal"])
	DeckManager.starting_deck_indices.assign([0])
	DeckManager.save_deck()
	var deck_file := FileAccess.get_file_as_string(DeckManager.SAVE_PATH)
	var collection_before := CollectionManager.collection.duplicate(true)
	changes.clear()
	check(not CollectionManager.offer_jester_card("chick", "candidate-normal")["ok"], "an exact copy added to the starting hand after preview is protected at confirmation")
	check(CollectionManager.get_jester_offering_candidate("chick")["instance"]["instance_id"] == "candidate-holo", "a free Holo remains selectable while the normal copy is protected")
	seed(781941)
	var next_random := randi()
	seed(781941)
	check(not CollectionManager.offer_jester_card("corpse", "candidate-normal")["ok"] and not CollectionManager.offer_jester_card("harald", "candidate-normal")["ok"] and not CollectionManager.offer_jester_card("chick", "missing-copy")["ok"], "unsupported graves, wrong card identity and stale copies are rejected")
	check(CollectionManager.collection == collection_before and changes.is_empty() and randi() == next_random, "rejected requests consume no cards, emit no award signal and do not roll a reward")
	check(FileAccess.get_file_as_string(DeckManager.SAVE_PATH) == deck_file and DeckManager.deck_instance_ids == ["candidate-normal"] and DeckManager.starting_deck_indices == [0], "candidate lookup and rejection never rewrite or alter the saved deck or starting hand")
	DeckManager.deck_instance_ids.clear()
	DeckManager.starting_deck_indices.clear()
	check(CollectionManager.get_jester_offering_candidate("chick")["instance"]["instance_id"] == "candidate-normal" and DeckManager.deck_instance_ids == ["candidate-holo"], "legacy deck copy resolution protects its Holo-first binding before choosing a sacrifice")
	check(CardUpgradeManager.upgrades == upgrades_before, "all offering previews preserve type upgrades byte for byte")


func _check_atomic_completion() -> void:
	_reset()
	_add("chick", "first-chick")
	_add("chick", "spare-chick")
	_add("harald", "second-harald")
	var fusion_ids: Array[String] = []
	for index in 5:
		var identity := "listener-corpse-%d" % index
		_add("corpse", identity)
		fusion_ids.append(identity)
	CardUpgradeManager.upgrades["harald"] = {"attack_bonus": 2, "health_bonus": 1, "effects": [], "effect_roll_count": 4}
	var upgrades_before := CardUpgradeManager.upgrades.duplicate(true)
	var nested: Array[Dictionary] = []
	var nested_fusions: Array[Dictionary] = []
	var saved_at_signal: Array[Dictionary] = []
	var listener := func(_ids: Array[String]):
		saved_at_signal.append(JSON.parse_string(FileAccess.get_file_as_string(CollectionManager.SAVE_PATH)))
		nested.append(CollectionManager.offer_jester_card("harald", "second-harald"))
		nested_fusions.append(CollectionManager.fuse_card_instances(fusion_ids))
	CollectionManager.collection_changed.connect(listener)
	changes.clear()
	var first := CollectionManager.offer_jester_card("chick", "first-chick")
	check(first["ok"] and not first["completed"] and first["instance"]["instance_id"] == "first-chick" and first["reward_instance"].is_empty(), "the first grave consumes the confirmed copy without awarding a Secret early")
	check(CollectionManager.get_amount("chick") == 1 and CollectionManager.get_amount("harald") == 1 and CollectionManager.get_jester_offering_state()["offered"] == ["chick"], "one exact Chick is removed while the spare and Harald remain")
	check(changes == [["chick"]] and nested.size() == 1 and not nested[0]["ok"], "a synchronous first-offer listener cannot secretly submit the second sacrifice")
	check(nested_fusions.size() == 1 and not nested_fusions[0]["ok"] and CollectionManager.get_amount("corpse") == 5, "offering notification also rejects a reentrant fusion of otherwise eligible cards")
	check(saved_at_signal[0]["metadata"]["jester_offering"]["offered"] == ["chick"] and int(saved_at_signal[0]["cards"]["chick"]) == 1, "observers see first-offer consumption and progress already saved together")
	CollectionManager.collection_changed.disconnect(listener)
	CollectionManager.reload_profile()
	check(CollectionManager.get_jester_offering_state()["offered"] == ["chick"] and not CollectionManager.get_jester_offering_state()["completed"] and not CollectionManager.get_jester_offering_candidate("chick")["ok"], "partial progress survives reload and cannot consume another Chick")
	changes.clear()
	nested.clear()
	nested_fusions.clear()
	saved_at_signal.clear()
	CollectionManager.collection_changed.connect(listener)
	var second := CollectionManager.offer_jester_card("harald", "second-harald")
	CollectionManager.collection_changed.disconnect(listener)
	var reward: Dictionary = second["reward_instance"]
	var reward_id := str(reward.get("card_id", ""))
	check(second["ok"] and second["completed"] and reward_id in CollectionManager.PROP_SECRET_CARD_IDS and second["reward_card_data"].get("rarity") == "secret", "the second grave immediately grants one existing eligible Secret combat card")
	check(CollectionManager.get_amount("harald") == 0 and CollectionManager.get_amount("chick") == 1 and _prop_secret_count(CollectionManager) == 1, "final atomic replacement consumes one Harald and creates exactly one reward")
	check(changes == [["harald", reward_id]] and nested.size() == 1 and not nested[0]["ok"], "completion emits one combined change and remains guarded through reentrant listeners")
	var committed: Dictionary = saved_at_signal[0]
	check(committed["metadata"]["jester_offering"]["completed"] == true and not committed["cards"].has("harald") and int(committed["cards"].get(reward_id, 0)) == 1 and committed["metadata"]["jester_offering"]["reward_instance"]["instance_id"] == reward["instance_id"], "the persisted completion contains both consumption and the exact granted reward before notification")
	var before := CollectionManager.collection.duplicate(true)
	changes.clear()
	check(not CollectionManager.offer_jester_card("harald", "second-harald")["ok"] and not CollectionManager.offer_jester_card("chick", "spare-chick")["ok"] and CollectionManager.collection == before and changes.is_empty(), "duplicate clicks and spare copies cannot farm a completed offering")
	CollectionManager.reload_profile()
	var state := CollectionManager.get_jester_offering_state()
	check(state["completed"] and state["offered"] == ["chick", "harald"] and state["reward_instance"]["instance_id"] == reward["instance_id"] and CollectionManager.get_amount(reward_id) == 1, "completed progress and its original reward survive reload without granting again")
	state["reward_instance"]["instance_id"] = "tampered-preview"
	check(CollectionManager.get_jester_offering_state()["reward_instance"]["instance_id"] == reward["instance_id"] and CardUpgradeManager.upgrades == upgrades_before, "state payloads are detached and both sacrifices leave all upgrades unchanged")


func _prop_secret_count(manager: Node) -> int:
	var count := 0
	for card_id: String in CollectionManager.PROP_SECRET_CARD_IDS:
		count += manager.get_amount(card_id)
	return count


func _check_discovery_reward_pool() -> void:
	var original_cards: Array[Dictionary] = CardDatabase.cards.duplicate(true)
	for card_id: String in CollectionManager.PROP_SECRET_CARD_IDS:
		_reset()
		_add("chick", "pool-chick")
		_add("harald", "pool-harald")
		CardDatabase.cards.assign(original_cards.filter(func(card: Dictionary): return card.get("rarity") != "secret" or card.get("id") == card_id))
		check(CardDatabase.get_random_card_by_rarity("secret").is_empty(), card_id + " stays excluded from random rewards during the Jester quest")
		CollectionManager.offer_jester_card("chick", "pool-chick")
		var result := CollectionManager.offer_jester_card("harald", "pool-harald")
		check(result.get("ok", false) and str(result.get("reward_instance", {}).get("card_id", "")) == card_id and _prop_secret_count(CollectionManager) == 1, "Jester can explicitly grant " + card_id + " despite its discovery-only random flag")
		CollectionManager.reload_profile()
		var random := RandomNumberGenerator.new()
		random.seed = 827361
		var random_state := random.state
		check(CollectionManager.has_discovered_card(card_id) and CollectionManager.discover_prop_secret(card_id, random).is_empty() and random.state == random_state and CollectionManager.get_amount(card_id) == 1, "saved Jester reward prevents a duplicate table discovery for " + card_id)
	CardDatabase.cards = original_cards


func _check_holo_only() -> void:
	_reset()
	_add("chick", "only-holo", true, 5)
	var candidate := CollectionManager.get_jester_offering_candidate("chick")
	check(candidate["ok"] and CardData.is_holo(candidate["card_data"]) and candidate["instance"]["instance_id"] == "only-holo", "a player's only free Holo can be offered explicitly and is clearly identified")
	DeckManager.battle_deck.assign(["chick"])
	DeckManager.deck_instance_ids.assign(["only-holo"])
	check(not CollectionManager.get_jester_offering_candidate("chick")["ok"] and not CollectionManager.offer_jester_card("chick", "only-holo")["ok"], "an only-Holo deck copy remains protected")
	DeckManager.clear_profile_state()
	var result := CollectionManager.offer_jester_card("chick", "only-holo")
	check(result["ok"] and CardData.is_holo(result["card_data"]) and result["card_data"]["level"] == 5 and CollectionManager.get_amount("chick") == 0, "confirming the free Holo consumes that exact copy without substituting another")


func _check_save_failures() -> void:
	_reset()
	_add("chick", "failure-chick")
	_add("harald", "failure-harald")
	var failing := FailingCollection.new()
	add_child(failing)
	var notifications: Array = []
	failing.collection_changed.connect(func(ids: Array[String]): notifications.append(ids))
	failing.refuse_saves = true
	var before := failing.collection.duplicate(true)
	var file_before := FileAccess.get_file_as_string(failing.SAVE_PATH)
	check(not failing.offer_jester_card("chick", "failure-chick")["ok"] and failing.collection == before and FileAccess.get_file_as_string(failing.SAVE_PATH) == file_before and notifications.is_empty(), "failed first-offer save rolls back every card, metadata field and notification")
	failing.refuse_saves = false
	check(failing.offer_jester_card("chick", "failure-chick")["ok"], "a failed transaction releases its guard so the same copy can be retried")
	before = failing.collection.duplicate(true)
	file_before = FileAccess.get_file_as_string(failing.SAVE_PATH)
	notifications.clear()
	var original_cards := CardDatabase.cards.duplicate(true)
	CardDatabase.cards.assign(original_cards.filter(func(card: Dictionary): return str(card.get("rarity", "")) != "secret"))
	check(not failing.offer_jester_card("harald", "failure-harald")["ok"] and failing.collection == before and notifications.is_empty(), "an empty eligible Secret pool preserves the second card and partial progress")
	CardDatabase.cards = original_cards
	failing.refuse_saves = true
	check(not failing.offer_jester_card("harald", "failure-harald")["ok"] and failing.collection == before and FileAccess.get_file_as_string(failing.SAVE_PATH) == file_before and notifications.is_empty(), "failed final save grants no reward and preserves the offered Harald and partial progress")
	failing.refuse_saves = false
	var completed := failing.offer_jester_card("harald", "failure-harald")
	check(completed["ok"] and completed["completed"] and _prop_secret_count(failing) == 1 and notifications.size() == 1, "retry after final-save failure atomically awards exactly once")
	failing.free()
	CollectionManager.reload_profile()


func _check_slots() -> void:
	check(SaveSlots.select_slot(1) == OK and SaveSlots.reset_slot(1) == OK, "slot-one fixture uses the public profile controller")
	_add("chick", "slot-one-chick")
	_add("harald", "slot-one-harald")
	check(CollectionManager.offer_jester_card("chick", "slot-one-chick")["ok"], "slot one can persist a partial offering")
	check(SaveSlots.reset_slot(2) == OK and SaveSlots.select_slot(2) == OK and CollectionManager.get_jester_offering_state()["offered"].is_empty(), "slot two starts without inheriting slot one's grave progress")
	_add("chick", "slot-two-chick")
	_add("harald", "slot-two-harald")
	CollectionManager.offer_jester_card("harald", "slot-two-harald")
	var completed := CollectionManager.offer_jester_card("chick", "slot-two-chick")
	check(completed["ok"] and completed["completed"], "the graves accept either order and award independently in slot two")
	var second_reward_id: String = completed["reward_instance"]["instance_id"]
	check(SaveSlots.select_slot(1) == OK and CollectionManager.get_jester_offering_state()["offered"] == ["chick"] and CollectionManager.get_amount("harald") == 1 and _prop_secret_count(CollectionManager) == 0, "returning to slot one restores only its own partial progress and remaining card")
	var first_completed := CollectionManager.offer_jester_card("harald", "slot-one-harald")
	check(first_completed["ok"] and first_completed["completed"] and first_completed["reward_instance"]["instance_id"] != second_reward_id, "each save slot may earn one distinct reward through its own two sacrifices")
	check(SaveSlots.select_slot(2) == OK and CollectionManager.get_jester_offering_state()["reward_instance"]["instance_id"] == second_reward_id and _prop_secret_count(CollectionManager) == 1, "reopening a completed slot restores its original reward without a second grant")
