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
		var name := str(effect.get("name", effect.get("type", "Effect")))
		var desc := str(effect.get("description", ""))

		lines.append("[b]" + name + "[/b]\n" + desc)

	effects_label.text = "\n\n".join(lines)
	show()


func hide_overview(_card: Card3D = null) -> void:
	hide()
