extends Node

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	if not str(DeckManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Run secret_reward_test.tscn only with isolated test saves.")
		get_tree().quit(1)
		return
	var original_cards: Array[Dictionary] = CardDatabase.cards.duplicate()
	var original_index: Dictionary = CardDatabase.cards_by_id.duplicate()
	var original_collection: Dictionary = CollectionManager.collection.duplicate(true)
	var original_weights: Dictionary = CardDatabase._current_pack_weights.duplicate()
	CollectionManager.collection = {"cards": {}, "instances": [], "metadata": {}}
	var developer: Dictionary = CardDatabase.get_card("developer")
	var missing: Dictionary = CardDatabase.get_card("missing_texture")
	var common: Dictionary = CardDatabase.get_card("corpse")
	_expect(str(developer.get("rarity")) == "exotic" and str(missing.get("rarity")) == "exotic", "Developer and Missing Texture use Exotic rarity")
	var eligible := CardDatabase._get_eligible_rewards()
	_expect(eligible.has(developer) and eligible.has(missing), "Both Exotic cards remain eligible random acquisitions")
	_expect(not eligible.has(CardDatabase.get_card("graveyard_key")), "Discovery-only keys remain excluded")
	_expect(CardDatabase.has_regular_pack_rewards(), "The real catalog supports ordinary paid packs")
	var real_secrets: Array[String] = []
	for card: Dictionary in CardDatabase.cards:
		if card.get("rarity") == "secret":
			real_secrets.append(str(card.id))
			_expect(not eligible.has(card), "World Secret stays outside random acquisitions: " + str(card.id))
	real_secrets.sort()
	_expect(real_secrets == ["cigarettes", "moewenmilch", "usb_stick"], "Exactly the three prop cards use Secret rarity")
	for pack_id: String in PackDefinition.PACK_TYPES:
		var actual := CardDatabase.get_reward_rarity_weights(eligible, PackDefinition.PACK_TYPES[pack_id].rarity_weights, 0.0)
		_expect(not actual.has("secret") and _close(_sum(actual), 100.0), "%s redistributes absent Secret mass among ordinary rarities" % pack_id)

	# Synthetic random-eligible cards retain boundary coverage for the generic
	# Secret probability machinery without changing the authored discovery cards.
	developer = developer.duplicate(true)
	developer["id"] = "secret_fixture_second"
	developer["rarity"] = "secret"
	missing = missing.duplicate(true)
	missing["id"] = "secret_fixture_first"
	missing["rarity"] = "secret"
	CardDatabase.cards_by_id[developer.id] = developer
	CardDatabase.cards_by_id[missing.id] = missing
	eligible.append(missing)
	eligible.append(developer)

	var expected := {"basic": 0.001, "ultra": 0.005, "god": 0.01}
	var old_common := {"basic": 65.0, "ultra": 35.0, "god": 10.0}
	for pack_id in expected:
		var configured: Dictionary = PackDefinition.PACK_TYPES[pack_id]["rarity_weights"]
		var secret_mass := float(expected[pack_id])
		_expect(_close(_sum(configured), 100.0), "%s pack weights total 100" % pack_id)
		_expect(_close(float(configured["secret"]), secret_mass), "%s Secret weight is per draw, shared between both cards" % pack_id)
		_expect(_close(float(configured["common"]), float(old_common[pack_id]) - secret_mass), "%s Secret mass comes only from common" % pack_id)
		var weights := CardDatabase.get_reward_rarity_weights(eligible, configured, 0.0)
		_expect(_close(_sum(weights), 100.0) and _close(float(weights["secret"]), secret_mass), "%s synthetic eligible pool keeps the absolute Secret chance" % pack_id)
		_expect(_close(float(weights["common"]) / float(weights["uncommon"]), float(configured["common"]) / float(configured["uncommon"])), "%s ordinary rarity ratios are preserved" % pack_id)
		var probability := secret_mass / 100.0
		_expect(CardDatabase._roll_rarity(weights, probability * 0.5) == "secret", "%s deterministic roll inside Secret interval succeeds" % pack_id)
		_expect(CardDatabase._roll_rarity(weights, probability + 0.000000001) != "secret", "%s deterministic roll above Secret interval misses" % pack_id)
		_expect(str(CardDatabase._select_reward(eligible, configured, 0.0, 0.0).get("id")) == "secret_fixture_first", "%s selection reaches the first Secret fixture" % pack_id)
		_expect(str(CardDatabase._select_reward(eligible, configured, 0.0, 0.999999).get("id")) == "secret_fixture_second", "%s selection reaches the second Secret fixture" % pack_id)
		var lucky := CardDatabase.get_reward_rarity_weights(eligible, configured, 0.05)
		_expect(_close(_sum(lucky), 100.0) and _close(float(lucky["secret"]), secret_mass * 1.05), "%s Lucky Coin gives only its small relative boost" % pack_id)

	var mixed: Array[Dictionary] = [common, developer, missing]
	var one_secret: Array[Dictionary] = [common, developer]
	var secrets: Array[Dictionary] = [developer, missing]
	seed(31837)
	var expected_next_random := randf()
	seed(31837)
	CardDatabase._select_reward(mixed, {}, 0.0, 0.0)
	_expect(randf() == expected_next_random, "Explicit boundary rolls do not consume the global RNG")
	var defaults := CardDatabase.get_reward_rarity_weights(mixed, {}, 0.0)
	_expect(_close(float(defaults["secret"]), 0.001), "Unconfigured/default rewards reserve only 0.001% Secret")
	_expect(_close(float(CardDatabase.get_reward_rarity_weights(one_secret, {}, 0.0)["secret"]), float(defaults["secret"])), "Secret chance never scales with number of eligible Secret cards")
	var exhausted := CardDatabase.get_reward_rarity_weights(mixed, {"epic": 100.0}, 0.0)
	_expect(_close(float(exhausted["secret"]), 0.001) and _close(float(exhausted["common"]), 99.999), "Exhausted configured rarity falls back without making Secret common")
	_expect(str(CardDatabase._select_reward(mixed, {"epic": 100.0}, 0.5, 0.0).get("id")) == "corpse", "An exhausted custom pack still awards ordinary cards on misses")
	var ordinary_only := CardDatabase.get_reward_rarity_weights(mixed, {"common": 1.0}, 0.0)
	_expect(not ordinary_only.has("secret") and _close(float(ordinary_only["common"]), 100.0), "A fulfilled explicitly ordinary rarity does not gain a Secret override")
	for configured in [{}, {"common": 100.0}, {"secret": 100.0}, PackDefinition.PACK_TYPES["god"]["rarity_weights"]]:
		var weights := CardDatabase.get_reward_rarity_weights(secrets, configured, 0.0)
		_expect(float(weights["secret"]) <= 0.01 and float(weights[CardDatabase.NO_REWARD_RARITY]) >= 99.99, "A Secret-only pool retains empty probability mass")
		_expect(CardDatabase._select_reward(secrets, configured, 0.5, 0.0).is_empty(), "A Secret-only miss is empty rather than a guaranteed Secret")
		_expect(str(CardDatabase._select_reward(secrets, configured, 0.0, 0.0).get("rarity")) == "secret", "A Secret-only pool still permits its rare successful draw")
	_expect(CardDatabase._select_reward([], {}, 0.0, 0.0).is_empty(), "Empty pools return no reward")

	CardDatabase.cards = secrets
	_expect(not CardDatabase.has_regular_pack_rewards(), "A Secret-only catalog cannot start a regular paid pack")
	for api in ["default", "pack"]:
		CardDatabase.set_pack_rarity_weights({"epic": 100.0})
		seed(91831)
		var predicted_roll := randf()
		seed(91831)
		var result := CardDatabase.get_random_card() if api == "default" else CardDatabase.get_random_card_for_current_pack()
		_expect(result.is_empty() if predicted_roll >= 0.00001 else str(result.get("rarity")) == "secret", "%s public reward API obeys its absolute fallback gate" % api)
	_expect(str(CardDatabase.get_random_card_by_rarity("secret").get("rarity")) == "secret", "Explicit fixed-Secret grants remain supported")
	_expect(CardDatabase.get_random_card_by_rarity("common").is_empty(), "Fixed rarities never fall back to Secret")

	var unlock := CardDatabase.get_card("clicker").duplicate(true)
	unlock["id"] = "secret_reward_fixture"
	unlock["rarity"] = "secret"
	unlock["requires"] = []
	CardDatabase.cards_by_id["secret_reward_fixture"] = unlock
	CardDatabase.cards = [common, unlock]
	CollectionManager.collection["cards"] = {"secret_reward_fixture": 1}
	_expect(not CardDatabase._get_eligible_rewards().has(unlock), "Owned unique Secret unlocks are excluded")
	CollectionManager.collection["cards"] = {}
	var pending: Array[String] = ["secret_reward_fixture"]
	_expect(not CardDatabase._get_eligible_rewards(pending).has(unlock), "Pending unique Secret unlocks cannot repeat in the same pack")
	_expect(CardDatabase._get_eligible_rewards().has(unlock), "An unowned unreserved Secret unlock remains eligible")
	_expect(CardDatabase.has_regular_pack_rewards(), "An ordinary fallback survives alongside unique Secret unlocks")

	CardDatabase.cards = original_cards
	CardDatabase.cards_by_id = original_index
	CardDatabase.set_pack_rarity_weights(original_weights)
	CollectionManager.collection = original_collection
	if _failures.is_empty():
		print("SECRET_REWARD_TESTS: PASS (%d checks)" % _checks)
	else:
		for failure in _failures:
			push_error(failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _sum(weights: Dictionary) -> float:
	var result := 0.0
	for value in weights.values():
		result += float(value)
	return result


func _close(actual: float, expected: float) -> bool:
	# Godot's default approximate tolerance is too broad for 0.001% weights.
	return absf(actual - expected) <= maxf(0.0000000001, absf(expected) * 0.00000001)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
