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
	effect = CardData.normalize_effect(effect)
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
	# A custom armor percentage has no matching catalog variant. Remote
	# effects intentionally omit text metadata, so derive it from the actual
	# value instead of inheriting an unrelated "Armor 25%" label.
	if effect_type == "armor" and effect.has("value") and not is_equal_approx(float(effect["value"]), float(defaults.get("value", 0.0))):
		var percentage := _as_percent(effect["value"])
		if str(effect.get("name", "")).strip_edges().is_empty():
			resolved["name"] = "Armor %d%%" % percentage
		if str(effect.get("description", "")).strip_edges().is_empty():
			resolved["description"] = "Reduces regular incoming damage by %d%% (rounded)." % percentage
	return resolved


static func get_title(effect: Dictionary) -> String:
	effect = resolve_defaults(effect)
	var title := str(effect.get("name", "")).strip_edges()
	if title != "":
		return Localization.text(title)

	var effect_type := str(effect.get("type", "effect")).strip_edges()
	return Localization.text(effect_type.replace("_", " ").capitalize())


static func get_description(effect: Dictionary) -> String:
	effect = resolve_defaults(effect)
	var rules := get_combat_description(effect, true)
	if not rules.is_empty():
		return rules
	var description := str(effect.get("description", "")).strip_edges()
	if description != "":
		return Localization.text(description)

	var badge := get_value_badge(effect)
	if badge == Localization.text("PASSIV"):
		return Localization.text("Passiver Karteneffekt.")
	return Localization.format_text("Aktiver Karteneffekt mit dem Wert %s.", [badge])


static func get_combat_description(effect: Dictionary, compact: bool = false) -> String:
	# Describe the executable rules, not several older catalog promises.
	# Missing future types retain their authored catalog description as fallback.
	effect = CardData.normalize_effect(effect)
	match str(effect.get("type", "")):
		"armor":
			return Localization.text("Reduziert regulären Treffer- und Gegenschaden um %s%% (gerundet). Gift und Dornen umgehen Rüstung.") % _format_number(clampf(float(effect.get("value", 0.25)), 0.0, 0.95) * 100.0)
		"regeneration":
			return Localization.text("Heilt zu Beginn des eigenen Zuges %d HP, höchstens bis zu den maximalen HP.") % int(effect.get("value", 3))
		"poison":
			var text := Localization.text("Vergiftet überlebende Ziele nur nach tatsächlichem Trefferschaden: %d Schaden zu Beginn ihrer nächsten %d eigenen Züge.") % [int(effect.get("damage", 3)), int(effect.get("turns", 3))]
			return text if compact else text + Localization.text(" Erneutes Vergiften ersetzt Dauer und Schaden. Gift umgeht Rüstung und Ersttrefferschild; Last Stand und Grave Return können retten.")
		"lifesteal":
			return Localization.text("Heilt am Ende eines überlebten eigenen Angriffs %s%% des gesamten verursachten Schadens einschließlich Cleave (gerundet), höchstens bis zu den maximalen HP.") % _format_number(float(effect.get("percent", 0.2)) * 100.0)
		"thorns":
			var text := Localization.text("Reflektiert %s%% des tatsächlich erlittenen Schadens von Haupt- und Lava-Treffern (gerundet). Cleave und umgeleiteter Schaden lösen keine Dornen aus.") % _format_number(float(effect.get("percent", 0.25)) * 100.0)
			return text if compact else text + Localization.text(" Umgeht Rüstung und Ersttrefferschild. Last Stand und Grave Return können vor dem Tod retten.")
		"cleave":
			return Localization.text("Trifft nach dem Angriff die beiden Nachbarplätze des Ziels mit %s%% des Angriffswerts (gerundet), auch wenn der Angreifer stirbt. Zählt für Lebensraub und Kill-Effekte. Entfällt bei Lava.") % _format_number(clampf(float(effect.get("side_damage", 0.5)), 0.0, 1.0) * 100.0)
		"lava":
			return Localization.text("Trifft alle beim Angriffsstart vorhandenen Gegner gleichzeitig mit vollem Angriffsschaden. Nur das Hauptziel kontert; frisch nachgezogene Gegner werden nicht mitgetroffen.")
		"double_strike", "triple_strike":
			var hits := clampi(int(effect.get("hits", 3 if str(effect.get("type", "")) == "triple_strike" else 2)), 1, 8)
			return Localization.text("Bis zu %d Treffer; Gegenschlag nur beim ersten. Endet bei Tod des Angreifers oder Ziels. Dornen wirken pro Treffer; Triple Strike hat Vorrang.") % hits
		"stun":
			return Localization.text("Nach einem Angriff mit tatsächlichem Trefferschaden setzt das überlebende Ziel mit %s%% Chance seinen nächsten gewählten Angriff aus; sein Zug endet. Gilt auch, wenn der Angreifer stirbt. Gegenschläge bleiben möglich.") % _format_number(clampf(float(effect.get("chance", 1.0)), 0.0, 1.0) * 100.0)
		"chain_attack":
			return Localization.text("Tötet ein Haupt-, Lava- oder Cleave-Treffer ein Ziel und überlebt der Angreifer, greift er nach dem Nachziehen einen zufälligen lebenden Gegner an. Die Kette kann weitergehen.")
		"last_stand":
			return Localization.text("Überlebt einmal tödlichen Schaden mit 1 HP, auch Gift, Dornen und Execute. Wird vor Grave Return verbraucht. Derselbe Treffer verbraucht keinen zweiten Überlebensschutz durch Execute.")
		"execute":
			return Localization.text("Entfernt nach tatsächlichem Trefferschaden die restlichen HP, sobald das Ziel höchstens %s%% seiner maximalen HP hat. Last Stand und Grave Return können retten. Entfällt, wenn der Treffer bereits einen Überlebensschutz ausgelöst hat.") % _format_number(clampf(float(effect.get("threshold", 0.25)), 0.0, 1.0) * 100.0)
		"shield_first_hit":
			return Localization.text("Blockiert den ersten regulären eingehenden Treffer einmal vollständig, auch einen Gegenschlag. Dieser Treffer löst weder Gift noch Execute aus. Gift-Schaden und Dornen umgehen den Schild.")
		"swarm_power":
			return Localization.text("Multipliziert eigenen Angriffsschaden mit der Zahl identischer Karten auf beiden Tischseiten, einschließlich dieser Karte. Gegenschaden wird nicht vervielfacht.")
		"grave_return":
			return Localization.text("Überlebt einmal tödlichen Schaden mit 50% der maximalen HP (gerundet, mindestens 1), auch Gift, Dornen und Execute. Ein im selben Treffer verbrauchter Überlebensschutz verhindert einen weiteren Execute-Versuch.")
		"draw_on_death":
			return Localization.text("Zieht beim tatsächlichen Tod dieser Karte genau eine Event-Karte vom gemeinsamen Stapel auf die Hand ihres Besitzers. Gilt auch bei Gift, Ewigem Leiden und Selbstopferung; Überlebenseffekte lösen keinen Kartenzug aus.")
		"eternal_suffering":
			return Localization.text("Nur der Creditkarte angeboren. Stirbt beim eigenen Angriff sofort und belegt das überlebende Ziel auch durch Schilde mit Ewigem Leiden. Das Ziel erleidet zu Beginn seiner eigenen Züge 1, 3, 5, 7 … Schaden. Nur Nachbarheilung entfernt den Zustand; das Ziel gibt ihn nicht weiter.") + Localization.text(" Stirbt eine infizierte Karte, vergiftet sie einmalig ihre lebenden direkten Nachbarn für 3 eigene Züge. Der Giftschaden entspricht ihrem Leidens-Schadenswert beim Tod. Dieses Gift verbreitet sich nicht weiter.")
		"curse":
			return Localization.text("Senkt nach einem Angriff mit tatsächlichem Trefferschaden den Angriff überlebender Ziele um %d, mindestens auf 0. Gilt auch, wenn der Angreifer stirbt. Die Senkung gilt für diese Karte im laufenden Kampf.") % int(effect.get("value", 2))
		"swap_stats":
			return Localization.text("Vertauscht beim Aufstellen die Ausgangswerte für Angriff und maximale HP. Der Effekt tauscht nicht nach jedem Treffer erneut.")
		"random_damage":
			return Localization.text("Wirft vor jedem eigenen Treffer eine Münze: je 50%% Chance auf %s× oder %s× Angriffsschaden (gerundet). Gegenschlag nutzt den normalen Angriffswert.") % [_format_number(0.75), _format_number(2.0)]
		"bodyguard":
			var text := Localization.text("Übernimmt %s%% des Rohschadens eines direkt benachbarten Verbündeten (gerundet). Bei zwei lebenden Beschützern hat der linke Vorrang; beide Karten nutzen ihre eigene Rüstung und ihren eigenen Schild.") % _format_number(clampf(float(effect.get("percent", 0.5)), 0.0, 1.0) * 100.0)
			return text if compact else text + Localization.text(" Der Schild des ursprünglichen Ziels blockiert den ganzen Treffer vor der Aufteilung. Umgeleiteter Schaden wird nicht erneut geteilt; Gift und Dornen werden nie geteilt.")
		"neighbor_heal":
			return Localization.text("Heilt zu Beginn des eigenen Zuges die direkt links und rechts benachbarten eigenen Karten um %d HP, höchstens bis zu deren maximalen HP.") % int(effect.get("value", 2))
	return ""


static func get_value_badge(effect: Dictionary) -> String:
	effect = CardData.normalize_effect(effect)
	var effect_type := str(effect.get("type", "")).strip_edges().to_lower()

	match effect_type:
		"eternal_suffering":
			return "1, 3, 5, 7 …"
		"armor":
			return Localization.text("%d%% ARMOR") % _as_percent(clampf(float(effect.get("value", 0.25)), 0.0, 0.95))
		"lifesteal":
			return Localization.text("%d%% HEAL") % _as_percent(effect.get("percent", 0.2))
		"thorns":
			return Localization.text("%d%% REFLECT") % _as_percent(effect.get("percent", 0.25))
		"bodyguard":
			return Localization.text("%d%% SHARE") % _as_percent(clampf(float(effect.get("percent", 0.5)), 0.0, 1.0))
		"cleave":
			return Localization.text("%d%% SPLASH") % _as_percent(clampf(float(effect.get("side_damage", 0.5)), 0.0, 1.0))
		"lava":
			return Localization.text("ALLE GEGNER")
		"stun":
			return Localization.text("%d%% CHANCE") % _as_percent(clampf(float(effect.get("chance", 1.0)), 0.0, 1.0))
		"execute":
			return Localization.text("≤ %d%% HP") % _as_percent(clampf(float(effect.get("threshold", 0.25)), 0.0, 1.0))
		"regeneration", "neighbor_heal":
			return Localization.text("+%s HP") % _format_number(float(effect.get("value", 3 if effect_type == "regeneration" else 2)))
		"curse":
			return Localization.text("-%s ATK") % _format_number(float(effect.get("value", 2)))
		"poison":
			return Localization.text("%d DMG · %dT") % [
				int(effect.get("damage", 3)),
				int(effect.get("turns", 3)),
			]
		"random_damage":
			return "0.75× / 2×"
		"double_strike", "triple_strike":
			return Localization.text("%d HITS") % clampi(int(effect.get("hits", 2 if effect_type == "double_strike" else 3)), 1, 8)

	if effect.has("percent"):
		return "%d%%" % _as_percent(effect.get("percent", 0.0))
	if effect.has("chance"):
		return Localization.text("%d%% CHANCE") % _as_percent(effect.get("chance", 0.0))
	if effect.has("damage") and effect.has("turns"):
		return Localization.text("%d DMG · %dT") % [int(effect["damage"]), int(effect["turns"])]
	if effect.has("value"):
		var value := float(effect.get("value", 0.0))
		if value > 0.0 and value <= 1.0:
			return "%d%%" % _as_percent(value)
		return "+%s" % _format_number(value)
	if effect.has("amount"):
		return str(int(effect.get("amount", 0)))
	return Localization.text("PASSIV")


static func get_icon_path(effect: Dictionary) -> String:
	effect = CardData.normalize_effect(effect)
	var effect_type := str(effect.get("type", "")).strip_edges().to_lower()
	if effect_type == "":
		return EFFECT_PLACEHOLDER

	var file_name := effect_type
	if effect_type == "eternal_suffering":
		file_name = "eternalSuffering"
	elif effect_type == "draw_on_death":
		file_name = "draw_on_kill"
	if effect_type == "armor":
		file_name = "armor_%d" % _as_percent(effect.get("value", 0.25))

	var candidate := EFFECT_ICON_PATH + file_name + ".png"
	if ResourceLoader.exists(candidate):
		return candidate
	var vector_candidate := EFFECT_ICON_PATH + file_name + ".svg"
	return vector_candidate if ResourceLoader.exists(vector_candidate) else EFFECT_PLACEHOLDER


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
	return Localization.decimal(value, 2)
