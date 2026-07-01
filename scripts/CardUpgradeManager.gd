extends Node

var upgrades: Dictionary = {}

signal upgrades_changed(card_id: String)

func _ready() -> void:
	load_upgrades()


func _get_entry(card_id: String) -> Dictionary:
	if not upgrades.has(card_id):
		upgrades[card_id] = {
			"attack_bonus": 0,
			"health_bonus": 0,
			"effects": []
		}

	return upgrades[card_id]


func add_attack(card_id: String, amount: int = 1) -> void:
	var entry := _get_entry(card_id)
	entry["attack_bonus"] = int(entry.get("attack_bonus", 0)) + amount
	upgrades[card_id] = entry
	save_upgrades()
	upgrades_changed.emit(card_id)


func add_health(card_id: String, amount: int = 1) -> void:
	var entry := _get_entry(card_id)
	entry["health_bonus"] = int(entry.get("health_bonus", 0)) + amount
	upgrades[card_id] = entry
	save_upgrades()
	upgrades_changed.emit(card_id)


func add_effect(card_id: String, effect: Dictionary) -> bool:
	if get_active_effect_count(card_id) >= CardData.MAX_EFFECTS_PER_CARD:
		return false

	var entry := _get_entry(card_id)
	var effects: Array = entry.get("effects", [])
	effects.append(effect.duplicate(true))
	entry["effects"] = _limit_effects(effects)
	upgrades[card_id] = entry
	save_upgrades()
	upgrades_changed.emit(card_id)
	return true


func apply_upgrades(card_id: String, data: Dictionary) -> Dictionary:
	var result := data.duplicate(true)

	if not upgrades.has(card_id):
		return result

	var entry: Dictionary = upgrades[card_id]

	result["attack"] = int(result.get("attack", 0)) + int(entry.get("attack_bonus", 0))
	result["defense"] = int(result.get("defense", 0)) + int(entry.get("health_bonus", 0))

	if not result.has("effects"):
		result["effects"] = []

	var result_effects: Array = result.get("effects", [])
	for effect in entry.get("effects", []):
		result_effects.append(effect)

	result["effects"] = _limit_effects(result_effects)

	return result


func get_attack_bonus(card_id: String) -> int:
	return int(_get_entry(card_id).get("attack_bonus", 0))


func get_health_bonus(card_id: String) -> int:
	return int(_get_entry(card_id).get("health_bonus", 0))


func get_effects(card_id: String) -> Array:
	var entry := _get_entry(card_id)
	return _limit_effects(entry.get("effects", []))


func get_active_effect_count(card_id: String) -> int:
	var base_card := CardDatabase.get_card(card_id)
	if base_card.is_empty():
		return get_effects(card_id).size()
	return CardData.get_active_effects(apply_upgrades(card_id, base_card)).size()


func save_upgrades() -> void:
	var cfg := ConfigFile.new()

	for card_id in upgrades.keys():
		var entry: Dictionary = upgrades[card_id]
		cfg.set_value(card_id, "attack_bonus", int(entry.get("attack_bonus", 0)))
		cfg.set_value(card_id, "health_bonus", int(entry.get("health_bonus", 0)))
		cfg.set_value(card_id, "effects", _limit_effects(entry.get("effects", [])))

	cfg.save("user://card_upgrades.cfg")


func load_upgrades() -> void:
	upgrades.clear()

	var cfg := ConfigFile.new()
	if cfg.load("user://card_upgrades.cfg") != OK:
		return

	for section in cfg.get_sections():
		upgrades[section] = {
			"attack_bonus": int(cfg.get_value(section, "attack_bonus", 0)),
			"health_bonus": int(cfg.get_value(section, "health_bonus", 0)),
			"effects": _limit_effects(cfg.get_value(section, "effects", []))
		}


func _limit_effects(effects: Variant) -> Array[Dictionary]:
	return CardData._limit_effects(effects)
