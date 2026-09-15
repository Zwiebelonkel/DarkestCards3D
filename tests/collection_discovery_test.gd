extends Node

class FailingCollection extends "res://scripts/autoload/CollectionManager.gd":
	var refuse_saves := false
	var save_attempts := 0
	func _save_collection_snapshot(snapshot: Dictionary, suffix: String = ".tmp") -> bool:
		save_attempts += 1
		return false if refuse_saves else super._save_collection_snapshot(snapshot, suffix)

var checks := 0
var failures := 0


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


func _instance(card_id: String, identity: String) -> Dictionary:
	return {"card_id": card_id, "instance_id": identity, "is_holo": false, "level": 1, "effects": []}


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/") or not str(SaveSlots.SAVE_ROOT).begins_with("res://test-user/"):
		push_error("Run collection_discovery_test using the isolated match-feature runner.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	_check_read_only_and_migration()
	_check_acquisition_and_events()
	_check_event_boundaries()
	_check_seen_cards()
	_check_consumption_and_failures()
	_check_slots()
	print("COLLECTION_DISCOVERY_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _check_read_only_and_migration() -> void:
	_reset()
	check(CollectionManager.get_discovered_card_ids().is_empty(), "new profiles have no discovered cards")
	CollectionManager.collection = {"cards": {"corpse": 2, "bat": 0}, "instances": [], "metadata": {"jester_offering": {"offered": ["chick", "harald"], "completed": true, "reward_instance": _instance("developer", "old-reward")}}}
	var before := CollectionManager.collection.duplicate(true)
	var saved := FileAccess.get_file_as_string(CollectionManager.SAVE_PATH)
	seed(319458)
	var expected_random := randi()
	seed(319458)
	check(CollectionManager.has_discovered_card("corpse") and not CollectionManager.has_discovered_card("bat") and not CollectionManager.has_discovered_card("invalid"), "legacy ownership reveals positive counts without revealing absent cards")
	check(CollectionManager.get_discovered_card_ids() == ["chick", "corpse", "developer", "harald"], "old completed offerings recover consumed cards and their recorded reward")
	check(CollectionManager.is_card_new("corpse") and CollectionManager.is_card_new("chick") and not CollectionManager.is_card_new("bat") and not CollectionManager.is_card_new("invalid"), "legacy discoveries without hover history are new while undiscovered cards are not")
	var detached := CollectionManager.get_discovered_card_ids()
	detached.append("bat")
	check(not CollectionManager.has_discovered_card("bat") and CollectionManager.collection == before and FileAccess.get_file_as_string(CollectionManager.SAVE_PATH) == saved and randi() == expected_random, "discovery queries return detached values without changing state, save bytes, or RNG")
	check(CollectionManager.save_collection(), "ordinary saves persist legacy discovery migration")
	CollectionManager.collection["cards"].clear()
	CollectionManager.collection["instances"].clear()
	CollectionManager.collection["metadata"].erase("jester_offering")
	CollectionManager.save_collection()
	CollectionManager.reload_profile()
	check(CollectionManager.get_discovered_card_ids() == ["chick", "corpse", "developer", "harald"], "migrated discovery survives loss of all owned copies and old offering metadata")
	CollectionManager.collection = {"corpse": 1, "metadata": {"unrelated": true}}
	before = CollectionManager.collection.duplicate(true)
	check(CollectionManager.has_discovered_card("corpse") and CollectionManager.collection == before, "flat legacy collections are inspected without generating instances")


func _check_acquisition_and_events() -> void:
	_reset()
	var rolled := CollectionManager.roll_card_instance("corpse")
	check(not rolled.is_empty() and not CollectionManager.has_discovered_card("corpse"), "rolling or previewing a pack card alone does not discover it")
	var stored := CollectionManager.add_card_instance(rolled)
	check(not stored.is_empty() and CollectionManager.has_discovered_card("corpse"), "collecting the exact pack instance discovers its card")
	var before := CollectionManager.collection.duplicate(true)
	check(CollectionManager.add_card_instance(rolled).is_empty() and CollectionManager.collection == before, "duplicate pack callbacks cannot alter discovery or award another copy")
	check(not CollectionManager.add_card("bat").is_empty() and CollectionManager.has_discovered_card("bat"), "regular card awards record discovery")
	check(not CollectionManager.add_card_instance(_instance("clicker", "discovery-clicker")).is_empty() and CollectionManager.has_discovered_card("clicker"), "special-card acquisitions record discovery")
	var owned := CollectionManager.get_owned_cards()
	var instances := CollectionManager.get_card_instances()
	var notifications: Array = []
	var listener := func(ids: Array[String]): notifications.append(ids.duplicate())
	CollectionManager.collection_changed.connect(listener)
	check(CollectionManager.discover_cards(["steel", "block", "steel", "invalid", 3]) and not CollectionManager.has_discovered_card("steel") and not CollectionManager.has_discovered_card("block") and not CollectionManager.has_discovered_card("invalid"), "event batches and malformed IDs never create collectible discoveries")
	check(CollectionManager.get_owned_cards() == owned and CollectionManager.get_card_instances() == instances and notifications.is_empty(), "receiving match events leaves collectible inventory and notifications unchanged")
	var saved := FileAccess.get_file_as_string(CollectionManager.SAVE_PATH)
	check(CollectionManager.discover_cards(["block", "steel"]) and notifications.is_empty() and FileAccess.get_file_as_string(CollectionManager.SAVE_PATH) == saved, "event hands remain a silent no-op with unchanged save bytes")
	CollectionManager.collection_changed.disconnect(listener)
	CollectionManager.reload_profile()
	check(not CollectionManager.has_discovered_card("steel") and not CollectionManager.has_discovered_card("block") and CollectionManager.has_discovered_card("corpse") and CollectionManager.has_discovered_card("clicker"), "reload preserves collectible discovery while keeping events outside collection history")


func _check_event_boundaries() -> void:
	_reset()
	var baseline_profile := PlayerProfile.snapshot()
	var original_cards := CardDatabase.cards.duplicate(true)
	var original_by_id := CardDatabase.cards_by_id.duplicate(true)
	var typed_event := {"id": "fixture_event", "name": "Fixture event", "category": "event", "rarity": "common", "reward_weight": 1000000.0}
	var reserved_event := {"id": "steel", "name": "Legacy event", "rarity": "common", "reward_weight": 1000000.0}
	for card: Dictionary in [typed_event, reserved_event]:
		CardDatabase.cards.append(card)
		CardDatabase.cards_by_id[str(card["id"])] = card
	var before := CollectionManager.collection.duplicate(true)
	var saved := FileAccess.get_file_as_string(CollectionManager.SAVE_PATH)
	seed(45310)
	var expected_random := randi()
	seed(45310)
	var event_ids: Array[String] = ["fixture_event"]
	for event: Dictionary in EventDeck.definitions():
		event_ids.append(str(event["id"]))
	for card_id: String in event_ids:
		check(not CollectionManager.can_obtain_card(card_id) and CollectionManager.roll_card_instance(card_id).is_empty() and CollectionManager.add_card(card_id).is_empty() and CollectionManager.add_card_instance(_instance(card_id, "excluded-" + card_id)).is_empty(), "event acquisition is rejected through every collection entry point: " + card_id)
		check(not CollectionManager.has_discovered_card(card_id) and not CollectionManager.is_card_new(card_id) and not CollectionManager.mark_card_seen(card_id), "events never enter discovery or NEW acknowledgement: " + card_id)
	check(CollectionManager.collection == before and FileAccess.get_file_as_string(CollectionManager.SAVE_PATH) == saved and randi() == expected_random, "rejected event acquisitions and discovery reads preserve state, save bytes, and RNG")
	check(not CardDatabase._is_random_reward(typed_event) and not CardDatabase._is_random_reward(reserved_event), "reward admission excludes category:event and reserved EventDeck IDs even without a category")
	var eligible := CardDatabase._get_eligible_rewards()
	check(not eligible.any(func(card: Dictionary): return CardDatabase.is_event_card(card)) and not CardDatabase.get_cards_by_rarity("common").any(func(card: Dictionary): return CardDatabase.is_event_card(card)), "pack and fixed-rarity reward pools exclude all event definitions")
	CardDatabase.cards.assign([typed_event, reserved_event])
	check(CardDatabase.get_random_card().is_empty() and CardDatabase.get_random_card_for_current_pack().is_empty() and CardDatabase.get_random_card_by_rarity("common").is_empty() and not CardDatabase.has_regular_pack_rewards(), "an event-only catalog cannot return a reward through any public random draw path")
	CardDatabase.cards.assign(original_cards)
	CardDatabase.cards.append(typed_event)
	CardDatabase.cards.append(reserved_event)
	CollectionManager.collection = {
		"cards": {"corpse": 1, "steel": 2, "fixture_event": 1},
		"instances": [_instance("corpse", "legacy-collectible"), _instance("steel", "legacy-steel"), _instance("fixture_event", "legacy-typed-event")],
		"metadata": {"discovered_cards": {"corpse": true, "steel": true, "fixture_event": true, "block": true}, "seen_cards": {"steel": true}},
	}
	CollectionManager.collection["instances"][1]["is_holo"] = true
	CollectionManager.collection["instances"][2]["is_holo"] = true
	check(CollectionManager.save_collection(), "legacy event ownership and hover metadata fixture is saved without deletion")
	saved = FileAccess.get_file_as_string(CollectionManager.SAVE_PATH)
	CollectionManager.reload_profile()
	before = CollectionManager.collection.duplicate(true)
	seed(911)
	expected_random = randi()
	seed(911)
	check(CollectionManager.get_discovered_card_ids() == ["corpse"] and not CollectionManager.has_discovered_card("steel") and not CollectionManager.has_discovered_card("block") and not CollectionManager.is_card_new("fixture_event"), "old event discovery and seen metadata cannot reveal cards or NEW labels")
	var visible_owned := CollectionManager.get_owned_cards()
	check(visible_owned.keys() == ["corpse"] and int(visible_owned.get("corpse", 0)) == 1 and CollectionManager.get_card_instances().size() == 1 and CollectionManager.get_amount("steel") == 0 and CollectionManager.get_instances_for_card("fixture_event").is_empty() and CollectionManager.get_display_card("steel").is_empty(), "legacy events are excluded from collectible counts, copies, and table display")
	DeckManager.battle_deck.assign(["steel", "fixture_event", "corpse"])
	DeckManager.deck_instance_ids.assign(["legacy-steel", "legacy-typed-event", "legacy-collectible"])
	var profile := PlayerProfile.snapshot()
	check(profile["collection_count"] == 1 and profile["combat_copies"] == 1 and profile["holo_collection_count"] == 0 and profile["deck_count"] == 1 and profile["holo_deck_count"] == 0 and profile["combat_catalog_count"] == baseline_profile["combat_catalog_count"] and profile["special_catalog_count"] == baseline_profile["special_catalog_count"], "profile counts exclude event ownership, Holo copies, saved deck entries, and catalog definitions")
	check(CollectionManager.discover_cards(event_ids) and not CollectionManager.mark_card_seen("block") and CollectionManager.collection == before and FileAccess.get_file_as_string(CollectionManager.SAVE_PATH) == saved and randi() == expected_random, "legacy event queries are read-only and never rewrite or remove old save metadata")
	DeckManager.clear_profile_state()
	CardDatabase.cards.assign(original_cards)
	CardDatabase.cards_by_id = original_by_id


func _check_seen_cards() -> void:
	_reset()
	CollectionManager.add_card_instance(_instance("corpse", "seen-corpse"))
	CollectionManager.discover_cards(["harald"])
	var tracker := FailingCollection.new()
	add_child(tracker)
	var seen_notifications: Array[String] = []
	var inventory_notifications: Array = []
	var published_after_save: Array[bool] = []
	tracker.card_seen.connect(func(card_id: String):
		seen_notifications.append(card_id)
		var saved_snapshot: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(tracker.SAVE_PATH))
		published_after_save.append(not tracker.is_card_new(card_id) and saved_snapshot.get("metadata", {}).get("seen_cards", {}).get(card_id, false) == true)
	)
	tracker.collection_changed.connect(func(ids: Array[String]): inventory_notifications.append(ids.duplicate()))
	check(tracker.is_card_new("corpse") and tracker.is_card_new("harald"), "new collectible types await their first collection hover")
	var before := tracker.collection.duplicate(true)
	var saved := FileAccess.get_file_as_string(tracker.SAVE_PATH)
	var attempts := tracker.save_attempts
	check(not tracker.mark_card_seen("bat") and not tracker.mark_card_seen("invalid") and not tracker.mark_card_seen(""), "unknown and undiscovered cards cannot be marked seen")
	check(tracker.collection == before and tracker.save_attempts == attempts and seen_notifications.is_empty() and inventory_notifications.is_empty() and FileAccess.get_file_as_string(tracker.SAVE_PATH) == saved, "invalid acknowledgements neither save nor publish a change")
	tracker.refuse_saves = true
	check(not tracker.mark_card_seen("corpse") and tracker.is_card_new("corpse") and tracker.collection == before and tracker.save_attempts == attempts + 1, "failed acknowledgement keeps the card new and all in-memory metadata unchanged")
	check(seen_notifications.is_empty() and inventory_notifications.is_empty() and FileAccess.get_file_as_string(tracker.SAVE_PATH) == saved, "failed acknowledgement keeps save bytes and both signals untouched")
	tracker.refuse_saves = false
	check(tracker.mark_card_seen("corpse") and not tracker.is_card_new("corpse") and tracker.is_card_new("harald"), "a successful hover acknowledges only its own card type")
	check(seen_notifications == ["corpse"] and published_after_save == [true] and inventory_notifications.is_empty(), "seen notification follows the durable save without refreshing the inventory")
	attempts = tracker.save_attempts
	saved = FileAccess.get_file_as_string(tracker.SAVE_PATH)
	check(tracker.mark_card_seen("corpse") and tracker.save_attempts == attempts and seen_notifications == ["corpse"] and FileAccess.get_file_as_string(tracker.SAVE_PATH) == saved, "repeated hover is a successful silent no-op without another save")
	tracker.free()
	CollectionManager.reload_profile()
	check(not CollectionManager.is_card_new("corpse") and CollectionManager.is_card_new("harald"), "seen and still-new card states survive profile reload")
	CollectionManager.add_card_instance(_instance("corpse", "seen-corpse-again"))
	check(not CollectionManager.is_card_new("corpse"), "obtaining another copy of a seen type does not restore its badge")
	check(CollectionManager.mark_card_seen("harald") and not CollectionManager.is_card_new("harald") and CollectionManager.get_amount("harald") == 0, "previously discovered collectible types can be acknowledged without remaining inventory copies")
	CollectionManager.reload_profile()
	check(not CollectionManager.is_card_new("harald"), "collectible acknowledgement is durable")


func _check_consumption_and_failures() -> void:
	_reset()
	var selected: Array[String] = []
	for index in 5:
		var identity := "discovery-fusion-%d" % index
		CollectionManager.add_card_instance(_instance("corpse", identity))
		selected.append(identity)
	var failing := FailingCollection.new()
	add_child(failing)
	check(failing.mark_card_seen("corpse"), "fusion fixture records the consumed type's first hover")
	failing.refuse_saves = true
	var before := failing.collection.duplicate(true)
	var saved := FileAccess.get_file_as_string(failing.SAVE_PATH)
	var notifications: Array = []
	failing.collection_changed.connect(func(ids: Array[String]): notifications.append(ids.duplicate()))
	check(not failing.discover_cards(["bat"]) and not failing.has_discovered_card("bat") and failing.collection == before and notifications.is_empty() and FileAccess.get_file_as_string(failing.SAVE_PATH) == saved, "failed collectible discovery writes reveal nothing and publish no change")
	check(not failing.fuse_card_instances(selected)["ok"] and failing.collection == before and failing.get_discovered_card_ids() == ["corpse"] and notifications.is_empty(), "failed fusion cannot discover its rolled reward or consume discovery inputs")
	failing.refuse_saves = false
	var fused := failing.fuse_card_instances(selected)
	var reward_id := str(fused.get("instance", {}).get("card_id", ""))
	check(fused["ok"] and failing.get_amount("corpse") == 0 and failing.has_discovered_card("corpse") and failing.has_discovered_card(reward_id), "successful fusion preserves a fully consumed type and discovers its reward")
	check(not failing.is_card_new("corpse") and failing.is_card_new(reward_id), "consumption retains acknowledgement while the new fusion reward awaits hover")
	failing.free()
	CollectionManager.reload_profile()
	check(CollectionManager.has_discovered_card("corpse") and CollectionManager.has_discovered_card(reward_id), "fusion input and reward discoveries are durable")
	CollectionManager.add_card_instance(_instance("corpse", "seen-after-consumption"))
	check(not CollectionManager.is_card_new("corpse"), "reacquiring a fully consumed seen type preserves its acknowledgement after reload")
	_reset()
	CollectionManager.add_card_instance(_instance("chick", "discovery-chick"))
	CollectionManager.add_card_instance(_instance("harald", "discovery-harald"))
	check(CollectionManager.offer_jester_card("chick", "discovery-chick")["ok"] and CollectionManager.get_amount("chick") == 0 and CollectionManager.has_discovered_card("chick"), "first Jester offering preserves its fully consumed card's discovery")
	failing = FailingCollection.new()
	add_child(failing)
	failing.refuse_saves = true
	before = failing.collection.duplicate(true)
	check(not failing.offer_jester_card("harald", "discovery-harald")["ok"] and failing.collection == before and not failing.has_discovered_card("developer") and not failing.has_discovered_card("missing_texture"), "failed final offering cannot discover a Secret reward")
	failing.refuse_saves = false
	var offering := failing.offer_jester_card("harald", "discovery-harald")
	reward_id = str(offering.get("reward_instance", {}).get("card_id", ""))
	check(offering["ok"] and failing.get_amount("harald") == 0 and failing.has_discovered_card("harald") and failing.has_discovered_card(reward_id), "completed offering retains consumed discoveries and records its Secret reward")
	failing.free()
	CollectionManager.reload_profile()
	check(CollectionManager.has_discovered_card("chick") and CollectionManager.has_discovered_card("harald") and CollectionManager.has_discovered_card(reward_id), "offering history and reward discovery survive reload")


func _check_slots() -> void:
	check(SaveSlots.select_slot(1) == OK and SaveSlots.reset_slot(1) == OK, "slot-one fixture starts with its own fresh profile")
	CollectionManager.discover_cards(["corpse", "chick"])
	CollectionManager.mark_card_seen("corpse")
	check(SaveSlots.reset_slot(2) == OK and SaveSlots.select_slot(2) == OK and CollectionManager.get_discovered_card_ids().is_empty(), "switching to a fresh slot does not inherit discoveries")
	CollectionManager.discover_cards(["bat", "harald", "corpse"])
	check(CollectionManager.is_card_new("corpse"), "the same card type starts unseen in an independent slot")
	CollectionManager.mark_card_seen("bat")
	check(SaveSlots.select_slot(1) == OK and CollectionManager.get_discovered_card_ids() == ["chick", "corpse"], "returning to slot one restores only its discoveries")
	check(not CollectionManager.is_card_new("corpse") and CollectionManager.is_card_new("chick"), "slot one restores its own seen and unseen types")
	check(SaveSlots.select_slot(2) == OK and CollectionManager.get_discovered_card_ids() == ["bat", "corpse", "harald"], "slot two preserves its independent discovery history")
	check(not CollectionManager.is_card_new("bat") and CollectionManager.is_card_new("corpse"), "slot two restores its own independent hover history")
	check(SaveSlots.reset_slot(2) == OK and CollectionManager.get_discovered_card_ids().is_empty(), "resetting the active slot clears discoveries")
	CollectionManager.discover_cards(["bat"])
	check(CollectionManager.is_card_new("bat"), "resetting a slot also clears its previous acknowledgements")
