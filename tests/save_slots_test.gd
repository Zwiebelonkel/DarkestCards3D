extends Node

const COMBAT_IDS: Array[String] = ["corpse", "stray_cat", "sewer_rat"]

var checks := 0
var failures := 0
var expected: Dictionary = {}
var observed_profiles: Array[Dictionary] = []
var settings_before := PackedByteArray()


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + description)
	if not condition:
		failures += 1
		push_error(description)


func _run() -> void:
	if not SaveSlots.SAVE_ROOT.begins_with("res://test-user/") or not SaveSlots.LEGACY_ROOT.begins_with("res://test-user/") or not SaveSlots.REGISTRY_PATH.begins_with("res://test-user/") or not SettingsManager.CONFIG_PATH.begins_with("res://test-user/"):
		push_error("Use the isolated match-feature runner; this suite resets its three fixture profiles.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	SettingsManager.set_damage_numbers_enabled(false)
	settings_before = FileAccess.get_file_as_bytes(SettingsManager.CONFIG_PATH)
	CollectionManager.collection_changed.connect(_on_collection_changed)
	check(SaveSlots.storage_error == OK, "profile storage initialized before progression autoloads")
	if not _select(1):
		_finish()
		return
	for slot in range(1, 4):
		check(SaveSlots.reset_slot(slot) == OK, "isolated setup clears slot %d" % slot)
	for slot in range(1, 4):
		if not _select(slot):
			_finish()
			return
		_check_empty("new slot %d" % slot)
		_seed_profile(slot)
		expected[slot] = _snapshot()
		check(SaveSlots.select_slot(slot) == OK, "slot %d explicitly persists its populated profile" % slot)
		var summary := SaveSlots.get_slot_summary(slot)
		check(bool(summary.get("exists")) and int(summary.get("level")) == slot + 1 and is_equal_approx(float(summary.get("coins")), float(GameCurrency.get_coins())), "slot %d summary reads its own saved wallet" % slot)
		check(int(summary.get("card_count")) == CollectionManager.get_card_instances().size(), "slot %d summary counts its own collection copies" % slot)
	for slot in [1, 2, 3, 1]:
		if not _select(slot):
			_finish()
			return
		_check_profile(expected[slot], "restored slot %d" % slot)
		_check_observer(slot)
		check(is_zero_approx(GameCurrency._auto_click_elapsed), "switch resets fractional clicker time in slot %d" % slot)
	_check_transaction_recovery()
	_check_rejected_changes()
	_check_reset_and_legacy_marker()
	check(FileAccess.get_file_as_bytes(SettingsManager.CONFIG_PATH) == settings_before and not SettingsManager.damage_numbers_enabled, "slot selection, recovery and reset preserve global settings byte for byte")
	_finish()


func _select(slot: int) -> bool:
	observed_profiles.clear()
	var error: Error = SaveSlots.select_slot(slot)
	var selected := error == OK and SaveSlots.active_slot == slot
	check(selected, "select_slot(%d) succeeds through the public API" % slot)
	if selected:
		var directory := SaveSlots.get_slot_directory(slot)
		check(CollectionManager.SAVE_PATH == directory.path_join("collection.json") and DeckManager.SAVE_PATH == directory.path_join("battle_deck.cfg") and CardUpgradeManager.SAVE_PATH == directory.path_join("card_upgrades.cfg") and GameCurrency.save_path == directory.path_join("currency.cfg"), "all four managers use the selected slot directory")
	return selected


func _seed_profile(slot: int) -> void:
	var combat_id := COMBAT_IDS[slot - 1]
	for copy in range(slot):
		check(not CollectionManager.add_card_instance({"card_id": combat_id, "instance_id": "slot-%d-copy-%d" % [slot, copy], "level": slot, "effects": [], "is_holo": copy == 0}).is_empty(), "slot %d stores its exact combat instance %d" % [slot, copy])
		check(DeckManager.add_card(combat_id), "slot %d selects owned combat copy %d" % [slot, copy])
	check(not CollectionManager.add_card("starting_hand_1").is_empty() and DeckManager.assign_starting_card(slot - 1, 0), "slot %d stores a chosen starting-hand copy" % slot)
	if slot == 1:
		CollectionManager.add_card("basement_key")
		CollectionManager.add_card("slot_room_key")
		CollectionManager.add_card("clicker")
		CollectionManager.add_card("auto_clicker")
		check(CollectionManager.unlock_area("basement") and CollectionManager.unlock_slot_room(), "slot one persists both area and legacy door unlock metadata")
	CollectionManager.collection["metadata"]["qa_slot"] = slot
	CollectionManager.save_collection()
	CardUpgradeManager.add_attack(combat_id, slot)
	CardUpgradeManager.add_health(combat_id, slot * 2)
	GameCurrency.coins = 111.0 * slot + float(slot) / 100.0
	GameCurrency.level = slot + 1
	GameCurrency.xp = slot * 7
	GameCurrency._coin_reward_remainder = float(slot) * 0.1
	GameCurrency._xp_reward_remainder = float(slot) * 0.2
	GameCurrency._auto_click_elapsed = 0.43
	check(GameCurrency.save(), "slot %d persists cents, XP and fractional rewards" % slot)


func _snapshot() -> Dictionary:
	return {
		"collection": CollectionManager.collection.duplicate(true),
		"deck": DeckManager.get_deck_cards(),
		"instances": DeckManager.deck_instance_ids.duplicate(),
		"starting": DeckManager.get_starting_deck_indices(),
		"upgrades": CardUpgradeManager.upgrades.duplicate(true),
		"cents": GameCurrency.get_coin_cents(), "level": GameCurrency.get_level(), "xp": GameCurrency.get_xp(),
		"coin_remainder": GameCurrency._coin_reward_remainder, "xp_remainder": GameCurrency._xp_reward_remainder,
	}


func _check_profile(state: Dictionary, label: String) -> void:
	check(_json_value(CollectionManager.collection) == _json_value(state["collection"]), label + " restores only its own instances, Holo/level data and unlock metadata")
	check(DeckManager.get_deck_cards() == state["deck"] and DeckManager.deck_instance_ids == state["instances"] and DeckManager.get_starting_deck_indices() == state["starting"], label + " restores the exact deck and starting-hand identities")
	check(CardUpgradeManager.upgrades == state["upgrades"], label + " restores only its own combat upgrades")
	check(GameCurrency.get_coin_cents() == state["cents"] and GameCurrency.get_level() == state["level"] and GameCurrency.get_xp() == state["xp"], label + " restores its wallet, level and XP")
	check(is_equal_approx(GameCurrency._coin_reward_remainder, float(state["coin_remainder"])) and is_equal_approx(GameCurrency._xp_reward_remainder, float(state["xp_remainder"])), label + " restores its own fractional income remainders")
	check(is_equal_approx(GameCurrency._auto_click_rate, CollectionManager.get_auto_click_rate()), label + " derives automatic income from its own collection")


func _check_empty(label: String) -> void:
	check(CollectionManager.get_owned_cards().is_empty() and CollectionManager.get_card_instances().is_empty(), label + " has no inherited cards")
	check(not CollectionManager.collection.get("metadata", {}).has("qa_slot") and not CollectionManager.has_area_access("basement") and not CollectionManager.is_slot_room_unlocked(), label + " has no inherited permanent unlocks")
	check(DeckManager.battle_deck.is_empty() and DeckManager.deck_instance_ids.is_empty() and DeckManager.starting_deck_indices.is_empty() and CardUpgradeManager.upgrades.is_empty(), label + " has no inherited deck, hand or upgrades")
	check(GameCurrency.get_coin_cents() == 2000 and GameCurrency.get_level() == 1 and GameCurrency.get_xp() == 0, label + " starts with twenty coins and level one")
	check(is_zero_approx(GameCurrency._coin_reward_remainder) and is_zero_approx(GameCurrency._xp_reward_remainder) and is_zero_approx(GameCurrency._auto_click_elapsed) and is_zero_approx(GameCurrency._auto_click_rate), label + " has no inherited income or elapsed clicker time")
	check(not GameCurrency.has_pending_slot_spin() and GameCurrency.get_queued_pack_count() == 0 and not GameCurrency._slot_transaction_active and not GameCurrency._pack_transaction_active, label + " has no inherited pending transactions")


func _on_collection_changed(_ids: Array[String]) -> void:
	observed_profiles.append({"slot": SaveSlots.active_slot, "marker": CollectionManager.collection.get("metadata", {}).get("qa_slot", 0), "cents": GameCurrency.get_coin_cents(), "deck": DeckManager.get_deck_cards()})


func _check_observer(slot: int) -> void:
	check(observed_profiles.size() == 1 and int(observed_profiles[0].get("marker", 0)) == slot and observed_profiles[0].get("cents") == expected[slot]["cents"] and observed_profiles[0].get("deck") == expected[slot]["deck"], "collection observers see one completed slot %d, never a mixed profile" % slot)


func _check_transaction_recovery() -> void:
	GameCurrency.coins = 100.37
	check(GameCurrency.begin_slot_spin(1000, 2500), "slot one commits an interrupted spin before its animation")
	var reservation := GameCurrency.begin_pack_purchase(225, 3)
	check(reservation > 0 and GameCurrency.get_queued_pack_count(reservation) == 2, "slot one reserves two later packs after its paid first pack")
	if not _select(2):
		return
	_check_profile(expected[2], "other slot during recovery")
	check(not GameCurrency.has_pending_slot_spin() and GameCurrency.get_queued_pack_count() == 0 and GameCurrency._pack_reservation_id != reservation, "switching invalidates old reservations and does not transfer pending payouts")
	check(not GameCurrency.consume_queued_pack(reservation) and not GameCurrency.refund_queued_packs(reservation), "stale pack callbacks cannot consume or refund another profile")
	if not _select(1):
		return
	check(GameCurrency.get_coin_cents() == 11312, "original slot recovers its 2500-cent payout and 450-cent queued-pack refund exactly")
	check(not GameCurrency.has_pending_slot_spin() and GameCurrency.get_queued_pack_count() == 0, "recovery clears both committed transaction records")
	expected[1] = _snapshot()
	GameCurrency.reload_profile()
	_check_profile(expected[1], "reloaded recovered slot")
	check(not GameCurrency.complete_slot_spin() and not GameCurrency.refund_queued_packs(), "repeated load cannot pay or refund either transaction twice")
	var persisted := ConfigFile.new()
	check(persisted.load(GameCurrency.save_path) == OK and not bool(persisted.get_value("currency", "slot_spin_pending", true)) and int(persisted.get_value("currency", "queued_pack_count", -1)) == 0, "recovery persists both cleared records in their original wallet file")


func _check_rejected_changes() -> void:
	var before := _snapshot()
	var registry := FileAccess.get_file_as_bytes(SaveSlots.REGISTRY_PATH)
	for slot in [-1, 0, 4]:
		check(SaveSlots.select_slot(slot) == ERR_INVALID_PARAMETER and SaveSlots.reset_slot(slot) == ERR_INVALID_PARAMETER, "invalid slot %d cannot be selected or reset" % slot)
	NetworkManager.current_lobby_id = 12345
	check(SaveSlots.select_slot(2) == ERR_BUSY and SaveSlots.reset_slot(1) == ERR_BUSY, "active online lobby blocks selection and reset")
	NetworkManager.current_lobby_id = 0
	NetworkManager._joining_lobby_id = 12345
	check(SaveSlots.select_slot(2) == ERR_BUSY, "pending invite join blocks profile switching before the lobby exists")
	NetworkManager._joining_lobby_id = 0
	check(SaveSlots.active_slot == 1 and _snapshot() == before and FileAccess.get_file_as_bytes(SaveSlots.REGISTRY_PATH) == registry, "rejected IDs and online operations leave memory and active-slot registry unchanged")
	var path := SaveSlots.get_slot_directory(3).path_join("collection.json")
	var valid_data := FileAccess.get_file_as_bytes(path)
	check(_write_bytes(path, "[]".to_utf8_buffer()), "inactive fixture collection can be replaced with an invalid profile shape")
	check(SaveSlots.select_slot(3) == ERR_FILE_CORRUPT, "corrupted target returns an error instead of silently selecting an empty profile")
	check(SaveSlots.active_slot == 1 and _snapshot() == before and FileAccess.get_file_as_bytes(SaveSlots.REGISTRY_PATH) == registry, "corrupted target preserves the previous active profile and registry")
	check(FileAccess.get_file_as_bytes(path) == "[]".to_utf8_buffer(), "failed selection does not overwrite the damaged save")
	check(_write_bytes(path, valid_data), "the inactive fixture save is restored after corruption testing")
	var reentrant_results: Array[int] = []
	var callback := func(): reentrant_results.append(SaveSlots.select_slot(2))
	SaveSlots.slots_changed.connect(callback)
	check(SaveSlots.select_slot(1) == OK, "same-slot selection can persist without reloading the profile")
	SaveSlots.slots_changed.disconnect(callback)
	check(reentrant_results == [ERR_BUSY] and SaveSlots.active_slot == 1, "synchronous slot listeners cannot reenter a switch")


func _check_reset_and_legacy_marker() -> void:
	var other_files := _profile_files([2, 3])
	var legacy_path := SaveSlots.LEGACY_ROOT.path_join("collection.json")
	var legacy_existed := FileAccess.file_exists(legacy_path)
	var previous_legacy := FileAccess.get_file_as_bytes(legacy_path) if legacy_existed else PackedByteArray()
	var legacy := {"cards": {"corpse": 99}, "instances": [], "metadata": {"qa_legacy": true}}
	check(_write_bytes(legacy_path, JSON.stringify(legacy).to_utf8_buffer()), "fixture supplies a retained legacy collection to detect accidental reimport")
	check(SaveSlots.reset_slot(1) == OK and SaveSlots.active_slot == 1, "reset targets the selected slot without changing the selection")
	_check_empty("reset slot one")
	check(_profile_files([2, 3]) == other_files, "reset leaves every other slot's four files byte-identical")
	check(FileAccess.get_file_as_string(legacy_path) == JSON.stringify(legacy), "reset preserves the retained legacy original")
	var registry := ConfigFile.new()
	check(registry.load(SaveSlots.REGISTRY_PATH) == OK and bool(registry.get_value("slots", "legacy_imported", false)), "reset preserves the global one-time migration marker")
	check(SaveSlots._initialize_storage() == OK, "storage can initialize again after resetting the migrated slot")
	if _select(2):
		_check_profile(expected[2], "untouched slot two after reset")
	if _select(1):
		_check_empty("reset slot one after storage reinitialization")
	check(not CollectionManager.collection.get("metadata", {}).has("qa_legacy") and CollectionManager.get_amount("corpse") == 0, "retained legacy data never resurrects a reset slot")
	if _select(3):
		_check_profile(expected[3], "untouched slot three after reset")
	if legacy_existed:
		check(_write_bytes(legacy_path, previous_legacy), "fixture restores its pre-test legacy bytes")
	else:
		check(DirAccess.remove_absolute(legacy_path) == OK, "fixture removes only its own temporary legacy file")


func _profile_files(slots: Array) -> Dictionary:
	var files := {}
	for slot in slots:
		for file_name in SaveSlots.PROFILE_FILES:
			var path := SaveSlots.get_slot_directory(int(slot)).path_join(file_name)
			files[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	return files


func _write_bytes(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	var error := file.get_error()
	file.close()
	return error == OK


func _json_value(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


func _finish() -> void:
	print("SAVE_SLOTS_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
