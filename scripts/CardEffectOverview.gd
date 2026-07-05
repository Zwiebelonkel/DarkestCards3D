extends Node3D
class_name CardEffectOverview

@onready var panel: MeshInstance3D = $Panel
@onready var title_label: Label3D = $TitleLabel
@onready var effects_label: Label3D = $EffectsLabel

@export var hover_offset := Vector3(0.0, 0.45, 0.0)
@export var title_prefix := "Effekte"

var _follow_card: Card3D = null

func _ready() -> void:
	visible = false

func show_for_card(card: Card3D) -> void:
	if card == null or not is_instance_valid(card):
		hide_overview()
		return

	var effects := CardData.get_active_effects(card.card_data)
	if effects.is_empty():
		hide_overview()
		return

	_follow_card = card
	title_label.text = "%s: %s" % [title_prefix, str(card.card_data.get("name", "Karte"))]
	effects_label.text = _build_effect_text(effects)
	_update_position()
	visible = true

func hide_overview(card: Card3D = null) -> void:
	if card != null and _follow_card != card:
		return
	_follow_card = null
	visible = false

func _process(_delta: float) -> void:
	if not visible:
		return
	if _follow_card == null or not is_instance_valid(_follow_card):
		hide_overview()
		return
	_update_position()

func _update_position() -> void:
	global_position = _follow_card.global_position + hover_offset
	global_rotation = Vector3(deg_to_rad(-70.0), 0.0, 0.0)

func _build_effect_text(effects: Array[Dictionary]) -> String:
	var lines: Array[String] = []
	for effect in effects:
		var name := str(effect.get("name", effect.get("type", "Effekt"))).replace("_", " ").capitalize()
		var description := str(effect.get("description", ""))
		if description == "":
			var database_effect := EffectDatabase.get_effect(str(effect.get("type", "")))
			description = str(database_effect.get("description", "Keine Beschreibung verfügbar."))
		lines.append("• %s\n  %s" % [name, description])
	return "\n".join(lines)
