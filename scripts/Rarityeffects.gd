extends Node

# Autoload-Singleton. In Project Settings -> Autoload als "RarityEffects" eintragen.
#
# Zentrale Stelle fuer alles, was beim Reveal einer Karte rarity-abhaengig
# unterschiedlich aussehen/klingen soll: Partikelfarbe, Partikelmenge,
# Kamera-/Screen-Effekt-Staerke, Slow-Motion-Dauer und Sound-Key.
#
# Farben stammen aus rarities.json (Drop-Weights bleiben weiterhin allein
# in CardDatabase.RARITIES - hier geht es nur um Praesentation).

class_name RarityEffectsData

const RARITY_DATA := {
	"common": {
		"color": Color("#8C8C8C"),
		"particle_amount": 20,
		"particle_speed": 1.20,
		"particle_glow_energy": 2.5,
		"particle_glow_scale": 1.20,
		"screen_flash_strength": 0.08,
		"screen_flicker_strength": 0.05,
		"screen_flicker_speed": 8.0,
		"aberration_strength": 0.001,
		"distortion_strength": 0.0,
		"distortion_speed": 2.2,
		"camera_shake_strength": 0.0,
		"slow_motion_scale": 1.0,
		"slow_motion_duration": 0.0,
		"sound_key": "reveal_common",
	},

	"uncommon": {
		"color": Color("#42D94A"),
		"particle_amount": 35,
		"particle_speed": 1.35,
		"particle_glow_energy": 3.5,
		"particle_glow_scale": 1.40,
		"screen_flash_strength": 0.15,
		"screen_flicker_strength": 0.10,
		"screen_flicker_speed": 12.0,
		"aberration_strength": 0.003,
		"distortion_strength": 0.003,
		"distortion_speed": 2.6,
		"camera_shake_strength": 0.03,
		"slow_motion_scale": 1.0,
		"slow_motion_duration": 0.0,
		"sound_key": "reveal_uncommon",
	},

	"rare": {
		"color": Color("#3D7DFF"),
		"particle_amount": 55,
		"particle_speed": 1.65,
		"particle_glow_energy": 5.0,
		"particle_glow_scale": 1.80,
		"screen_flash_strength": 0.30,
		"screen_flicker_strength": 0.30,
		"screen_flicker_speed": 18.0,
		"aberration_strength": 0.006,
		"distortion_strength": 0.008,
		"distortion_speed": 3.0,
		"camera_shake_strength": 0.12,
		"slow_motion_scale": 1.0,
		"slow_motion_duration": 0.0,
		"sound_key": "reveal_rare",
	},

	"epic": {
		"color": Color("#B04DFF"),
		"particle_amount": 95,
		"particle_speed": 2.0,
		"particle_glow_energy": 7.0,
		"particle_glow_scale": 2.20,
		"screen_flash_strength": 0.50,
		"screen_flicker_strength": 0.50,
		"screen_flicker_speed": 26.0,
		"aberration_strength": 0.012,
		"distortion_strength": 0.018,
		"distortion_speed": 3.8,
		"camera_shake_strength": 0.28,
		"slow_motion_scale": 0.45,
		"slow_motion_duration": 0.80,
		"sound_key": "reveal_epic",
	},

	"legendary": {
		"color": Color("#FFC233"),
		"particle_amount": 150,
		"particle_speed": 2.40,
		"particle_glow_energy": 10.0,
		"particle_glow_scale": 2.80,
		"screen_flash_strength": 0.80,
		"screen_flicker_strength": 0.75,
		"screen_flicker_speed": 36.0,
		"aberration_strength": 0.018,
		"distortion_strength": 0.030,
		"distortion_speed": 4.5,
		"camera_shake_strength": 0.45,
		"slow_motion_scale": 0.32,
		"slow_motion_duration": 1.20,
		"sound_key": "reveal_legendary",
	},

	"mythic": {
		"color": Color("#37207A"),
		"particle_amount": 220,
		"particle_speed": 2.90,
		"particle_glow_energy": 14.0,
		"particle_glow_scale": 3.40,
		"screen_flash_strength": 1.15,
		"screen_flicker_strength": 0.95,
		"screen_flicker_speed": 46.0,
		"aberration_strength": 0.024,
		"distortion_strength": 0.045,
		"distortion_speed": 5.3,
		"camera_shake_strength": 0.65,
		"slow_motion_scale": 0.22,
		"slow_motion_duration": 1.70,
		"sound_key": "reveal_mythic",
	},

	"exotic": {
		"color": Color("#FF2222"),
		"particle_amount": 320,
		"particle_speed": 3.50,
		"particle_glow_energy": 18.0,
		"particle_glow_scale": 4.00,
		"screen_flash_strength": 1.45,
		"screen_flicker_strength": 1.00,
		"screen_flicker_speed": 60.0,
		"aberration_strength": 0.030,
		"distortion_strength": 0.060,
		"distortion_speed": 6.0,
		"camera_shake_strength": 0.90,
		"slow_motion_scale": 0.15,
		"slow_motion_duration": 2.30,
		"sound_key": "reveal_exotic",
	},
}

const DEFAULT_RARITY := "common"

# Ab dieser Rarity (Index in RARITY_ORDER) wird Slow-Motion ausgeloest.
const RARITY_ORDER := ["common", "uncommon", "rare", "epic", "legendary", "mythic", "exotic"]
const SLOW_MOTION_MIN_INDEX := 3 # "epic"


static func get_data(rarity_id: String) -> Dictionary:
	var key := rarity_id.to_lower().strip_edges()
	if RARITY_DATA.has(key):
		return RARITY_DATA[key]
	push_warning("RarityEffects: unbekannte Rarity '%s', falle auf '%s' zurueck." % [rarity_id, DEFAULT_RARITY])
	return RARITY_DATA[DEFAULT_RARITY]


static func get_color(rarity_id: String) -> Color:
	return get_data(rarity_id).get("color", Color.WHITE)


static func should_slow_motion(rarity_id: String) -> bool:
	var index := RARITY_ORDER.find(rarity_id.to_lower().strip_edges())
	return index >= SLOW_MOTION_MIN_INDEX


static func rarity_rank(rarity_id: String) -> int:
	var index := RARITY_ORDER.find(rarity_id.to_lower().strip_edges())
	return max(index, 0)
