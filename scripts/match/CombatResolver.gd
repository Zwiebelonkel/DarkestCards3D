extends RefCounted
class_name CombatResolver

const RANDOM_DAMAGE_LOW := 0.75
const RANDOM_DAMAGE_HIGH := 2.0

static func get_active_effects(card: Card3D) -> Array[Dictionary]:
	return CardData.get_active_effects(card.card_data)

static func get_hit_count(attacker: Card3D) -> int:
	var triple := CardData.get_effect(attacker.card_data, "triple_strike")
	if not triple.is_empty():
		return clampi(int(triple.get("hits", 3)), 1, 8)
	var double := CardData.get_effect(attacker.card_data, "double_strike")
	if not double.is_empty():
		return clampi(int(double.get("hits", 2)), 1, 8)
	return 1

static func roll_attack_multiplier(attacker: Card3D) -> float:
	if not CardData.has_effect(attacker.card_data, "random_damage"):
		return 1.0
	return RANDOM_DAMAGE_LOW if randi() % 2 == 0 else RANDOM_DAMAGE_HIGH


static func get_attack_damage(attacker: Card3D, identical_on_board: int = 1, rolled_multiplier: float = -1.0) -> int:
	var damage := attacker.attack_value
	if CardData.has_effect(attacker.card_data, "swarm_power"):
		damage *= max(identical_on_board, 1)
	if CardData.has_effect(attacker.card_data, "random_damage"):
		var multiplier := roll_attack_multiplier(attacker) if rolled_multiplier < 0.0 else rolled_multiplier
		damage = roundi(float(damage) * multiplier)
	return max(damage, 0)

## Pure mitigation: callers such as Bodyguard can divide this result without
## applying armor a second time or consuming anyone's shield.
static func get_damage_after_armor(defender: Card3D, raw_damage: int) -> int:
	var damage := maxi(raw_damage, 0)
	var armor := CardData.get_effect(defender.card_data, "armor")
	if not armor.is_empty():
		damage = roundi(float(damage) * (1.0 - clampf(float(armor.get("value", 0.25)), 0.0, 0.95)))
	return damage


## Damage that deliberately bypasses mitigation (poison, execute, redirected
## damage) still uses the same one-use death saves as an ordinary hit. Grave
## Return restores health after the hit, so its damage is measured before
## revival and its restored HP is reported separately. Last Stand prevents
## the final point of damage instead.
static func apply_damage_with_survival(defender: Card3D, damage: int) -> Dictionary:
	if damage <= 0 or defender.is_dead():
		return {"damage": 0, "died": defender.is_dead(), "shield_blocked": false, "survival_effect": "", "healed": 0}
	var hp_before := defender.current_hp
	var died := defender.take_damage(damage)
	var damage_taken := maxi(hp_before - defender.current_hp, 0)
	var survival_effect := ""
	var healed := 0
	if died and defender.try_survive_death():
		died = false
		survival_effect = str(defender.get_meta("last_survival_effect", ""))
		defender.remove_meta("last_survival_effect")
		if survival_effect == "grave_return":
			healed = defender.current_hp
		else:
			damage_taken = maxi(hp_before - defender.current_hp, 0)
	return {"damage": damage_taken, "died": died, "shield_blocked": false, "survival_effect": survival_effect, "healed": healed}


static func apply_incoming_damage(defender: Card3D, raw_damage: int) -> Dictionary:
	if raw_damage <= 0 or defender.is_dead():
		return apply_damage_with_survival(defender, 0)
	if defender.consume_first_hit_shield():
		return {"damage": 0, "died": false, "shield_blocked": true, "survival_effect": "", "healed": 0}
	return apply_damage_with_survival(defender, get_damage_after_armor(defender, raw_damage))

static func heal_from_lifesteal(attacker: Card3D, damage_done: int) -> int:
	var lifesteal := CardData.get_effect(attacker.card_data, "lifesteal")
	if lifesteal.is_empty() or damage_done <= 0:
		return 0
	var hp_before := attacker.current_hp
	var heal_amount := int(round(float(damage_done) * float(lifesteal.get("percent", 0.2))))
	attacker.heal(heal_amount)
	return maxi(attacker.current_hp - hp_before, 0)

static func apply_thorns(defender: Card3D, attacker: Card3D, damage_taken: int) -> bool:
	var thorns := CardData.get_effect(defender.card_data, "thorns")
	if thorns.is_empty() or damage_taken <= 0:
		return false
	var reflected := int(round(float(damage_taken) * float(thorns.get("percent", 0.25))))
	return attacker.take_damage(max(reflected, 0))
