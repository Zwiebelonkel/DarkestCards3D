extends Node

var _checks := 0
var _failures: Array[String] = []
var _change_signals := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not SettingsManager.CONFIG_PATH.begins_with("res://test-user/"):
		push_error("Run cheat_rarity_rewards_test.tscn only with isolated test saves.")
		get_tree().quit(1)
		return
	var original_cards: Array[Dictionary] = CardDatabase.cards.duplicate()
	var original_index: Dictionary = CardDatabase.cards_by_id.duplicate()
	var original_collection: Dictionary = CollectionManager.collection.duplicate(true)
	var original_weights: Dictionary = CardDatabase._current_pack_weights.duplicate()
	CollectionManager.collection = {"cards": {}, "instances": [], "metadata": {}}
	SettingsManager.cheat_rarities_changed.connect(func() -> void: _change_signals += 1)
	SettingsManager.reset_to_defaults(false)
	_expect(_enabled() == CardDatabase.REWARD_RARITIES, "Defaults enable all eight rarities")
	var eligible := CardDatabase._get_eligible_rewards()
	_expect(eligible.all(func(card: Dictionary): return card.get("rarity") != "secret"), "The authored catalog excludes all three discovery Secrets from random rewards")
	for card_id: String in ["developer", "missing_texture"]:
		_expect(CardDatabase.get_card(card_id).get("rarity") == "exotic" and eligible.has(CardDatabase.get_card(card_id)), card_id + " remains available as an Exotic random reward")
	# Synthetic random-eligible Secret keeps generic rarity math covered without
	# pretending that the three authored world discoveries can drop from packs.
	var secret := CardDatabase.get_card("usb_stick").duplicate(true)
	secret["id"] = "cheat_secret_fixture"
	secret["random_reward"] = true
	CardDatabase.cards_by_id[secret["id"]] = secret
	var fixture_eligible: Array[Dictionary] = eligible.duplicate()
	fixture_eligible.append(secret)
	for pack_id in PackDefinition.PACK_TYPES:
		var configured: Dictionary = PackDefinition.PACK_TYPES[pack_id].rarity_weights
		var weights := CardDatabase.get_reward_rarity_weights(eligible, configured, 0.0)
		_expect(not weights.has("secret") and _close(_sum(weights), 100.0), "%s has no Secret chance while only discovery Secrets are authored" % pack_id)
		weights = CardDatabase.get_reward_rarity_weights(fixture_eligible, configured, 0.0)
		_expect(_close(float(weights.secret), float(configured.secret)), "%s retains its exact configured Secret chance for an explicit random-reward fixture" % pack_id)

	var signals_before := _change_signals
	_expect(SettingsManager.set_cheat_rarity_enabled(" COMMON ", false), "A valid toggle accepts normalized rarity IDs")
	_expect(_change_signals == signals_before + 1 and not SettingsManager.is_cheat_rarity_enabled("common"), "A changed checkbox emits exactly one refresh signal")
	_expect(SettingsManager.set_cheat_rarity_enabled("common", false) and _change_signals == signals_before + 1, "Repeated values do not emit another change")
	_expect(not SettingsManager.set_cheat_rarity_enabled("god", true), "Pack types are not accepted as rarities")
	SettingsManager.load_settings()
	_expect(not SettingsManager.is_cheat_rarity_enabled("common"), "The saved disabled rarity survives reloading settings")

	_select_only(["common", "rare"])
	var basic: Dictionary = PackDefinition.PACK_TYPES.basic.rarity_weights
	var mixed := CardDatabase.get_reward_rarity_weights(eligible, basic, 0.0)
	_expect(mixed.size() == 2 and mixed.has("common") and mixed.has("rare") and _close(_sum(mixed), 100.0), "A mixed selection removes disabled tiers and normalizes to a complete reward")
	_expect(_close(float(mixed.common) / float(mixed.rare), float(basic.common) / float(basic.rare)), "Filtering preserves the relative pack odds of enabled rarities")

	for rarity in CardDatabase.REWARD_RARITIES:
		_select_only([rarity])
		_expect(not SettingsManager.set_cheat_rarity_enabled(rarity, false) and SettingsManager.is_cheat_rarity_enabled(rarity), "The last enabled rarity cannot be unchecked: " + rarity)
		_expect(CardDatabase.has_regular_pack_rewards() == (rarity != "secret"), "Only an authored repeatable selected pool supports complete packs: " + rarity)
		for pack_id in PackDefinition.PACK_TYPES:
			CardDatabase.set_pack_rarity_weights(PackDefinition.PACK_TYPES[pack_id].rarity_weights)
			for draw in range(12):
				var card := CardDatabase.get_random_card_for_current_pack()
				_expect(card.is_empty() if rarity == "secret" else str(card.get("rarity", "")) == rarity, "%s / %s draw %d only awards eligible cards of its checked rarity" % [pack_id, rarity, draw])
		var random_card := CardDatabase.get_random_card()
		_expect(random_card.is_empty() if rarity == "secret" else str(random_card.get("rarity", "")) == rarity, "Unconfigured random rewards obey the eligible selection: " + rarity)

	_select_only(["secret"])
	_expect(str(CardDatabase.get_random_card_by_rarity("common").get("rarity")) == "common", "Fixed-rarity grants keep their promised rarity despite the cheat")
	_expect(not CardDatabase.get_cards_by_rarity("common").is_empty() and CollectionManager.get_next_fusion_rarity("common") == "uncommon", "The filter leaves rarity catalogs and fusion available")
	var secret_weights := CardDatabase.get_reward_rarity_weights(eligible, basic, 0.0)
	_expect(secret_weights == {CardDatabase.NO_REWARD_RARITY: 100.0} and not CardDatabase.has_regular_pack_rewards(), "The authored Secret-only cheat has no available reward and fails the pre-payment pack gate")
	_expect(CardDatabase._select_reward(eligible, basic, 0.0, 0.0).is_empty() and CardDatabase._select_reward(eligible, basic, 0.999999, 0.0).is_empty(), "Neither minimum nor near-maximum rolls bypass authored discovery-only restrictions")
	secret_weights = CardDatabase.get_reward_rarity_weights(fixture_eligible, basic, 0.0)
	_expect(secret_weights == {"secret": 100.0}, "An explicit random-eligible Secret fixture removes the ordinary empty-reward gate under the cheat")
	_expect(CardDatabase._select_reward(fixture_eligible, basic, 0.999999, 0.0).get("id") == secret["id"], "Even a near-maximum rarity roll awards the selected random-eligible Secret fixture")

	# Exhausted and discovery-only pools must fail the pre-payment pack gate.
	var common: Dictionary = CardDatabase.get_card("corpse")
	CardDatabase.cards.assign([CardDatabase.get_card("usb_stick"), CardDatabase.get_card("cigarettes"), CardDatabase.get_card("moewenmilch")])
	_expect(not CardDatabase.has_regular_pack_rewards() and CardDatabase.get_random_card_for_current_pack().is_empty(), "A catalog containing all three authored Secrets still cannot start a paid pack")
	CardDatabase.cards.assign([common, CardDatabase.get_card("graveyard_key")])
	_expect(not CardDatabase.has_regular_pack_rewards() and CardDatabase.get_random_card_for_current_pack().is_empty(), "An exhausted selected pool cannot fall back to disabled or discovery-only cards")
	var unique := CardDatabase.get_card("clicker").duplicate(true)
	unique["id"] = "cheat_unique_fixture"
	unique["rarity"] = "secret"
	unique["requires"] = []
	CardDatabase.cards_by_id[unique.id] = unique
	CardDatabase.cards.assign([unique])
	_expect(not CardDatabase.has_regular_pack_rewards(), "A single one-time selected unlock cannot start a pack it cannot fill")
	_expect(CardDatabase.get_random_card_for_current_pack(["cheat_unique_fixture"]).is_empty(), "Pending unique unlocks remain excluded even under the cheat")
	CollectionManager.collection.cards[unique.id] = 1
	_expect(CardDatabase.get_random_card().is_empty(), "Owned unique unlocks remain excluded even under the cheat")
	CollectionManager.collection.cards.clear()
	CardDatabase.cards.assign([unique, secret])
	_expect(CardDatabase.has_regular_pack_rewards(), "A repeatable selected fallback makes the paid pool safe")
	for draw in range(12):
		_expect(CardDatabase.get_random_card_for_current_pack(["cheat_unique_fixture"]).get("id") == secret.id, "Reserved unique cards leave a complete selected fallback: %d" % draw)
	CardDatabase.cards.assign([secret])
	_select_only(CardDatabase.REWARD_RARITIES)
	_expect(not CardDatabase.has_regular_pack_rewards(), "Reenabling all rarities restores the normal Secret-only purchase restriction")
	_expect(CardDatabase._select_reward([secret], basic, 0.5, 0.0).is_empty(), "Reenabling all rarities restores the normal absolute Secret gate")
	CardDatabase.cards = original_cards
	CardDatabase.cards_by_id = original_index

	# Legacy, empty and malformed saved filters recover a usable default.
	for stored: Variant in [[], ["invalid"], false, {"common": false}]:
		var config := ConfigFile.new()
		config.set_value(SettingsManager.SECTION, "cheat_enabled_rarities", stored)
		_expect(config.save(SettingsManager.CONFIG_PATH) == OK, "Malformed-filter fixture is saved")
		SettingsManager.load_settings()
		_expect(_enabled() == CardDatabase.REWARD_RARITIES, "Empty or invalid saved selections restore all rarities: " + str(stored))
	var config := ConfigFile.new()
	config.set_value(SettingsManager.SECTION, "cheat_enabled_rarities", [" RARE ", "rare", "unknown", 4])
	config.save(SettingsManager.CONFIG_PATH)
	SettingsManager.load_settings()
	_expect(_enabled() == ["rare"], "Saved IDs are normalized, deduplicated and restricted to known rarities")
	config = ConfigFile.new()
	config.set_value(SettingsManager.SECTION, "frame_limit", 60)
	config.save(SettingsManager.CONFIG_PATH)
	SettingsManager.load_settings()
	_expect(_enabled() == CardDatabase.REWARD_RARITIES, "Older settings with no filter enable all rarities")
	_select_only(["secret"])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SettingsManager.CONFIG_PATH))
	SettingsManager.load_settings()
	_expect(_enabled() == CardDatabase.REWARD_RARITIES, "A missing settings file clears a previously active filter")
	_select_only(["exotic"])
	SettingsManager.reset_to_defaults()
	SettingsManager.load_settings()
	_expect(_enabled() == CardDatabase.REWARD_RARITIES, "Reset restores and saves the normal unfiltered defaults")
	CardDatabase.set_pack_rarity_weights(original_weights)
	CollectionManager.collection = original_collection
	if _failures.is_empty():
		print("CHEAT_RARITY_REWARDS_TESTS: PASS (%d checks)" % _checks)
	else:
		for failure in _failures:
			push_error(failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _select_only(rarities: Array[String]) -> void:
	for rarity in rarities:
		SettingsManager.set_cheat_rarity_enabled(rarity, true)
	for rarity in CardDatabase.REWARD_RARITIES:
		if not rarities.has(rarity):
			SettingsManager.set_cheat_rarity_enabled(rarity, false)


func _enabled() -> Array[String]:
	var result: Array[String] = []
	for rarity in CardDatabase.REWARD_RARITIES:
		if SettingsManager.is_cheat_rarity_enabled(rarity):
			result.append(rarity)
	return result


func _sum(weights: Dictionary) -> float:
	var result := 0.0
	for value in weights.values():
		result += float(value)
	return result


func _close(actual: float, expected: float) -> bool:
	return absf(actual - expected) <= maxf(0.0000000001, absf(expected) * 0.00000001)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
