extends Node3D

const CONTENT := preload("res://scripts/ui/JournalContent.gd")
const PROFILE_KEYS: Array[String] = ["slot", "level", "xp", "xp_required", "coins", "deck_count", "deck_capacity", "total_attack", "total_health", "deck_strength", "average_strength", "unique_deck_cards", "effect_count", "unique_effects", "holo_deck_count", "strongest_card_id", "strongest_strength", "collection_count", "combat_copies", "combat_types", "combat_catalog_count", "special_types", "special_catalog_count", "holo_collection_count", "stat_purchases"]

var checks := 0
var failures := 0
var viewport: SubViewport
var camera: Camera3D
var book: Journal3D


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + description)
	if not condition:
		failures += 1
		push_error(description)


func _run() -> void:
	for path in [SaveSlots.SAVE_ROOT, SaveSlots.LEGACY_ROOT, SaveSlots.REGISTRY_PATH, CollectionManager.SAVE_PATH, CardUpgradeManager.SAVE_PATH, DeckManager.SAVE_PATH, GameCurrency.save_path, SettingsManager.CONFIG_PATH]:
		if not str(path).begins_with("res://test-user/"):
			push_error("Use the isolated match-feature runner; this suite resets fixture slots 1 and 2.")
			get_tree().quit(1)
			return
	GameCurrency.set_process(false)
	Localization.set_locale("de")
	if not _select_slot(1):
		_finish()
		return
	for slot in [1, 2]:
		var error: Error = SaveSlots.reset_slot(slot)
		check(error == OK, "reset isolated profile fixture %d" % slot)
		if error != OK:
			_finish()
			return
	var empty := _read_profile("fresh empty profile")
	_check_empty_deck(empty)
	check(int(empty.get("collection_count", -1)) == 0 and int(empty.get("stat_purchases", -1)) == 0 and int(empty.get("level", 0)) == 1 and is_equal_approx(float(empty.get("coins", -1)), 20.0), "fresh profile has no inherited progress")
	_seed_profile()
	var populated := _read_profile("populated exact-copy deck")
	_check_populated(populated)
	_check_legacy_readonly()
	_check_slot_profiles(populated)
	await _check_journal()
	_finish()


func _seed_profile() -> void:
	_add_instance("corpse", "profile-corpse-normal")
	_add_instance("corpse", "profile-corpse-holo", true)
	_add_instance("corpse", "profile-corpse-holo-reserve", true)
	_add_instance("joe", "profile-joe")
	_add_instance("piss", "profile-piss")
	_add_instance("mailman", "profile-mailman-reserve")
	_add_instance("clicker", "profile-clicker")
	_add_instance("basement_key", "profile-key")
	DeckManager.battle_deck.assign(["corpse", "corpse", "joe", "piss"])
	DeckManager.deck_instance_ids.assign(["profile-corpse-normal", "profile-corpse-holo", "profile-joe", "profile-piss"])
	check(DeckManager.save_deck(), "save duplicate combat cards bound to exact owned copies")
	check(not DeckManager.add_card("clicker") and not DeckManager.add_card("basement_key"), "special cards cannot enter the real combat deck")
	CardUpgradeManager.add_attack("corpse", 2)
	CardUpgradeManager.add_health("corpse", 3)
	CardUpgradeManager.add_health("joe", 1)
	CardUpgradeManager.add_attack("piss", 4)
	CardUpgradeManager.add_health("mailman", 2)
	check(CardUpgradeManager.add_effect("corpse", EffectDatabase.get_effect("armor")), "both corpse copies share one purchased armor effect")
	check(CardUpgradeManager.remove_effect_at("joe", "base", 0) and CardUpgradeManager.add_effect("joe", EffectDatabase.get_effect("regeneration")), "replace Joe's innate thorns with a purchased effect")
	CardUpgradeManager.record_effect_roll("corpse", true)
	GameCurrency.coins = 123.45
	GameCurrency.level = 4
	GameCurrency.xp = 37
	check(GameCurrency.save(), "save a non-default player level, XP and cent balance")


func _add_instance(card_id: String, instance_id: String, holo: bool = false) -> void:
	check(not CollectionManager.add_card_instance({"card_id": card_id, "instance_id": instance_id, "level": 1, "effects": [], "is_holo": holo}).is_empty(), "own the exact fixture instance " + instance_id)


func _check_populated(profile: Dictionary) -> void:
	var corpse := CardDatabase.get_card("corpse")
	var joe := CardDatabase.get_card("joe")
	var piss := CardDatabase.get_card("piss")
	var expected_attack := 2 * (int(corpse["attack"]) + 2) + int(joe["attack"]) + int(piss["attack"]) + 4
	var expected_health := 2 * (int(corpse["defense"]) + 3) + int(joe["defense"]) + 1 + int(piss["defense"])
	var corpse_strength := int(corpse["attack"]) + 2 + int(corpse["defense"]) + 3
	check(int(profile.get("slot", 0)) == 1 and int(profile.get("level", 0)) == 4 and int(profile.get("xp", -1)) == 37 and int(profile.get("xp_required", 0)) == GameCurrency.get_xp_required() and is_equal_approx(float(profile.get("coins", -1)), 123.45), "overview reads the selected slot's exact player progression")
	check(int(profile.get("deck_count", -1)) == 4 and int(profile.get("deck_capacity", -1)) == DeckManager.MAX_DECK_SIZE and int(profile.get("unique_deck_cards", -1)) == 3, "deck counts copies separately from unique combat types")
	check(int(profile.get("total_attack", -1)) == expected_attack and int(profile.get("total_health", -1)) == expected_health and int(profile.get("deck_strength", -1)) == expected_attack + expected_health, "deck strength sums each copy's upgraded attack and maximum health exactly once")
	check(is_equal_approx(float(profile.get("average_strength", -1)), float(expected_attack + expected_health) / 4.0), "average strength divides by actual deck copies")
	check(str(profile.get("strongest_card_id", "")) == "corpse" and int(profile.get("strongest_strength", -1)) == corpse_strength, "strongest card is evaluated using its upgraded maximum stats")
	check(int(profile.get("effect_count", -1)) == 4 and int(profile.get("unique_effects", -1)) == 3, "effects include both armor copies, regeneration and innate Lava while removed thorns stay absent")
	check(int(profile.get("holo_deck_count", -1)) == 1 and int(profile.get("holo_collection_count", -1)) == 2, "a reserved collection Holo does not replace the normal copy pinned in the deck")
	check(int(profile.get("collection_count", -1)) == 8 and int(profile.get("combat_copies", -1)) == 6 and int(profile.get("combat_types", -1)) == 4 and int(profile.get("special_types", -1)) == 2, "collection distinguishes combat copies, combat types and permanent special types")
	check(int(profile.get("stat_purchases", -1)) == 5, "stat purchases count each type transaction once, including reserves but excluding effect rolls")
	var combat_catalog := 0
	var special_catalog := 0
	for card: Dictionary in CardDatabase.get_all_cards():
		if CardData.is_combat_card(card):
			combat_catalog += 1
		elif str(card.get("category", "")) == "special":
			special_catalog += 1
	check(int(profile.get("combat_catalog_count", -1)) == combat_catalog and int(profile.get("special_catalog_count", -1)) == special_catalog, "catalog completion denominators include every relevant card type")


func _check_empty_deck(profile: Dictionary) -> void:
	for key in ["deck_count", "total_attack", "total_health", "deck_strength", "average_strength", "unique_deck_cards", "effect_count", "unique_effects", "holo_deck_count", "strongest_strength"]:
		check(is_zero_approx(float(profile.get(key, -1))), "empty deck reports zero for " + key)
	check(str(profile.get("strongest_card_id", "invalid")) == "" and int(profile.get("deck_capacity", -1)) == DeckManager.MAX_DECK_SIZE, "empty deck has no strongest card and retains its capacity")


func _check_legacy_readonly() -> void:
	var cards := DeckManager.battle_deck.duplicate()
	var ids := DeckManager.deck_instance_ids.duplicate()
	var upgrades := CardUpgradeManager.upgrades.duplicate(true)
	DeckManager.deck_instance_ids.clear()
	CardUpgradeManager.upgrades.erase("corpse")
	DeckManager.battle_deck.append("clicker")
	var legacy := _read_profile("legacy deck without bindings or a corpse upgrade record")
	check(int(legacy.get("deck_count", -1)) == 4 and int(legacy.get("holo_deck_count", -1)) == 0 and not CardUpgradeManager.upgrades.has("corpse"), "read-only profile ignores a stray special without filling legacy Holo bindings or missing upgrade records")
	CardUpgradeManager.upgrades = upgrades.duplicate(true)
	CardUpgradeManager.upgrades["mailman"].erase("stat_upgrade_count")
	check(int(_read_profile("legacy stat counter").get("stat_purchases", -1)) == 6, "legacy purchase fallback reads stat bonuses without writing a derived counter")
	DeckManager.battle_deck.clear()
	DeckManager.deck_instance_ids.clear()
	_check_empty_deck(_read_profile("owned collection with an empty deck"))
	DeckManager.battle_deck = cards
	DeckManager.deck_instance_ids = ids
	CardUpgradeManager.upgrades = upgrades


func _state() -> Dictionary:
	return {"collection": CollectionManager.collection.duplicate(true), "upgrades": CardUpgradeManager.upgrades.duplicate(true), "deck": DeckManager.battle_deck.duplicate(), "ids": DeckManager.deck_instance_ids.duplicate(), "starting": DeckManager.starting_deck_indices.duplicate(), "slot": SaveSlots.active_slot, "coins": GameCurrency.get_coin_cents(), "level": GameCurrency.level, "xp": GameCurrency.xp, "coin_remainder": GameCurrency._coin_reward_remainder, "xp_remainder": GameCurrency._xp_reward_remainder, "auto_elapsed": GameCurrency._auto_click_elapsed, "cards": CardDatabase.get_all_cards(), "effects": EffectDatabase.get_all_effects()}


func _files() -> Dictionary:
	var result := {}
	var paths: Array[String] = [SaveSlots.REGISTRY_PATH, SettingsManager.CONFIG_PATH]
	for slot in range(1, 4):
		for file_name: String in SaveSlots.PROFILE_FILES:
			paths.append(SaveSlots.get_slot_directory(slot).path_join(file_name))
	for path in paths:
		result[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	return result


func _read_profile(label: String) -> Dictionary:
	var state_before := _state()
	var files_before := _files()
	seed(830791)
	var expected_rng := randi()
	seed(830791)
	var profile := PlayerProfile.snapshot()
	var repeated := PlayerProfile.snapshot()
	check(randi() == expected_rng, label + ": repeated reads preserve shared RNG")
	check(_state() == state_before and _files() == files_before, label + ": reads preserve all profile/catalog state and all save/settings bytes")
	check(profile == repeated and PROFILE_KEYS.all(func(key: String) -> bool: return profile.has(key)), label + ": stable snapshot contains the complete public schema")
	var original := profile.duplicate(true)
	profile["deck_strength"] = -99999
	check(PlayerProfile.snapshot() == original, label + ": callers own the returned snapshot")
	return original


func _select_slot(slot: int) -> bool:
	var error: Error = SaveSlots.select_slot(slot)
	check(error == OK and SaveSlots.active_slot == slot, "select fixture slot %d through the real API" % slot)
	return error == OK


func _check_slot_profiles(original: Dictionary) -> void:
	if not _select_slot(2):
		return
	var empty := _read_profile("second save slot")
	_check_empty_deck(empty)
	check(int(empty.get("slot", 0)) == 2 and int(empty.get("collection_count", -1)) == 0 and int(empty.get("stat_purchases", -1)) == 0, "another save slot has independent collection and purchase counts")
	_add_instance("joe", "profile-slot2-joe")
	check(DeckManager.add_card("joe"), "second slot owns and selects its own combat card")
	GameCurrency.coins = 77.66
	GameCurrency.level = 2
	GameCurrency.xp = 9
	check(GameCurrency.save(), "persist the second profile's distinct wallet")
	var second := _read_profile("populated second save slot")
	check(int(second.get("deck_count", -1)) == 1 and int(second.get("effect_count", -1)) == 1 and int(second.get("stat_purchases", -1)) == 0 and is_equal_approx(float(second.get("coins", -1)), 77.66), "second slot's Joe retains innate thorns instead of the first slot's purchased regeneration")
	if _select_slot(1):
		check(_read_profile("restored first save slot") == original, "switching back restores the exact first profile statistics")


func _check_journal() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	camera = Camera3D.new()
	camera.position = Vector3(0, 1.6, 4)
	viewport.add_child(camera)
	camera.make_current()
	book = Journal3D.new()
	book.open_duration = 0.03
	book.close_duration = 0.03
	viewport.add_child(book)
	book.close_requested.connect(func(): book.close_journal())
	check(book.open_journal(camera) and await _wait_until(func(): return book.is_open()), "standalone journal opens with a real reading camera")
	await _click_chapter("profile")
	_check_profile_page("profile:overview")
	var strength_before := int(PlayerProfile.snapshot()["deck_strength"])
	CardUpgradeManager.add_attack("corpse", 1)
	check(await _wait_until(func(): return int(book.chapters[_chapter_index("profile")]["entries"][0].get("profile_strength", -1)) == strength_before + 2), "open profile updates both upgraded deck copies without switching tabs or reopening")
	_check_profile_page("profile:overview")
	await _click("entry:1")
	_check_profile_page("profile:deck")
	await _close_with_escape()
	CardUpgradeManager.add_health("corpse", 1)
	check(book.open_journal(camera) and await _wait_until(func(): return book.is_open()), "journal reopens after progression changes while closed")
	_check_profile_page("profile:deck")
	await _click_chapter("effects")
	var previous_label := book._body_label
	var previous_text := book._body_label.text
	var previous_subject: String = book._entries()[book.entry_index]["id"]
	GameCurrency.add_coins(1.25)
	book.refresh_profile()
	check(book.chapter_index == _chapter_index("effects") and book._entries()[book.entry_index]["id"] == previous_subject and book._body_label == previous_label and book._body_label.text == previous_text, "refreshing profile data preserves another tab's subject and existing printed nodes")
	await _click_chapter("profile")
	_check_profile_page("profile:overview")
	await _click("entry:2")
	_check_profile_page("profile:collection")
	_add_instance("mailman", "profile-new-collection-copy")
	check(await _wait_until(func(): return book.chapters[_chapter_index("profile")] == CONTENT.build_profile_chapter()), "the visible collection page updates after acquisition")
	_check_profile_page("profile:collection")
	await _close_with_escape()
	viewport.queue_free()
	await get_tree().process_frame


func _check_profile_page(subject: String) -> void:
	check(book.chapter_index == _chapter_index("profile") and book._entries()[book.entry_index]["id"] == subject and book.chapters[_chapter_index("profile")] == CONTENT.build_profile_chapter(), "journal preserves its selected subject and shows a fresh snapshot: " + subject)
	check(book._body_label.text == book._body_pages[book.body_page] and not book._body_label.text.is_empty() and book._paper_contents.visible, "updated profile text is printed on the visible page: " + subject)


func _wait_until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 3000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())


func _chapter_index(id: String) -> int:
	for index in range(book.chapters.size()):
		if str(book.chapters[index]["id"]) == id:
			return index
	return -1


func _click_chapter(id: String) -> void:
	await _click("chapter:%d" % _chapter_index(id))


func _click(action: String) -> void:
	check(book._buttons.has(action), "physical profile control exists: " + action)
	if not book._buttons.has(action):
		return
	var control := book._buttons[action]["node"] as Node3D
	var point := camera.unproject_position(control.global_position)
	check(Rect2(Vector2.ZERO, Vector2(viewport.size)).has_point(point) and book._hit_target(point) == action, "profile control is visible and pointer-reachable: " + action)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = pressed
		viewport.push_input(event, true)
		await get_tree().process_frame
	check(await _wait_until(func(): return book.is_open()), "physical click completes: " + action)


func _close_with_escape() -> void:
	check(not book._buttons.has("close"), "profile has no Close or X control")
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.physical_keycode = KEY_ESCAPE
		event.pressed = pressed
		viewport.push_input(event, true)
	check(await _wait_until(func(): return not book.is_active()), "Escape closes the profile journal")


func _finish() -> void:
	print("JOURNAL_PROFILE_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
