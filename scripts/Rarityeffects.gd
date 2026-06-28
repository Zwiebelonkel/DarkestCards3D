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
		"particle_amount": 10,
		"particle_speed": 1.0,
		"particle_glow_energy": 1.5,
		"particle_glow_scale": 1.0,
		"screen_flash_strength": 0.0,
		"screen_flicker_strength": 0.02,
		"screen_flicker_speed": 5.0,
		"aberration_strength": 0.0,
		"distortion_strength": 0.0,
		"distortion_speed": 2.0,
		"camera_shake_strength": 0.0,
		"slow_motion_scale": 1.0,
		"slow_motion_duration": 0.0,
		"sound_key": "reveal_common",
	},
	"uncommon": {
		"color": Color("#42D94A"),
		"particle_amount": 16,
		"particle_speed": 1.1,
		"particle_glow_energy": 2.0,
		"particle_glow_scale": 1.1,
		"screen_flash_strength": 0.05,
		"screen_flicker_strength": 0.06,
		"screen_flicker_speed": 8.0,
		"aberration_strength": 0.0015,
		"distortion_strength": 0.0,
		"distortion_speed": 2.0,
		"camera_shake_strength": 0.0,
		"slow_motion_scale": 1.0,
		"slow_motion_duration": 0.0,
		"sound_key": "reveal_uncommon",
	},
	"rare": {
		"color": Color("#3D7DFF"),
		"particle_amount": 26,
		"particle_speed": 1.25,
		"particle_glow_energy": 2.6,
		"particle_glow_scale": 1.25,
		"screen_flash_strength": 0.12,
		"screen_flicker_strength": 0.12,
		"screen_flicker_speed": 12.0,
		"aberration_strength": 0.003,
		"distortion_strength": 0.0,
		"distortion_speed": 2.5,
		"camera_shake_strength": 0.05,
		"slow_motion_scale": 1.0,
		"slow_motion_duration": 0.0,
		"sound_key": "reveal_rare",
	},
	"epic": {
		"color": Color("#B04DFF"),
		"particle_amount": 42,
		"particle_speed": 1.4,
		"particle_glow_energy": 3.4,
		"particle_glow_scale": 1.4,
		"screen_flash_strength": 0.22,
		"screen_flicker_strength": 0.25,
		"screen_flicker_speed": 18.0,
		"aberration_strength": 0.006,
		"distortion_strength": 0.008,
		"distortion_speed": 3.0,
		"camera_shake_strength": 0.12,
		"slow_motion_scale": 0.55,
		"slow_motion_duration": 0.5,
		"sound_key": "reveal_epic",
	},
	"legendary": {
		"color": Color("#FFC233"),
		"particle_amount": 64,
		"particle_speed": 1.6,
		"particle_glow_energy": 4.2,
		"particle_glow_scale": 1.6,
		"screen_flash_strength": 0.35,
		"screen_flicker_strength": 0.45,
		"screen_flicker_speed": 26.0,
		"aberration_strength": 0.01,
		"distortion_strength": 0.016,
		"distortion_speed": 3.6,
		"camera_shake_strength": 0.22,
		"slow_motion_scale": 0.4,
		"slow_motion_duration": 0.85,
		"sound_key": "reveal_legendary",
	},
	"mythic": {
		"color": Color("#37207A"),
		"particle_amount": 90,
		"particle_speed": 1.85,
		"particle_glow_energy": 5.2,
		"particle_glow_scale": 1.8,
		"screen_flash_strength": 0.5,
		"screen_flicker_strength": 0.7,
		"screen_flicker_speed": 34.0,
		"aberration_strength": 0.014,
		"distortion_strength": 0.026,
		"distortion_speed": 4.2,
		"camera_shake_strength": 0.32,
		"slow_motion_scale": 0.3,
		"slow_motion_duration": 1.15,
		"sound_key": "reveal_mythic",
	},
	"exotic": {
		"color": Color("#FF2222"),
		"particle_amount": 130,
		"particle_speed": 2.1,
		"particle_glow_energy": 6.5,
		"particle_glow_scale": 2.1,
		"screen_flash_strength": 0.65,
		"screen_flicker_strength": 1.0,
		"screen_flicker_speed": 44.0,
		"aberration_strength": 0.02,
		"distortion_strength": 0.04,
		"distortion_speed": 5.0,
		"camera_shake_strength": 0.45,
		"slow_motion_scale": 0.22,
		"slow_motion_duration": 1.4,
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
