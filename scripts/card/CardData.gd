extends Resource
class_name CardData

const MAX_PERKS_PER_CARD := 2

static func create_instance(card_id: String, level: int = 1, perks: Array = []) -> Dictionary:
	return {
		"instance_id": _make_instance_id(card_id),
		"card_id": card_id,
		"level": max(level, 1),
		"perks": _limit_perks(perks),
	}

static func merge_card_and_instance(base_card: Dictionary, card_instance: Dictionary = {}) -> Dictionary:
	var merged := base_card.duplicate(true)
	if card_instance.is_empty():
		if not merged.has("effects"):
			merged["effects"] = []
		merged["perks"] = []
		merged["active_effects"] = _normalize_effects(merged.get("effects", []))
		return merged

	merged["instance_id"] = str(card_instance.get("instance_id", ""))
	merged["card_id"] = str(card_instance.get("card_id", merged.get("id", "")))
	merged["level"] = int(card_instance.get("level", 1))
	merged["perks"] = _limit_perks(card_instance.get("perks", []))
	merged["active_effects"] = get_active_effects(merged)
	return merged

static func get_active_effects(card_or_instance: Dictionary) -> Array[Dictionary]:
	var active: Array[Dictionary] = []
	active.append_array(_normalize_effects(card_or_instance.get("effects", [])))
	active.append_array(_normalize_effects(card_or_instance.get("perks", [])))
	return active

static func has_effect(card: Dictionary, effect_type: String) -> bool:
	for effect in get_active_effects(card):
		if str(effect.get("type", "")) == effect_type:
			return true
	return false

static func get_effect(card: Dictionary, effect_type: String) -> Dictionary:
	for effect in get_active_effects(card):
		if str(effect.get("type", "")) == effect_type:
			return effect
	return {}

static func _limit_perks(perks: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(perks) != TYPE_ARRAY:
		return result
	for perk in perks:
		if typeof(perk) != TYPE_DICTIONARY:
			continue
		result.append((perk as Dictionary).duplicate(true))
		if result.size() >= MAX_PERKS_PER_CARD:
			break
	return result

static func _normalize_effects(effects: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(effects) != TYPE_ARRAY:
		return result
	for effect in effects:
		if typeof(effect) == TYPE_DICTIONARY and str((effect as Dictionary).get("type", "")) != "":
			result.append((effect as Dictionary).duplicate(true))
	return result

static func _make_instance_id(card_id: String) -> String:
	return "%s_%s_%d" % [card_id, Time.get_unix_time_from_system(), randi()]
