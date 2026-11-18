extends RefCounted
class_name OfflineMatchRules

const LEVEL_COUNT := 100
const STORY_STAT_GROWTH := 0.95
const TRAINING_DECK_SIZE := 5
const MAX_TRAINING_STAT := 1000000
const STORY_RARITIES := ["common", "uncommon", "rare", "epic", "legendary", "mythic", "exotic"]
# Percentages at campaign milestones; interpolate between them each level.
const STORY_RARITY_MILESTONES := {
	1: [100, 0, 0, 0, 0, 0, 0],
	20: [55, 35, 10, 0, 0, 0, 0],
	40: [20, 35, 30, 15, 0, 0, 0],
	60: [5, 15, 30, 30, 20, 0, 0],
	80: [0, 5, 15, 30, 30, 15, 5],
	100: [0, 0, 5, 15, 30, 30, 20],
}


static func story_card_value(level: int) -> int:
	var steps := clampi(level, 1, LEVEL_COUNT) - 1
	return 4 + roundi(steps * STORY_STAT_GROWTH) + roundi(steps * 2.0 * STORY_STAT_GROWTH)


static func story_rewards(level: int) -> Dictionary:
	return {"xp": 50 + 10 * (level - 1), "coins": 5 + (level - 1)}


static func story_rarity_weights(level: int) -> Dictionary:
	var target := clampi(level, 1, LEVEL_COUNT)
	var lower := 1
	var upper := LEVEL_COUNT
	for milestone: int in STORY_RARITY_MILESTONES:
		if milestone <= target:
			lower = milestone
		if milestone >= target:
			upper = milestone
			break
	var blend := 0.0 if lower == upper else float(target - lower) / float(upper - lower)
	var weights := {}
	for index in range(STORY_RARITIES.size()):
		weights[STORY_RARITIES[index]] = lerpf(float(STORY_RARITY_MILESTONES[lower][index]), float(STORY_RARITY_MILESTONES[upper][index]), blend)
	return weights


static func story_deck(level: int, count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if level < 1 or level > LEVEL_COUNT or count <= 0:
		return result
	var pools := {}
	for rarity: String in STORY_RARITIES:
		pools[rarity] = []
	for card: Dictionary in CardDatabase.get_combat_cards():
		var rarity := str(card.get("rarity", "")).to_lower()
		if not pools.has(rarity):
			continue
		# Preserve the gentle opening; discovery-only Secrets are not in pools.
		if rarity == "common" and int(card.get("attack", 0)) + int(card.get("defense", 0)) > 10:
			continue
		pools[rarity].append(card)
	var weights := story_rarity_weights(level)
	var total_weight := 0.0
	for rarity: String in STORY_RARITIES:
		pools[rarity].sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
		if not pools[rarity].is_empty():
			total_weight += float(weights[rarity])
	if total_weight <= 0.0:
		return result
	var used := {}
	for index in range(count):
		# Evenly spaced quantiles give small decks a reliable rarity mix. The
		# match shuffles afterwards, so rarities are not drawn in sorted order.
		var roll := (float(index) + 0.5) / float(count) * total_weight
		var cumulative := 0.0
		for rarity: String in STORY_RARITIES:
			if pools[rarity].is_empty():
				continue
			cumulative += float(weights[rarity])
			if roll >= cumulative:
				continue
			var offset := int(used.get(rarity, 0))
			var card: Dictionary = pools[rarity][offset % pools[rarity].size()].duplicate(true)
			used[rarity] = offset + 1
			card["attack"] = 1 + roundi((level - 1) * STORY_STAT_GROWTH)
			card["defense"] = story_card_value(level) - int(card["attack"])
			result.append(CardData.merge_card_and_instance(card))
			break
	return result


static func training_card(attack: int, defense: int) -> Dictionary:
	return {
		"id": "training_dummy", "name": "Trainingskarte", "category": "combat",
		"rarity": "common", "image": "res://assets/cards/training_target.svg",
		"description": "Frei einstellbare Trainingskarte.", "effects": [],
		"attack": clampi(attack, 0, MAX_TRAINING_STAT),
		"defense": clampi(defense, 1, MAX_TRAINING_STAT), "training_dummy": true,
	}


static func training_player_deck(pool: Array[Dictionary], indices: Array[int]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var used: Array[int] = []
	if indices.size() != TRAINING_DECK_SIZE:
		return result
	for index in indices:
		if index < 0 or index >= pool.size() or used.has(index) or not CardData.is_combat_card(pool[index]):
			return []
		used.append(index)
		result.append(pool[index].duplicate(true))
	return result


static func training_enemy_deck(entries: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if entries.size() != TRAINING_DECK_SIZE:
		return result
	for entry in entries:
		if entry.get("training_dummy", false) == true:
			var dummy := training_card(int(entry.get("attack", 0)), int(entry.get("defense", 1)))
			dummy["training_slot"] = result.size() + 1
			result.append(dummy)
		else:
			var card: Dictionary = CardDatabase.get_card(str(entry.get("id", "")))
			if not CardData.is_combat_card(card):
				return []
			result.append(CardData.merge_card_and_instance(card))
	return result
