extends Node

class FailingCollection extends "res://scripts/autoload/CollectionManager.gd":
	var refuse_saves := false
	func _ready() -> void:
		pass
	func _save_collection_snapshot(snapshot: Dictionary, suffix: String = ".tmp") -> bool:
		return false if refuse_saves else super._save_collection_snapshot(snapshot, suffix)

var checks := 0
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + description)
	if not condition:
		failures += 1

func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/") or not str(SaveSlots.SAVE_ROOT).begins_with("res://test-user/"):
		push_error("Run prop Secret backend tests in an isolated project to protect player saves.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	_check_catalog()
	_check_invalid_discovery()
	_check_partial_progress_failure()
	for card_id: String in CollectionManager.PROP_SECRET_CARD_IDS:
		print("PROP SECRET: " + card_id)
		_check_discovery(card_id)
		_check_failed_save(card_id)
		_check_old_ownership(card_id)
		_check_profiles(card_id)
	_check_independent_discoveries()
	print("USB_SECRET_BACKEND_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)

func _random() -> RandomNumberGenerator:
	var random := RandomNumberGenerator.new()
	random.seed = 829401
	return random

func _same_saved_value(left: Variant, right: Variant) -> bool:
	# JSON normalizes authored integer levels to floats when loading saves.
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))

func _reset() -> void:
	CollectionManager.clear_profile_state()
	DeckManager.clear_profile_state()
	CollectionManager.save_collection()

func _check_catalog() -> void:
	var scenes := {
		"usb_stick": "res://scenes/cards/UsbSecretRoom.tscn",
		"cigarettes": "res://scenes/cards/CigarettesSecretRoom.tscn",
		"moewenmilch": "res://scenes/cards/SeagullMilkSecretRoom.tscn",
	}
	var cards: Array[Dictionary] = CardDatabase.cards.duplicate(true)
	for card_id: String in CollectionManager.PROP_SECRET_CARD_IDS:
		var data := CardDatabase.get_card(card_id)
		check(data.get("rarity") == "secret" and CardData.is_combat_card(data) and int(data.get("attack")) == 32 and int(data.get("defense")) == 32, card_id + " is a collectible Secret combat card with its authored stats")
		check(str(data.get("image", "")) == "" and str(data.get("artwork_scene")) == scenes[card_id] and data.get("animated") == false, card_id + " uses scene artwork instead of a static image or sprite animation")
		check(CardDatabase.get_combat_cards().has(data) and not CardDatabase.get_cards_by_rarity("secret").has(data), card_id + " remains playable but is excluded from ordinary rarity rewards")
		CardDatabase.cards = [data]
		check(CardDatabase.get_random_card().is_empty() and CardDatabase.get_random_card_by_rarity("secret").is_empty() and CardDatabase.get_random_card_for_current_pack().is_empty(), "all random card APIs reject " + card_id + " even when it is the only candidate")
		CardDatabase.cards = cards
	var secret_ids: Array = cards.filter(func(card: Dictionary): return card.get("rarity") == "secret").map(func(card: Dictionary): return card["id"])
	check(secret_ids.size() == 4 and secret_ids.all(func(card_id: String): return card_id in CollectionManager.PROP_SECRET_CARD_IDS or card_id == "dman"), "prop Secrets and the separate DMAN wall discovery use Secret rarity")
	for card_id: String in ["developer", "missing_texture"]:
		var data := CardDatabase.get_card(card_id)
		check(data.get("rarity") == "exotic" and CardDatabase.get_cards_by_rarity("exotic").has(data), card_id + " is again an ordinary Exotic reward")

func _check_invalid_discovery() -> void:
	_reset()
	var random := _random()
	var before := CollectionManager.collection.duplicate(true)
	var state := random.state
	var file_before := FileAccess.get_file_as_string(CollectionManager.SAVE_PATH)
	check(CollectionManager.discover_prop_secret("developer", random).is_empty() and CollectionManager.discover_prop_secret("missing_texture", random).is_empty() and CollectionManager.discover_prop_secret("invalid_prop", random).is_empty() and CollectionManager.discover_prop_secret("usb_stick", null).is_empty(), "only the three authored tabletop discoveries and a private RNG are accepted")
	check(CollectionManager.collection == before and random.state == state and FileAccess.get_file_as_string(CollectionManager.SAVE_PATH) == file_before, "invalid discovery requests change neither cards, save files nor random state")

func _check_discovery(card_id: String) -> void:
	_reset()
	var random := _random()
	var required := int(CollectionManager.PROP_SECRET_THROW_REQUIREMENTS[card_id])
	var progress_valid := true
	var early_changes: Array = []
	var progress_listener := func(ids: Array[String]):
		if not ids.is_empty():
			early_changes.append(ids)
	CollectionManager.collection_changed.connect(progress_listener)
	for count in range(1, required):
		progress_valid = progress_valid and CollectionManager.discover_prop_secret(card_id, random).is_empty()
		progress_valid = progress_valid and CollectionManager.get_prop_secret_throw_count(card_id) == count
		if count == required / 2:
			CollectionManager.reload_profile()
			progress_valid = progress_valid and CollectionManager.get_prop_secret_throw_count(card_id) == count
	CollectionManager.collection_changed.disconnect(progress_listener)
	check(progress_valid and CollectionManager.get_amount(card_id) == 0 and not CollectionManager.has_discovered_card(card_id), "all throws below the exact threshold remain locked and partial progress survives reload: " + card_id)
	check(random.state == _random().state and early_changes.is_empty(), "progress-only throws neither roll an instance nor publish a card award")
	var prediction := _random()
	prediction.randi()
	var expected_holo := CardData.roll_holo(prediction.randi_range(0, CardData.HOLO_ROLL_SIDES - 1))
	var changes: Array = []
	var nested: Array[Dictionary] = []
	var saved: Array[Dictionary] = []
	var listener := func(ids: Array[String]):
		changes.append(ids.duplicate())
		saved.append(JSON.parse_string(FileAccess.get_file_as_string(CollectionManager.SAVE_PATH)))
		nested.append(CollectionManager.discover_prop_secret(card_id, random))
		var other_id: String = CollectionManager.PROP_SECRET_CARD_IDS[(CollectionManager.PROP_SECRET_CARD_IDS.find(card_id) + 1) % 3]
		nested.append(CollectionManager.discover_prop_secret(other_id, random))
	CollectionManager.collection_changed.connect(listener)
	seed(443912)
	var next_shared_random := randi()
	seed(443912)
	var instance := CollectionManager.discover_usb_secret(random) if card_id == CollectionManager.USB_SECRET_CARD_ID else CollectionManager.discover_prop_secret(card_id, random)
	check(randi() == next_shared_random, "prop Secret identity and Holo roll preserve shared battle randomness")
	check(not instance.is_empty() and str(instance.get("card_id")) == card_id and int(instance.get("level")) == 1 and instance.get("effects") == [], "discovery grants one exact level-one prop Secret without bonus effects")
	check(CardData.is_holo(instance) == expected_holo and random.state == prediction.state, "the optional Holo uses only the supplied prop RNG")
	check(changes == [[card_id]] and nested == [{}, {}], "one collection event is published and synchronous reentry grants neither the same nor another prop Secret")
	check(saved.size() == 1 and _same_saved_value(saved[0].get("instances"), [instance]) and saved[0].get("metadata", {}).get("discovered_cards", {}).get(card_id) == true, "listeners see the exact instance and permanent discovery already saved together")
	var committed := instance.duplicate(true)
	instance["is_holo"] = not CardData.is_holo(instance)
	instance["effects"].append({"type": "double_strike"})
	check(CollectionManager.get_instances_for_card(card_id) == [committed], "changing a returned instance cannot alter stored identity or effects")
	CollectionManager.collection_changed.disconnect(listener)
	CollectionManager.reload_profile()
	var repeated_random_state := random.state
	check(_same_saved_value(CollectionManager.get_instances_for_card(card_id), [committed]) and CollectionManager.discover_prop_secret(card_id, random).is_empty() and random.state == repeated_random_state, "reload preserves the exact card and another throw neither awards nor rerolls")
	check(DeckManager.add_card(card_id), "the discovered Secret remains playable in the combat deck")
	DeckManager.clear_profile_state()
	CollectionManager.collection["cards"].erase(card_id)
	CollectionManager.collection["instances"] = []
	CollectionManager.save_collection()
	CollectionManager.reload_profile()
	check(CollectionManager.get_amount(card_id) == 0 and CollectionManager.has_discovered_card(card_id) and CollectionManager.discover_prop_secret(card_id, random).is_empty(), "losing the last owned copy does not reset the permanent one-time discovery")

func _check_failed_save(card_id: String) -> void:
	_reset()
	CollectionManager.collection.metadata["prop_secret_throws"] = {card_id: int(CollectionManager.PROP_SECRET_THROW_REQUIREMENTS[card_id]) - 1}
	CollectionManager.save_collection()
	var failing := FailingCollection.new()
	add_child(failing)
	failing.collection = CollectionManager.collection.duplicate(true)
	var random := _random()
	var random_state := random.state
	var before := failing.collection.duplicate(true)
	var file_before := FileAccess.get_file_as_string(failing.SAVE_PATH)
	var changes: Array = []
	failing.collection_changed.connect(func(ids: Array[String]): changes.append(ids.duplicate()))
	failing.refuse_saves = true
	check(failing.discover_prop_secret(card_id, random).is_empty() and failing.collection == before and not failing.has_discovered_card(card_id), "failed persistence leaves ownership and discovery unchanged in memory")
	check(FileAccess.get_file_as_string(failing.SAVE_PATH) == file_before and changes.is_empty() and random.state == random_state, "failed persistence leaves the prior save, notifications and private roll unchanged")
	failing.refuse_saves = false
	var instance: Dictionary = failing.discover_prop_secret(card_id, random)
	check(not instance.is_empty() and failing.get_instances_for_card(card_id) == [instance] and changes == [[card_id]], "a failed discovery can retry successfully exactly once")
	check(failing.discover_prop_secret(card_id, random).is_empty() and changes.size() == 1, "retry callbacks cannot duplicate the committed card")
	failing.free()
	CollectionManager.reload_profile()
	check(_same_saved_value(CollectionManager.get_instances_for_card(card_id), [instance]) and CollectionManager.has_discovered_card(card_id), "the successful retry remains durable after reload")

func _check_old_ownership(card_id: String) -> void:
	_reset()
	var random := _random()
	var before := random.state
	CollectionManager.collection = {card_id: 1}
	check(CollectionManager.discover_prop_secret(card_id, random).is_empty() and CollectionManager.collection == {card_id: 1} and random.state == before, "legacy quantity ownership also prevents a second discovery without migrating or consuming randomness")
	CollectionManager.collection = {"cards": {}, "instances": [], "metadata": {"discovered_cards": {card_id: true}}}
	check(CollectionManager.discover_prop_secret(card_id, random).is_empty(), "existing journal discovery counts even after all copies were consumed")

func _check_profiles(card_id: String) -> void:
	SaveSlots.select_slot(2)
	_reset()
	SaveSlots.select_slot(1)
	_reset()
	var first := _earn_secret(card_id, _random())
	check(SaveSlots.select_slot(2) == OK and not CollectionManager.has_discovered_card(card_id) and CollectionManager.get_prop_secret_throw_count(card_id) == 0, "another save slot starts with its own undiscovered prop Secret and zero throws")
	var second := _earn_secret(card_id, _random())
	check(not second.is_empty() and CollectionManager.get_amount(card_id) == 1, "the second save slot can independently discover one prop Secret")
	check(SaveSlots.select_slot(1) == OK and _same_saved_value(CollectionManager.get_instances_for_card(card_id), [first]) and CollectionManager.discover_prop_secret(card_id, _random()).is_empty(), "returning to the first slot restores its one-time discovery and original instance")
	check(SaveSlots.select_slot(2) == OK and _same_saved_value(CollectionManager.get_instances_for_card(card_id), [second]) and CollectionManager.discover_prop_secret(card_id, _random()).is_empty(), "returning to the second slot restores its own instance without another award")

func _check_independent_discoveries() -> void:
	_reset()
	var random := _random()
	for card_id: String in CollectionManager.PROP_SECRET_CARD_IDS:
		check(not _earn_secret(card_id, random).is_empty(), "the same profile can independently earn " + card_id)
	CollectionManager.reload_profile()
	check(CollectionManager.get_card_instances().size() == 3 and CollectionManager.PROP_SECRET_CARD_IDS.all(func(card_id: String): return CollectionManager.get_amount(card_id) == 1 and CollectionManager.has_discovered_card(card_id)), "all three one-time discoveries coexist durably in the same profile")


func _earn_secret(card_id: String, random: RandomNumberGenerator) -> Dictionary:
	var result: Dictionary = {}
	for count in range(int(CollectionManager.PROP_SECRET_THROW_REQUIREMENTS[card_id])):
		result = CollectionManager.discover_prop_secret(card_id, random)
	return result


func _check_partial_progress_failure() -> void:
	_reset()
	var failing := FailingCollection.new()
	add_child(failing)
	failing.collection = CollectionManager.collection.duplicate(true)
	failing.refuse_saves = true
	var random := _random()
	var before := failing.collection.duplicate(true)
	check(failing.discover_prop_secret("usb_stick", random).is_empty() and failing.collection == before and failing.get_prop_secret_throw_count("usb_stick") == 0, "failed progress save does not count a throw")
	failing.refuse_saves = false
	failing.discover_prop_secret("usb_stick", random)
	check(failing.get_prop_secret_throw_count("usb_stick") == 1 and failing.get_amount("usb_stick") == 0, "retry saves one progress step without granting early")
	for invalid: Variant in ["49", -10, false, {}, null]:
		failing.collection.metadata["prop_secret_throws"] = {"usb_stick": invalid}
		check(failing.get_prop_secret_throw_count("usb_stick") == 0, "malformed progress cannot skip the discovery requirement")
	failing.free()
