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
			"effects": [],
			"removed_base_effect_indices": []
		}

	if not upgrades[card_id].has("removed_base_effect_indices"):
		upgrades[card_id]["removed_base_effect_indices"] = []

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
	if get_free_effect_slots(card_id) <= 0:
		return false

	var entry := _get_entry(card_id)
	var effects: Array = entry.get("effects", [])

	effects.append(effect.duplicate(true))
	entry["effects"] = _limit_upgrade_effects_for_card(card_id, effects)

	upgrades[card_id] = entry
	save_upgrades()
	upgrades_changed.emit(card_id)

	return true

func remove_last_effect(card_id: String) -> bool:
	if not upgrades.has(card_id):
		return false

	var entry := _get_entry(card_id)
	var effects: Array = entry.get("effects", [])

	if effects.is_empty():
		return false

	effects.remove_at(effects.size() - 1)

	entry["effects"] = effects
	upgrades[card_id] = entry

	save_upgrades()
	upgrades_changed.emit(card_id)

	return true
	
func get_upgrade_effects(card_id: String) -> Array:
	var entry := _get_entry(card_id)
	return _limit_upgrade_effects_for_card(card_id, entry.get("effects", []))
	
func get_free_effect_slots(card_id: String) -> int:
	var base_count := get_base_effect_count(card_id)
	var upgrade_count := get_upgrade_effects(card_id).size()

	return max(CardData.MAX_EFFECTS_PER_CARD - base_count - upgrade_count, 0)
	
func _limit_upgrade_effects_for_card(card_id: String, effects: Variant) -> Array:
	var limited: Array[Dictionary] = []
	var max_upgrade_count :int= max(CardData.MAX_EFFECTS_PER_CARD - get_base_effect_count(card_id), 0)

	if not (effects is Array):
		return limited

	for effect in effects:
		if limited.size() >= max_upgrade_count:
			break

		if effect is Dictionary:
			limited.append(effect.duplicate(true))

	return limited
	
func get_base_effect_count(card_id: String) -> int:
	return get_base_effects(card_id).size()

func apply_upgrades(card_id: String, data: Dictionary) -> Dictionary:
	var result := data.duplicate(true)
	var entry := _get_entry(card_id)

	result["attack"] = int(result.get("attack", 0)) + int(entry.get("attack_bonus", 0))
	result["defense"] = int(result.get("defense", 0)) + int(entry.get("health_bonus", 0))

	var combined_effects: Array = []

	for effect in get_base_effects(card_id):
		if effect is Dictionary:
			combined_effects.append(effect.duplicate(true))

	for effect in get_upgrade_effects(card_id):
		if effect is Dictionary:
			combined_effects.append(effect.duplicate(true))

	result["effects"] = CardData._limit_effects(combined_effects)

	return result

func get_attack_bonus(card_id: String) -> int:
	return int(_get_entry(card_id).get("attack_bonus", 0))


func get_health_bonus(card_id: String) -> int:
	return int(_get_entry(card_id).get("health_bonus", 0))


func get_effects(card_id: String) -> Array:
	return get_upgrade_effects(card_id)


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
		cfg.set_value(card_id, "effects", _limit_upgrade_effects_for_card(card_id, entry.get("effects", [])))
		cfg.set_value(card_id, "removed_base_effect_indices", entry.get("removed_base_effect_indices", []))

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
			"effects": _limit_upgrade_effects_for_card(section, cfg.get_value(section, "effects", [])),
			"removed_base_effect_indices": cfg.get_value(section, "removed_base_effect_indices", [])
		}

func _limit_effects(effects: Variant) -> Array[Dictionary]:
	return CardData._limit_effects(effects)

func get_effect_entries(card_id: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []

	var base_card := CardDatabase.get_card(card_id)

	if not base_card.is_empty():
		var base_effects: Array = CardData.get_active_effects(base_card)
		var removed_indices: Array = _get_entry(card_id).get("removed_base_effect_indices", [])

		for i in range(base_effects.size()):
			if removed_indices.has(i):
				continue

			var effect = base_effects[i]

			if effect is Dictionary:
				entries.append({
					"source": "base",
					"index": i,
					"effect": effect.duplicate(true)
				})

	var upgrade_effects: Array = get_upgrade_effects(card_id)

	for i in range(upgrade_effects.size()):
		var effect = upgrade_effects[i]

		if effect is Dictionary:
			entries.append({
				"source": "upgrade",
				"index": i,
				"effect": effect.duplicate(true)
			})

	return entries
	
func remove_effect_at(card_id: String, effect_source: String, effect_index: int) -> bool:
	var entry := _get_entry(card_id)

	if effect_source == "upgrade":
		var effects: Array = entry.get("effects", [])

		if effect_index < 0 or effect_index >= effects.size():
			return false

		effects.remove_at(effect_index)

		entry["effects"] = effects
		upgrades[card_id] = entry

		save_upgrades()
		upgrades_changed.emit(card_id)

		return true

	if effect_source == "base":
		var base_card := CardDatabase.get_card(card_id)

		if base_card.is_empty():
			return false

		var base_effects: Array = CardData.get_active_effects(base_card)

		if effect_index < 0 or effect_index >= base_effects.size():
			return false

		var removed_indices: Array = entry.get("removed_base_effect_indices", [])

		if removed_indices.has(effect_index):
			return false

		removed_indices.append(effect_index)
		removed_indices.sort()

		entry["removed_base_effect_indices"] = removed_indices
		upgrades[card_id] = entry

		save_upgrades()
		upgrades_changed.emit(card_id)

		return true

	return false

func get_base_effects(card_id: String) -> Array[Dictionary]:
	var base_card := CardDatabase.get_card(card_id)

	if base_card.is_empty():
		return []

	var base_effects: Array = CardData.get_active_effects(base_card)
	var removed_indices: Array = _get_entry(card_id).get("removed_base_effect_indices", [])

	var visible_effects: Array[Dictionary] = []

	for i in range(base_effects.size()):
		if removed_indices.has(i):
			continue

		var effect = base_effects[i]

		if effect is Dictionary:
			visible_effects.append(effect.duplicate(true))

	return visible_effects
