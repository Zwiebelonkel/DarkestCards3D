extends RefCounted
class_name EffectPresentation

## Shared, UI-only presentation helpers for card effects. Gameplay code keeps
## using the original effect dictionaries; this class only resolves catalog
## metadata, icons, readable values and colors.

const EFFECT_ICON_PATH := "res://assets/effects/"
const EFFECT_PLACEHOLDER := "res://assets/effects/placeholder.png"

const BLOOD_RED := Color("#6E2930")
const BLOOD_RED_BRIGHT := Color("#D0525F")
const WARM_WHITE := Color("#F3E7E4")

const VARIANT_KEYS: Array[String] = [
	"value",
	"percent",
	"damage",
	"turns",
	"min",
	"max",
	"threshold",
	"amount",
	"hits",
	"side_damage",
	"chance",
]


static func build(effect: Dictionary, fallback_rarity: String = "common") -> Dictionary:
	var normalized := resolve_defaults(effect)
	var rarity := str(normalized.get("rarity", fallback_rarity)).strip_edges().to_lower()
	if not RarityEffectsData.RARITY_DATA.has(rarity):
		rarity = fallback_rarity.strip_edges().to_lower()
	if not RarityEffectsData.RARITY_DATA.has(rarity):
		rarity = RarityEffectsData.DEFAULT_RARITY

	return {
		"effect": normalized,
		"title": get_title(normalized),
		"description": get_description(normalized),
		"badge": get_value_badge(normalized),
		"icon": get_icon(normalized),
		"icon_path": get_icon_path(normalized),
		"rarity": rarity,
		"accent_color": get_accent_color(rarity),
	}


static func resolve_defaults(effect: Dictionary) -> Dictionary:
	var effect_type := str(effect.get("type", "")).strip_edges().to_lower()
	if effect_type == "":
		return effect.duplicate(true)

	var defaults := _find_best_variant(effect_type, effect)
	var resolved := defaults.duplicate(true)
	for key: Variant in effect.keys():
		var value: Variant = effect[key]
		if value is String and (value as String).strip_edges() == "" and resolved.has(key):
			continue
		resolved[key] = value
	resolved["type"] = effect_type
	return resolved


static func get_title(effect: Dictionary) -> String:
	var title := str(effect.get("name", "")).strip_edges()
	if title != "":
		return title

	var effect_type := str(effect.get("type", "effect")).strip_edges()
	return effect_type.replace("_", " ").capitalize()


static func get_description(effect: Dictionary) -> String:
	var description := str(effect.get("description", "")).strip_edges()
	if description != "":
		return description

	var badge := get_value_badge(effect)
	if badge == "PASSIV":
		return "Passiver Karteneffekt."
	return "Aktiver Karteneffekt mit dem Wert %s." % badge


static func get_value_badge(effect: Dictionary) -> String:
	var effect_type := str(effect.get("type", "")).strip_edges().to_lower()

	match effect_type:
		"armor":
			return "%d%% ARMOR" % _as_percent(effect.get("value", 0.0))
		"lifesteal":
			return "%d%% HEAL" % _as_percent(effect.get("percent", 0.0))
		"thorns":
			return "%d%% REFLECT" % _as_percent(effect.get("percent", 0.0))
		"bodyguard":
			return "%d%% SHARE" % _as_percent(effect.get("percent", 0.0))
		"cleave":
			return "%d%% SPLASH" % _as_percent(effect.get("side_damage", 0.0))
		"stun":
			return "%d%% CHANCE" % _as_percent(effect.get("chance", 1.0))
		"execute":
			return "≤ %d%% HP" % _as_percent(effect.get("threshold", 0.0))
		"regeneration", "neighbor_heal":
			return "+%s HP" % _format_number(float(effect.get("value", 0.0)))
		"curse":
			return "-%s ATK" % _format_number(float(effect.get("value", 0.0)))
		"poison":
			return "%d DMG · %dT" % [
				int(effect.get("damage", 0)),
				int(effect.get("turns", 0)),
			]
		"random_damage":
			return "%s–%s×" % [
				_format_number(float(effect.get("min", 0.0))),
				_format_number(float(effect.get("max", 0.0))),
			]
		"double_strike", "triple_strike":
			return "%d HITS" % int(effect.get("hits", 2 if effect_type == "double_strike" else 3))
		"deck_burn":
			return "-%d CARD" % int(effect.get("amount", 1))

	if effect.has("percent"):
		return "%d%%" % _as_percent(effect.get("percent", 0.0))
	if effect.has("chance"):
		return "%d%% CHANCE" % _as_percent(effect.get("chance", 0.0))
	if effect.has("damage") and effect.has("turns"):
		return "%d DMG · %dT" % [int(effect["damage"]), int(effect["turns"])]
	if effect.has("value"):
		var value := float(effect.get("value", 0.0))
		if value > 0.0 and value <= 1.0:
			return "%d%%" % _as_percent(value)
		return "+%s" % _format_number(value)
	if effect.has("amount"):
		return str(int(effect.get("amount", 0)))
	return "PASSIV"


static func get_icon_path(effect: Dictionary) -> String:
	var effect_type := str(effect.get("type", "")).strip_edges().to_lower()
	if effect_type == "":
		return EFFECT_PLACEHOLDER

	var file_name := effect_type
	if effect_type == "armor":
		var percentage := _as_percent(effect.get("value", 0.0))
		if percentage == 25 or percentage == 50 or percentage == 75:
			file_name = "armor_%d" % percentage

	var candidate := EFFECT_ICON_PATH + file_name + ".png"
	return candidate if ResourceLoader.exists(candidate) else EFFECT_PLACEHOLDER


static func get_icon(effect: Dictionary) -> Texture2D:
	return load(get_icon_path(effect)) as Texture2D


static func get_accent_color(rarity: String) -> Color:
	var rarity_key := rarity.strip_edges().to_lower()
	if not RarityEffectsData.RARITY_DATA.has(rarity_key):
		rarity_key = RarityEffectsData.DEFAULT_RARITY
	var rarity_color := RarityEffectsData.get_color(rarity_key)
	# Keep every rarity legible inside the blood-red UI family. Common gets a
	# little more warmth, while high rarities retain their recognizable hue.
	return rarity_color.lerp(BLOOD_RED_BRIGHT, 0.28)


static func _find_best_variant(effect_type: String, effect: Dictionary) -> Dictionary:
	var raw_variants: Variant = EffectDatabase.effects_by_type.get(effect_type, [])
	if not (raw_variants is Array) or (raw_variants as Array).is_empty():
		return {}

	var variants := raw_variants as Array
	var best_variant: Dictionary = {}
	var best_score := -INF
	for raw_variant: Variant in variants:
		if not (raw_variant is Dictionary):
			continue
		var variant := raw_variant as Dictionary
		var score := _variant_score(effect, variant)
		if score > best_score:
			best_score = score
			best_variant = variant
	return best_variant.duplicate(true)


static func _variant_score(effect: Dictionary, variant: Dictionary) -> float:
	var score := 0.0
	var compared_values := 0
	for key: String in VARIANT_KEYS:
		if not effect.has(key):
			continue
		if not variant.has(key):
			score -= 5.0
			continue

		compared_values += 1
		var source: Variant = effect[key]
		var candidate: Variant = variant[key]
		if _is_number(source) and _is_number(candidate):
			var difference := absf(float(source) - float(candidate))
			if is_equal_approx(difference, 0.0):
				score += 100.0
			else:
				score += maxf(0.0, 10.0 - difference)
		elif source == candidate:
			score += 100.0
		else:
			score -= 5.0

	# With no distinguishing fields the first catalog entry remains the stable
	# fallback. Armor carries `value`, so 25/50/75 resolve to their exact rows.
	return score + float(compared_values) * 0.01


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _as_percent(value: Variant) -> int:
	var number := float(value)
	if absf(number) <= 1.0:
		number *= 100.0
	return int(round(number))


static func _format_number(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return String.num(value, 2)
