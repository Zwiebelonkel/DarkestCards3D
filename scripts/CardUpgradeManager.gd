extends Node

var upgrades: Dictionary = {}


func _ready() -> void:
	load_upgrades()


func _get_entry(card_id: String) -> Dictionary:
	if not upgrades.has(card_id):
		upgrades[card_id] = {
			"attack_bonus": 0,
			"health_bonus": 0,
			"perks": []
		}

	return upgrades[card_id]


func add_attack(card_id: String, amount: int = 1) -> void:
	var entry := _get_entry(card_id)
	entry["attack_bonus"] = int(entry.get("attack_bonus", 0)) + amount
	upgrades[card_id] = entry
	save_upgrades()


func add_health(card_id: String, amount: int = 1) -> void:
	var entry := _get_entry(card_id)
	entry["health_bonus"] = int(entry.get("health_bonus", 0)) + amount
	upgrades[card_id] = entry
	save_upgrades()


func add_perk(card_id: String, perk: Dictionary) -> void:
	var entry := _get_entry(card_id)
	var perks: Array = entry.get("perks", [])
	perks.append(perk)
	entry["perks"] = perks
	upgrades[card_id] = entry
	save_upgrades()


func apply_upgrades(card_id: String, data: Dictionary) -> Dictionary:
	var result := data.duplicate(true)

	if not upgrades.has(card_id):
		return result

	var entry: Dictionary = upgrades[card_id]

	result["attack"] = int(result.get("attack", 0)) + int(entry.get("attack_bonus", 0))
	result["defense"] = int(result.get("defense", 0)) + int(entry.get("health_bonus", 0))

	if not result.has("perks"):
		result["perks"] = []

	var result_perks: Array = result.get("perks", [])
	for perk in entry.get("perks", []):
		result_perks.append(perk)

	result["perks"] = result_perks

	return result


func get_attack_bonus(card_id: String) -> int:
	return int(_get_entry(card_id).get("attack_bonus", 0))


func get_health_bonus(card_id: String) -> int:
	return int(_get_entry(card_id).get("health_bonus", 0))


func get_perks(card_id: String) -> Array:
	return _get_entry(card_id).get("perks", [])


func save_upgrades() -> void:
	var cfg := ConfigFile.new()

	for card_id in upgrades.keys():
		var entry: Dictionary = upgrades[card_id]
		cfg.set_value(card_id, "attack_bonus", int(entry.get("attack_bonus", 0)))
		cfg.set_value(card_id, "health_bonus", int(entry.get("health_bonus", 0)))
		cfg.set_value(card_id, "perks", entry.get("perks", []))

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
			"perks": cfg.get_value(section, "perks", [])
		}
