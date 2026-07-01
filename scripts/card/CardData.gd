extends Resource
class_name CardData

const MAX_EFFECTS_PER_CARD := 2

static func create_instance(card_id: String, level: int = 1, effects: Array = []) -> Dictionary:
	return {
		"instance_id": _make_instance_id(card_id),
		"card_id": card_id,
		"level": max(level, 1),
		"effects": _limit_effects(effects),
	}

static func merge_card_and_instance(base_card: Dictionary, card_instance: Dictionary = {}) -> Dictionary:
	var merged := base_card.duplicate(true)
	var base_effects := _normalize_effects(merged.get("effects", []))
	var instance_effects := _normalize_effects(card_instance.get("effects", []))

	if card_instance.is_empty():
		merged["effects"] = _limit_effects(base_effects)
		merged["active_effects"] = merged["effects"]
		return merged

	merged["instance_id"] = str(card_instance.get("instance_id", ""))
	merged["card_id"] = str(card_instance.get("card_id", merged.get("id", "")))
	merged["level"] = int(card_instance.get("level", 1))
	merged["effects"] = _limit_effects(_combine_effects(base_effects, instance_effects))
	merged["active_effects"] = merged["effects"]
	return merged

static func get_active_effects(card_or_instance: Dictionary) -> Array[Dictionary]:
	return _limit_effects(card_or_instance.get("active_effects", card_or_instance.get("effects", [])))

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

static func _limit_effects(effects: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(effects) != TYPE_ARRAY:
		return result
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var normalized_effect := (effect as Dictionary).duplicate(true)
		if str(normalized_effect.get("type", "")) == "":
			continue
		result.append(normalized_effect)
		if result.size() >= MAX_EFFECTS_PER_CARD:
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

static func _combine_effects(first: Array[Dictionary], second: Array[Dictionary]) -> Array[Dictionary]:
	var combined: Array[Dictionary] = []
	combined.append_array(first)
	combined.append_array(second)
	return combined

static func _make_instance_id(card_id: String) -> String:
	return "%s_%s_%d" % [card_id, Time.get_unix_time_from_system(), randi()]
