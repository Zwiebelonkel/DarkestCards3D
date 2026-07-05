extends PanelContainer
class_name CardEffectOverviewUI

@onready var effects_label: RichTextLabel = $Margin/VBox/EffectsLabel

func show_for_card(card: Card3D) -> void:
	if card == null or not is_instance_valid(card):
		hide()
		return

	var effects := CardData.get_active_effects(card.card_data)

	if effects.is_empty():
		hide()
		return

	var lines: Array[String] = []

	for effect: Dictionary in effects:
		var normalized_effect := _with_database_defaults(effect)
		var name := str(normalized_effect.get("name", normalized_effect.get("type", "Effect")))
		var desc := str(normalized_effect.get("description", "")).strip_edges()

		if desc == "":
			desc = _build_fallback_description(normalized_effect)

		lines.append("[b]" + name + "[/b]\n" + desc)

	effects_label.text = "\n\n".join(lines)
	show()


func hide_overview(_card: Card3D = null) -> void:
	hide()


func _with_database_defaults(effect: Dictionary) -> Dictionary:
	var normalized := effect.duplicate(true)
	var effect_type := str(normalized.get("type", "")).strip_edges()

	if effect_type == "":
		return normalized

	var defaults := EffectDatabase.get_effect(effect_type)

	for key in defaults.keys():
		if not normalized.has(key) or str(normalized.get(key, "")).strip_edges() == "":
			normalized[key] = defaults[key]

	return normalized


func _build_fallback_description(effect: Dictionary) -> String:
	var effect_type := str(effect.get("type", "effect")).replace("_", " ")
	var details: Array[String] = []

	for key in ["percent", "value", "damage", "turns", "threshold", "amount", "min", "max", "side_damage", "chance", "hits"]:
		if effect.has(key):
			details.append("%s: %s" % [str(key).replace("_", " ").capitalize(), str(effect[key])])

	if details.is_empty():
		return "Keine Beschreibung fuer diesen %s-Effekt vorhanden." % effect_type

	return "Effektwerte: " + ", ".join(details)
