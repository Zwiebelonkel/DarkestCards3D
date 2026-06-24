extends RefCounted
class_name CombatResolver

static func get_active_effects(card: Card3D) -> Array[Dictionary]:
	return CardData.get_active_effects(card.card_data)

static func get_hit_count(attacker: Card3D) -> int:
	if CardData.has_effect(attacker.card_data, "triple_strike"):
		return 3
	if CardData.has_effect(attacker.card_data, "double_strike"):
		return 2
	return 1

static func get_attack_damage(attacker: Card3D, identical_on_board: int = 1) -> int:
	var damage := attacker.attack_value
	if CardData.has_effect(attacker.card_data, "swarm_power"):
		damage *= max(identical_on_board, 1)
	var random_damage := CardData.get_effect(attacker.card_data, "random_damage")
	if not random_damage.is_empty():
		damage = int(round(float(damage) * randf_range(float(random_damage.get("min", 0.75)), float(random_damage.get("max", 1.25)))))
	return max(damage, 0)

static func apply_incoming_damage(defender: Card3D, raw_damage: int) -> Dictionary:
	var damage : float= max(raw_damage, 0)
	if defender.consume_first_hit_shield():
		damage = 0
	else:
		var armor := CardData.get_effect(defender.card_data, "armor")
		if not armor.is_empty():
			damage = int(round(float(damage) * (1.0 - clamp(float(armor.get("value", 0.0)), 0.0, 0.95))))
	var died := defender.take_damage(damage)
	if died and defender.try_survive_death():
		died = false
	return {"damage": damage, "died": died}

static func heal_from_lifesteal(attacker: Card3D, damage_done: int) -> void:
	var lifesteal := CardData.get_effect(attacker.card_data, "lifesteal")
	if lifesteal.is_empty() or damage_done <= 0:
		return
	attacker.heal(int(round(float(damage_done) * float(lifesteal.get("percent", 0.0)))))

static func apply_thorns(defender: Card3D, attacker: Card3D, damage_taken: int) -> bool:
	var thorns := CardData.get_effect(defender.card_data, "thorns")
	if thorns.is_empty() or damage_taken <= 0:
		return false
	var reflected := int(round(float(damage_taken) * float(thorns.get("percent", 0.25))))
	return attacker.take_damage(max(reflected, 0))
