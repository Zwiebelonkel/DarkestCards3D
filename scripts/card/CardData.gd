extends Resource
class_name CardData

const MAX_EFFECTS_PER_CARD := 2
const HOLO_ROLL_SIDES := 100
const INNATE_ONLY_EFFECT_TYPES := ["lava"]

static func normalize_effect(effect: Dictionary) -> Dictionary:
	var effect_type: Variant = effect.get("type", "")
	if not effect_type is String or effect_type.strip_edges().is_empty():
		return {}
	# Legacy migration only: the retired effect has no remaining gameplay or
	# presentation fields. Its old amount/name/description must not survive.
	if effect_type.strip_edges().to_lower() == "deck_burn":
		return {"type": "draw_on_kill"}
	return effect.duplicate(true)

static func is_innate_only_effect(effect_type: String) -> bool:
	return effect_type.strip_edges().to_lower() in INNATE_ONLY_EFFECT_TYPES

static func filter_instance_effects(effects: Variant) -> Array[Dictionary]:
	# Acquisition/save boundaries only. Authored base effects and synthetic
	# combat states still use the regular, unrestricted effect reader below.
	var result: Array[Dictionary] = []
	for effect in _normalize_effects(effects):
		if not is_innate_only_effect(str(effect.get("type", ""))):
			result.append(effect)
	return result

static func is_combat_card(data: Dictionary) -> bool:
	# Older cards have no category and remain valid combat cards.
	return not data.is_empty() and str(data.get("category", "combat")).to_lower() not in ["special", "event"]

static func is_upgrade_collection_card(data: Dictionary) -> bool:
	var card_id := str(data.get("id", data.get("card_id", "")))
	return str(data.get("category", "")).to_lower() == "special" and card_id != "slot_room_key"

static func is_unique_unlock(data: Dictionary) -> bool:
	return str(data.get("category", "")).to_lower() == "special" and data.get("unique_unlock", false) == true

static func create_instance(card_id: String, level: int = 1, effects: Array = [], is_holo: bool = false) -> Dictionary:
	return {
		"instance_id": _make_instance_id(card_id),
		"card_id": card_id,
		"level": max(level, 1),
		"effects": _limit_effects(filter_instance_effects(effects)),
		"is_holo": is_holo,
	}

static func roll_holo(roll: int = -1) -> bool:
	# Exactly one of 100 equally likely outcomes, independently for each new
	# acquisition. Explicit rolls make boundary tests deterministic.
	return (randi_range(0, HOLO_ROLL_SIDES - 1) if roll < 0 else roll) == 0

static func is_holo(data: Dictionary) -> bool:
	return data.get("is_holo", false) == true

static func with_instance_metadata(base_card: Dictionary, instance: Dictionary = {}) -> Dictionary:
	var result := base_card.duplicate(true)
	result["is_holo"] = is_holo(instance) if not instance.is_empty() else is_holo(base_card)
	if not instance.is_empty():
		result["instance_id"] = str(instance.get("instance_id", ""))
		result["card_id"] = str(instance.get("card_id", result.get("id", "")))
		result["level"] = maxi(int(instance.get("level", 1)), 1)
	return result

static func merge_card_and_instance(base_card: Dictionary, card_instance: Dictionary = {}) -> Dictionary:
	var merged := with_instance_metadata(base_card, card_instance)
	if not is_combat_card(merged):
		merged["effects"] = []
		merged["active_effects"] = []
		if not card_instance.is_empty():
			merged["instance_id"] = str(card_instance.get("instance_id", ""))
			merged["card_id"] = str(card_instance.get("card_id", merged.get("id", "")))
			merged["level"] = int(card_instance.get("level", 1))
		return merged
	var base_effects := _normalize_effects(merged.get("effects", []))
	var instance_effects := filter_instance_effects(card_instance.get("effects", []))

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
	if not is_combat_card(card_or_instance):
		return []
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
	for effect in _normalize_effects(effects):
		result.append(effect)
		if result.size() >= MAX_EFFECTS_PER_CARD:
			break
	return result

static func _normalize_effects(effects: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(effects) != TYPE_ARRAY:
		return result
	var has_mailman := false
	for effect in effects:
		if not effect is Dictionary:
			continue
		var normalized := normalize_effect(effect)
		if normalized.is_empty():
			continue
		if str(normalized.get("type", "")) == "draw_on_kill":
			if has_mailman:
				continue
			has_mailman = true
		result.append(normalized)
	return result

static func _combine_effects(first: Array[Dictionary], second: Array[Dictionary]) -> Array[Dictionary]:
	var combined: Array[Dictionary] = []
	combined.append_array(first)
	combined.append_array(second)
	return combined

static func _make_instance_id(card_id: String) -> String:
	return "%s_%s_%d" % [card_id, Time.get_unix_time_from_system(), randi()]
