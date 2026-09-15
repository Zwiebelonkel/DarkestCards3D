extends Node

const NEW_IDS: Array[String] = [
	"lucky_coin", "golden_clicker", "auto_clicker", "black_market_access", "dealer_license",
	"fusion_upgrade_1", "fusion_upgrade_2", "soulcoin_boost_1", "soulcoin_boost_2",
	"soulcoin_boost_3", "soulcoin_boost_4", "xp_boost_1", "xp_boost_2", "xp_boost_3",
	"xp_boost_4", "graveyard_key", "basement_key",
]

var _checks := 0
var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Run progression_rewards_test through the isolated match feature runner.")
		get_tree().quit(1)
		return
	CollectionManager.collection = {"cards": {}, "instances": []}
	_test_card_data()
	_test_rarity_weights()
	_test_reward_paths()
	_test_secret_graveyard_key()
	print("PROGRESSION_REWARD_TESTS: %s (%d checks)" % ["PASS" if _failures.is_empty() else "FAIL", _checks])
	for failure in _failures:
		push_error(failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _test_card_data() -> void:
	for id in NEW_IDS:
		var card: Dictionary = CardDatabase.get_card(id)
		_expect(not card.is_empty() and str(card.get("category", "")) == "special", id + " is registered as special")
		_expect(not CardData.is_combat_card(card) and int(card.get("attack", -1)) == 0 and int(card.get("defense", -1)) == 0 and card.get("effects") == [], id + " cannot fight and has no combat stats or effects")
		_expect(card.get("permanent_upgrade", false) and card.get("upgrade_modifiers") is Dictionary, id + " declares a permanent data-driven upgrade")
		_expect(CardData.is_unique_unlock(card) == (id != "golden_clicker"), id + " has the requested uniqueness")
		_expect(FileAccess.file_exists(str(card.get("image", ""))), id + " reuses an existing artwork")
		for required in card.get("requires", []):
			_expect(CardDatabase.has_card(str(required)), id + " has a registered prerequisite")
	_expect(CardDatabase.get_card("lucky_coin").get("flavor_text") == "A lucky coin that somehow always lands on the expensive side.", "Provided Lucky Coin flavor is preserved")
	_expect(is_equal_approx(float(CardDatabase.get_card("lucky_coin").get("reward_weight", 1.0)), 0.02), "Lucky Coin uses one fiftieth of ordinary per-card reward weight")
	_expect(CardDatabase.get_card("black_market_access").get("area_unlock") == "black_market" and CardDatabase.get_card("graveyard_key").get("area_unlock") == "graveyard" and CardDatabase.get_card("basement_key").get("area_unlock") == "basement", "Area keys use the same declarative unlock property")


func _test_rarity_weights() -> void:
	var source := {"common": 60.0, "uncommon": 20.0, "rare": 10.0, "epic": 6.0, "legendary": 3.0, "mythic": 0.8, "exotic": 0.2}
	var original := source.duplicate(true)
	var adjusted: Dictionary = CardDatabase.get_adjusted_rarity_weights(source, 0.05)
	_expect(source == original, "Lucky Coin never mutates pack definitions")
	_expect(is_equal_approx(_total(adjusted), 100.0), "Lucky Coin preserves probability mass")
	_expect(is_equal_approx(float(adjusted["common"]), 59.0) and is_equal_approx(float(adjusted["uncommon"]), 20.0), "A 20% rare+ chance becomes 21% by reducing common from 60% to 59%")
	for rarity in ["rare", "epic", "legendary", "mythic", "exotic"]:
		_expect(is_equal_approx(float(adjusted[rarity]), float(source[rarity]) * 1.05), rarity + " gets exactly a five percent relative increase")
	_expect(CardDatabase.get_adjusted_rarity_weights(source, 0.0) == source, "Zero bonus leaves odds unchanged")
	_expect(CardDatabase.get_adjusted_rarity_weights({"legendary": 1.0}, 0.05) == {"legendary": 1.0}, "Guaranteed legendary rewards remain guaranteed legendary")
	_expect(CardDatabase.get_adjusted_rarity_weights({"rare": 2.0, "mythic": 1.0}, 0.05) == {"rare": 2.0, "mythic": 1.0}, "All-rare pools are unchanged because rare+ is already certain")
	var exhausted: Dictionary = CardDatabase.get_adjusted_rarity_weights({"common": 0.01, "uncommon": 0.01, "rare": 0.98}, 0.05)
	_expect(is_zero_approx(float(exhausted["common"])) and is_zero_approx(float(exhausted["uncommon"])) and is_equal_approx(float(exhausted["rare"]), 1.0), "Large bonuses cap at available low-rarity mass without negative odds")
	_expect(CardDatabase.get_adjusted_rarity_weights(source) == source, "Actual locked Lucky Coin adds no bonus")
	CollectionManager.add_card("lucky_coin")
	_expect(CardDatabase.get_adjusted_rarity_weights(source) == adjusted, "Actual Lucky Coin unlock activates the central adjustment")
	CollectionManager.collection = {"cards": {}, "instances": []}
	CollectionManager.load_collection()
	_expect(CardDatabase.get_adjusted_rarity_weights(source) == adjusted, "Lucky Coin reward bonus survives save and reload")


func _test_reward_paths() -> void:
	var original_cards: Array[Dictionary] = CardDatabase.cards.duplicate(true)
	var coin: Dictionary = CardDatabase.get_card("lucky_coin")
	var common: Dictionary = CardDatabase.get_card("corpse")
	var legendary: Dictionary = CardDatabase.get_card("plinky")
	CollectionManager.collection = {"cards": {}, "instances": []}
	CardDatabase.cards.assign([common, coin, CardDatabase.get_card("golden_clicker"), CardDatabase.get_card("auto_clicker"), CardDatabase.get_card("fusion_upgrade_2"), CardDatabase.get_card("slot_room_key")])
	_expect(CardDatabase.get_random_card_by_rarity("epic").is_empty() and CardDatabase.get_random_card_by_rarity("mythic").is_empty(), "Fixed-rarity drops exclude unmet clicker and fusion prerequisites")
	CardDatabase.set_pack_rarity_weights({"legendary": 1.0})
	_expect(CardDatabase.get_random_card_for_current_pack().get("id") == "lucky_coin", "Eligible unique Lucky Coin can appear in its legendary pack slot")
	var pending: Array[String] = ["lucky_coin"]
	_expect(CardDatabase.get_random_card_for_current_pack(pending).get("id") == "corpse", "A reserved Lucky Coin cannot appear twice in a pack; exhausted pool fills from eligible cards")
	CollectionManager.add_card("lucky_coin")
	var all_valid := true
	for _index in range(100):
		all_valid = all_valid and CardDatabase.get_random_card().get("id") == "corpse" and CardDatabase.get_random_card_for_current_pack().get("id") == "corpse"
	_expect(all_valid, "Every random reward API excludes owned unique cards, unmet requirements and the secret original door key")
	_expect(CardDatabase.get_random_card_by_rarity("legendary").is_empty(), "An exhausted fixed-rarity drop never silently changes rarity")
	CollectionManager.collection = {"cards": {}, "instances": []}
	CollectionManager.add_card("clicker")
	_expect(CardDatabase.get_random_card_by_rarity("epic").get("id") == "golden_clicker" and CardDatabase.get_random_card_by_rarity("mythic").get("id") == "auto_clicker", "Prerequisites enable the existing fixed-rarity reward API")
	CardDatabase.cards.assign([coin, legendary])
	seed(78231)
	var lucky_drops := 0
	for _index in range(10000):
		if CardDatabase.get_random_card_by_rarity("legendary").get("id") == "lucky_coin":
			lucky_drops += 1
	_expect(lucky_drops > 50 and lucky_drops < 350, "Lucky Coin is obtainable but much rarer than an ordinary legendary (seeded 10000-drop sample: %d)" % lucky_drops)
	CardDatabase.cards = original_cards
	CardDatabase.set_pack_rarity_weights({})


func _total(weights: Dictionary) -> float:
	var total := 0.0
	for weight in weights.values():
		total += float(weight)
	return total


func _test_secret_graveyard_key() -> void:
	var original_cards: Array[Dictionary] = CardDatabase.cards.duplicate(true)
	var secret: Dictionary = CardDatabase.get_card("graveyard_key")
	_expect(secret.get("random_reward", true) == false, "Graveyard Key is explicitly excluded from random rewards")
	_expect(CardDatabase.get_all_cards().has(secret), "Secret reward exclusion keeps the card in the collectible and journal catalog")
	CollectionManager.collection = {"cards": {}, "instances": []}
	# An otherwise empty secret-only catalog makes leaks deterministic rather
	# than relying on a large sample that could simply miss a rare secret.
	CardDatabase.cards.assign([secret, CardDatabase.get_card("slot_room_key")])
	_expect(CardDatabase.get_random_card().is_empty(), "Generic random rewards cannot draw either world secret")
	_expect(CardDatabase.get_random_card_by_rarity("legendary").is_empty(), "Fixed legendary drops cannot award the hidden Graveyard Key")
	_expect(CardDatabase.get_cards_by_rarity("legendary").is_empty(), "Direct rarity pools exclude the hidden Graveyard Key")
	_expect(CollectionManager.get_fusion_pool("epic").is_empty(), "Direct fusion reward pools exclude world secrets")
	for pack_id: String in PackDefinition.PACK_TYPES:
		CardDatabase.set_pack_rarity_weights(PackDefinition.PACK_TYPES[pack_id]["rarity_weights"])
		_expect(CardDatabase.get_random_card_for_current_pack().is_empty(), pack_id + " pack and exhausted-rarity fallback cannot award a secret")
	CardDatabase.cards.append(CardDatabase.get_card("corpse"))
	CardDatabase.set_pack_rarity_weights({"legendary": 1.0})
	_expect(CardDatabase.get_random_card_for_current_pack().get("id") == "corpse", "Exhausted legendary pack slots fall back to an eligible card, never a secret")
	CardDatabase.cards.assign([secret, CardDatabase.get_card("plinky")])
	_expect(CardDatabase.get_random_card_by_rarity("legendary").get("id") == "plinky", "Ordinary legendary rewards remain obtainable beside a hidden secret")
	CardDatabase.cards = original_cards
	CardDatabase.set_pack_rarity_weights({})
	_expect(not CollectionManager.add_card("graveyard_key").is_empty() and CollectionManager.has_area_access("graveyard"), "Explicit world discovery still grants the unique Graveyard Key and access")
	_expect(CollectionManager.add_card("graveyard_key").is_empty() and CollectionManager.get_amount("graveyard_key") == 1, "Repeated discovery cannot duplicate an owned secret")
	# Older saves may already contain the card or a visited entrance; changing
	# reward eligibility must not revoke either form of existing progress.
	CollectionManager.collection = {"cards": {"graveyard_key": 1}, "instances": [], "metadata": {"area_access": {"graveyard": true}}}
	CollectionManager.save_collection()
	CollectionManager.collection = {"cards": {}, "instances": []}
	CollectionManager.load_collection()
	_expect(CollectionManager.get_amount("graveyard_key") == 1 and CollectionManager.has_area_access("graveyard"), "An existing owner's saved Graveyard Key and unlocked entrance survive reload")
