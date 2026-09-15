extends Node

const CARDS_PATH := "res://data/cards.json"
const REWARD_RARITIES: Array[String] = ["common", "uncommon", "rare", "epic", "legendary", "mythic", "exotic", "secret"]
const RARE_OR_HIGHER: Array[String] = ["rare", "epic", "legendary", "mythic", "exotic", "secret"]
const DEFAULT_SECRET_WEIGHT := 0.001
const MAX_SECRET_WEIGHT := 0.01
const NO_REWARD_RARITY := "_no_reward"

var cards: Array[Dictionary] = []
var cards_by_id: Dictionary = {}
var _current_pack_weights := {}
var _cheat_reward_rarities: Array[String] = REWARD_RARITIES.duplicate()


func _ready() -> void:
	load_cards()


func load_cards() -> void:
	cards.clear()
	cards_by_id.clear()
	
	if not FileAccess.file_exists(CARDS_PATH):
		push_error("cards.json nicht gefunden: " + CARDS_PATH)
		return
	
	var file := FileAccess.open(CARDS_PATH, FileAccess.READ)
	if file == null:
		push_error("cards.json konnte nicht geöffnet werden.")
		return
	
	var text := file.get_as_text()
	file.close()
	
	var parsed = JSON.parse_string(text)
	
	if typeof(parsed) != TYPE_ARRAY:
		push_error("cards.json muss ein Array sein.")
		return
	
	for entry in parsed:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		
		var card: Dictionary = entry
		var id := str(card.get("id", "")).strip_edges()
		
		if id == "":
			push_warning("Karte ohne ID übersprungen.")
			continue
		
		if cards_by_id.has(id):
			push_warning("Doppelte Karten-ID gefunden: " + id)
			continue
		
		cards.append(card)
		cards_by_id[id] = card
	
	print("CardDatabase geladen: ", cards.size(), " Karten")


func get_card(card_id: String) -> Dictionary:
	if not cards_by_id.has(card_id):
		push_warning("Karte nicht gefunden: " + card_id)
		return {}
	
	return cards_by_id[card_id]


func has_card(card_id: String) -> bool:
	return cards_by_id.has(card_id)


func is_event_card(card: Dictionary) -> bool:
	if str(card.get("category", "")).to_lower() == "event":
		return true
	# Match-event IDs stay reserved even if an old or imported definition is
	# missing its category. Events belong to the shared match deck, not packs.
	var card_id := str(card.get("id", card.get("card_id", "")))
	for event: Dictionary in EventDeck.CARD_DEFINITIONS:
		if str(event.get("id", "")) == card_id:
			return true
	return false


func is_collectible_card(card_id: String) -> bool:
	return has_card(card_id) and not is_event_card(cards_by_id[card_id])


func get_all_cards() -> Array[Dictionary]:
	return cards.duplicate(true)


func get_combat_cards() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for card in cards:
		if CardData.is_combat_card(card):
			result.append(card.duplicate(true))
	return result


func get_cards_by_rarity(rarity: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var target := rarity.to_lower()
	
	for card in cards:
		if _is_random_reward(card) and str(card.get("rarity", "")).to_lower() == target:
			result.append(card)
	
	return result


func get_random_card() -> Dictionary:
	return _select_reward(_get_eligible_rewards())


func get_random_card_by_rarity(rarity: String) -> Dictionary:
	var pool: Array[Dictionary] = []
	for card in _get_eligible_rewards():
		if str(card.get("rarity", "")).to_lower() == rarity.to_lower():
			pool.append(card)
	# A fixed-rarity reward must never change its promised rarity.
	return _pick_weighted_card(pool)
	

func set_pack_rarity_weights(weights: Dictionary) -> void:
	_current_pack_weights = weights.duplicate()


func set_cheat_reward_rarities(rarities: Array[String]) -> void:
	_cheat_reward_rarities.clear()
	for rarity in REWARD_RARITIES:
		if rarities.has(rarity):
			_cheat_reward_rarities.append(rarity)
	if _cheat_reward_rarities.is_empty():
		_cheat_reward_rarities.assign(REWARD_RARITIES)


func _has_cheat_rarity_filter() -> bool:
	return _cheat_reward_rarities.size() < REWARD_RARITIES.size()


func get_random_card_for_current_pack(pending_card_ids: Array[String] = []) -> Dictionary:
	return _select_reward(_get_eligible_rewards(pending_card_ids), _current_pack_weights)


func has_regular_pack_rewards() -> bool:
	for card in _get_eligible_rewards():
		if _has_cheat_rarity_filter():
			# A repeatable selected reward can fill every slot, even after the
			# pack has reserved all eligible one-time unlocks.
			if _cheat_reward_rarities.has(str(card.get("rarity", "common")).to_lower()) and not CardData.is_unique_unlock(card):
				return true
			continue
		if str(card.get("rarity", "common")).to_lower() != "secret":
			return true
	return false


func _get_eligible_rewards(pending_card_ids: Array[String] = []) -> Array[Dictionary]:
	var eligible_cards: Array[Dictionary] = []
	for card in cards:
		if not _is_random_reward(card) or float(card.get("reward_weight", 1.0)) <= 0.0:
			continue
		var card_id := str(card.get("id", ""))
		if not CollectionManager.can_obtain_card(card_id):
			continue
		# Pack cards are revealed and collected later, so ownership alone does
		# not exclude a second unlock card within this same pack.
		if CardData.is_unique_unlock(card) and pending_card_ids.has(card_id):
			continue
		eligible_cards.append(card)
	return eligible_cards


func _select_reward(eligible_cards: Array[Dictionary], rarity_weights: Dictionary = {}, rarity_roll: float = -1.0, card_roll: float = -1.0) -> Dictionary:
	if eligible_cards.is_empty():
		return {}
	var selected_rarity := _roll_rarity(get_reward_rarity_weights(eligible_cards, rarity_weights), rarity_roll)
	if selected_rarity == NO_REWARD_RARITY:
		return {}
	var pool: Array[Dictionary] = []
	for card in eligible_cards:
		if str(card.get("rarity", "")).to_lower() == selected_rarity:
			pool.append(card)
	return _pick_weighted_card(pool, card_roll)


func get_reward_rarity_weights(eligible_cards: Array[Dictionary], rarity_weights: Dictionary = {}, lucky_bonus: float = -1.0) -> Dictionary:
	var weights := _get_unfiltered_reward_rarity_weights(eligible_cards, rarity_weights, lucky_bonus)
	if not _has_cheat_rarity_filter():
		return weights
	var selected_weights := {}
	var fallback_weights := {}
	for card in eligible_cards:
		var rarity := str(card.get("rarity", "common")).to_lower()
		var mass := maxf(float(card.get("reward_weight", 1.0)), 0.0)
		if not _cheat_reward_rarities.has(rarity) or mass <= 0.0:
			continue
		fallback_weights[rarity] = float(fallback_weights.get(rarity, 0.0)) + mass
		if float(weights.get(rarity, 0.0)) > 0.0:
			selected_weights[rarity] = float(weights[rarity])
	# Explicit cheats may select a rarity absent from a pack's normal table.
	# Pool fallback stays inside the selection and never restores disabled tiers.
	if selected_weights.is_empty():
		selected_weights = get_adjusted_rarity_weights(fallback_weights, lucky_bonus)
	var total := 0.0
	for value in selected_weights.values():
		total += float(value)
	if total <= 0.0:
		return {NO_REWARD_RARITY: 100.0}
	for rarity in selected_weights:
		selected_weights[rarity] = 100.0 * float(selected_weights[rarity]) / total
	return selected_weights


func _get_unfiltered_reward_rarity_weights(eligible_cards: Array[Dictionary], rarity_weights: Dictionary = {}, lucky_bonus: float = -1.0) -> Dictionary:
	# Return probability mass totalling 100 (including a possible empty result).
	# Secret's chance comes from the original pack table, before exhausted
	# rarities are removed. Pool exhaustion must never turn it into a guarantee.
	if eligible_cards.is_empty():
		return {NO_REWARD_RARITY: 100.0}
	var available_weights := {}
	for card in eligible_cards:
		var rarity := str(card.get("rarity", "common")).to_lower()
		var mass := maxf(float(card.get("reward_weight", 1.0)), 0.0)
		if mass > 0.0:
			available_weights[rarity] = float(available_weights.get(rarity, 0.0)) + mass
	var ordinary_weights := {}
	var configured_total := 0.0
	var configured_secret := 0.0
	for key in rarity_weights:
		var rarity := str(key).to_lower()
		var mass := maxf(float(rarity_weights[key]), 0.0)
		configured_total += mass
		if rarity == "secret":
			configured_secret += mass
		elif available_weights.has(rarity) and mass > 0.0:
			ordinary_weights[rarity] = float(ordinary_weights.get(rarity, 0.0)) + mass
	var fallback := ordinary_weights.is_empty()
	if fallback:
		# Keep the historical relative per-card fallback for ordinary cards.
		for rarity in available_weights:
			if rarity != "secret":
				ordinary_weights[rarity] = available_weights[rarity]
	var secret_weight := 0.0
	if available_weights.has("secret"):
		if configured_secret > 0.0 and configured_total > 0.0:
			secret_weight = minf(100.0 * configured_secret / configured_total, MAX_SECRET_WEIGHT)
		elif fallback:
			secret_weight = DEFAULT_SECRET_WEIGHT
	var ordinary_total := 0.0
	for value in ordinary_weights.values():
		ordinary_total += float(value)
	var result := {}
	if secret_weight > 0.0:
		result["secret"] = secret_weight
	if ordinary_total > 0.0:
		for rarity in ordinary_weights:
			result[rarity] = float(ordinary_weights[rarity]) / ordinary_total * (100.0 - secret_weight)
	else:
		# With no ordinary fallback there is deliberately no reward on a miss.
		# Callers must handle an empty draw, not repeatedly roll until Secret wins.
		result[NO_REWARD_RARITY] = 100.0 - secret_weight
	return get_adjusted_rarity_weights(result, lucky_bonus)


func get_adjusted_rarity_weights(weights: Dictionary, lucky_bonus: float = -1.0) -> Dictionary:
	# Relative, not percentage-point, bonus: 20% rare+ becomes 21% at +5%.
	# Transfer common mass first, then uncommon if common cannot cover it.
	# A guaranteed rarity (or an all-rare+ pool) consequently stays unchanged.
	var result := {}
	var rare_total := 0.0
	for key in weights:
		var rarity := str(key).to_lower()
		var weight := maxf(float(weights[key]), 0.0)
		result[rarity] = float(result.get(rarity, 0.0)) + weight
		if rarity in RARE_OR_HIGHER:
			rare_total += weight
	var bonus := CollectionManager.get_lucky_coin_bonus() if lucky_bonus < 0.0 else lucky_bonus
	if bonus <= 0.0 or rare_total <= 0.0:
		return result
	var available := float(result.get("common", 0.0)) + float(result.get("uncommon", 0.0))
	var transferred := minf(rare_total * bonus, available)
	var remaining := transferred
	for rarity in ["common", "uncommon"]:
		if not result.has(rarity):
			continue
		var taken := minf(float(result[rarity]), remaining)
		result[rarity] = float(result[rarity]) - taken
		remaining -= taken
	for rarity in RARE_OR_HIGHER:
		if result.has(rarity):
			result[rarity] = float(result[rarity]) * (1.0 + transferred / rare_total)
	return result


func _pick_weighted_card(pool: Array[Dictionary], normalized_roll: float = -1.0) -> Dictionary:
	var total := 0.0
	for card in pool:
		total += maxf(float(card.get("reward_weight", 1.0)), 0.0)
	if total <= 0.0:
		return {}
	var roll := (randf() if normalized_roll < 0.0 else clampf(normalized_roll, 0.0, 1.0)) * total
	for card in pool:
		roll -= maxf(float(card.get("reward_weight", 1.0)), 0.0)
		if roll < 0.0:
			return card
	return pool.back()


func _is_random_reward(card: Dictionary) -> bool:
	# World-discovery cards are distinct from the ultra-rare Secret rarity.
	# Their explicit acquisition-only flag always excludes random rewards.
	return not is_event_card(card) and card.get("random_reward", true) != false


func _roll_rarity(weights: Dictionary, normalized_roll: float = -1.0) -> String:
	var total := 0.0

	for value in weights.values():
		total += maxf(float(value), 0.0)

	if total <= 0.0:
		return "common"

	var roll := (randf() if normalized_roll < 0.0 else clampf(normalized_roll, 0.0, 1.0)) * total
	var current := 0.0
	var last_rarity := "common"

	for rarity in weights.keys():
		var mass := maxf(float(weights[rarity]), 0.0)
		if mass > 0.0:
			last_rarity = str(rarity)
		current += mass

		if roll < current:
			return str(rarity)

	return last_rarity
