extends Resource
class_name PackDefinition

const PACK_TYPES := {
	"basic": {
		"name": "BASIC PACK",
		"cost": 5,
		"minimum_level": 1,
		"card_count": 5,
		"description": "Solider Einstieg mit zuverlässigen Karten.",
		"scene": preload("res://assets/cards/pack/basic/pack.glb"),
		"rarity_weights": {
			"common": 64.999,
			"uncommon": 25.0,
			"rare": 8.0,
			"epic": 1.7,
			"legendary": 0.3,
			"mythic": 0.0,
			"exotic": 0.0,
			"secret": 0.001
		}
	},

	"ultra": {
		"name": "ULTRA PACK",
		"cost": 20,
		"minimum_level": 1,
		"card_count": 7,
		"description": "Stärkere Auswahl mit deutlich besseren Chancen.",
		"scene": preload("res://assets/cards/pack/ultra/pack.glb"),
		"rarity_weights": {
			"common": 34.995,
			"uncommon": 32.0,
			"rare": 20.0,
			"epic": 9.0,
			"legendary": 3.0,
			"mythic": 0.8,
			"exotic": 0.2,
			"secret": 0.005
		}
	},

	"god": {
		"name": "GOD PACK",
		"cost": 35,
		"minimum_level": 10,
		"card_count": 10,
		"description": "Höchste Chancen auf seltene und spektakuläre Karten.",
		"scene": preload("res://assets/cards/pack/god/pack.glb"),
		"rarity_weights": {
			"common": 9.99,
			"uncommon": 20.0,
			"rare": 28.0,
			"epic": 24.0,
			"legendary": 12.0,
			"mythic": 5.0,
			"exotic": 1.0,
			"secret": 0.01
		}
	}
}

static func get_price(pack_id: String, pack_data: Dictionary = {}) -> float:
	var data: Dictionary = PACK_TYPES.get(pack_id, {}) if pack_data.is_empty() else pack_data
	return GameCurrency.get_shop_price(float(data.get("cost", 0)), str(data.get("shop_pool", "normal")))


static func get_minimum_level(pack_id: String) -> int:
	var data: Dictionary = PACK_TYPES.get(pack_id, {})
	return maxi(int(data.get("minimum_level", 1)), 1)


static func is_unlocked(pack_id: String, player_level: int) -> bool:
	return player_level >= get_minimum_level(pack_id)


static func get_unlock_message(pack_id: String) -> String:
	return Localization.format_text("AB LEVEL %d VERFÜGBAR", [get_minimum_level(pack_id)])


static func get_display_name(pack_id: String) -> String:
	return Localization.text(str(PACK_TYPES.get(pack_id, {}).get("name", pack_id)))


static func get_display_description(pack_id: String) -> String:
	return Localization.text(str(PACK_TYPES.get(pack_id, {}).get("description", "")))
