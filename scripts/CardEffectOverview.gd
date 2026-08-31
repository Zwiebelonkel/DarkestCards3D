extends PanelContainer
class_name CardEffectOverviewUI

const MAX_VISIBLE_EFFECTS := 2
const SHOW_DURATION := 0.14
const HIDE_DURATION := 0.10
const HIDE_DELAY := 0.075
const SLIDE_DISTANCE := 12.0

@onready var _card_name_label: Label = $Margin/VBox/HeaderRow/HeaderText/CardNameLabel
@onready var _count_label: Label = $Margin/VBox/HeaderRow/CountBadge/CountLabel

@onready var _row_panels: Array[PanelContainer] = [
	$Margin/VBox/EffectsList/EffectRow1,
	$Margin/VBox/EffectsList/EffectRow2,
]
@onready var _icon_frames: Array[PanelContainer] = [
	$Margin/VBox/EffectsList/EffectRow1/RowMargin/RowContent/IconFrame,
	$Margin/VBox/EffectsList/EffectRow2/RowMargin/RowContent/IconFrame,
]
@onready var _icons: Array[TextureRect] = [
	$Margin/VBox/EffectsList/EffectRow1/RowMargin/RowContent/IconFrame/IconMargin/Icon,
	$Margin/VBox/EffectsList/EffectRow2/RowMargin/RowContent/IconFrame/IconMargin/Icon,
]
@onready var _effect_names: Array[Label] = [
	$Margin/VBox/EffectsList/EffectRow1/RowMargin/RowContent/EffectText/TitleRow/EffectName,
	$Margin/VBox/EffectsList/EffectRow2/RowMargin/RowContent/EffectText/TitleRow/EffectName,
]
@onready var _badge_panels: Array[PanelContainer] = [
	$Margin/VBox/EffectsList/EffectRow1/RowMargin/RowContent/EffectText/TitleRow/ValueBadge,
	$Margin/VBox/EffectsList/EffectRow2/RowMargin/RowContent/EffectText/TitleRow/ValueBadge,
]
@onready var _badge_labels: Array[Label] = [
	$Margin/VBox/EffectsList/EffectRow1/RowMargin/RowContent/EffectText/TitleRow/ValueBadge/BadgeMargin/ValueLabel,
	$Margin/VBox/EffectsList/EffectRow2/RowMargin/RowContent/EffectText/TitleRow/ValueBadge/BadgeMargin/ValueLabel,
]
@onready var _descriptions: Array[Label] = [
	$Margin/VBox/EffectsList/EffectRow1/RowMargin/RowContent/EffectText/Description,
	$Margin/VBox/EffectsList/EffectRow2/RowMargin/RowContent/EffectText/Description,
]

var _active_card: Card3D = null
var _animation: Tween = null
var _request_serial := 0
var _rest_offset_left := 0.0
var _rest_offset_right := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rest_offset_left = offset_left
	_rest_offset_right = offset_right
	_set_mouse_passthrough(self)
	modulate.a = 0.0
	hide()


func show_for_card(card: Card3D) -> void:
	if card == null or not is_instance_valid(card):
		hide_overview()
		return

	var effects := CardData.get_active_effects(card.card_data)
	if effects.is_empty():
		hide_overview()
		return

	_request_serial += 1
	_active_card = card
	_populate(card, effects)
	_play_show_animation()


func hide_overview(card: Card3D = null) -> void:
	# An unhover from a previously displayed card must not close a newer card's
	# panel. For the same card, the short delay bridges slot-to-slot movement.
	if card != null and _active_card != null and card != _active_card:
		return

	_request_serial += 1
	var request_id := _request_serial
	_hide_after_delay(request_id)


func _populate(card: Card3D, effects: Array[Dictionary]) -> void:
	var card_name := str(card.card_data.get("name", card.card_data.get("id", "CARD"))).strip_edges()
	_card_name_label.text = card_name.to_upper()
	var card_rarity := str(card.card_data.get("rarity", "common"))
	_card_name_label.add_theme_color_override(
		"font_color",
		EffectPresentation.get_accent_color(card_rarity).lightened(0.22)
	)

	var visible_count := mini(effects.size(), MAX_VISIBLE_EFFECTS)
	_count_label.text = "%d %s" % [visible_count, "EFFEKT" if visible_count == 1 else "EFFEKTE"]

	for index in range(MAX_VISIBLE_EFFECTS):
		if index >= visible_count:
			_row_panels[index].visible = false
			continue

		var view_data := EffectPresentation.build(effects[index], card_rarity)
		_configure_row(index, view_data)
		_row_panels[index].visible = true

	call_deferred("_fit_height_to_content")


func _fit_height_to_content() -> void:
	# The panel is anchored directly to a CanvasLayer, so it does not have a
	# parent Container that can shrink it when the second effect row is hidden.
	# Keep its top edge fixed and size only to the currently visible content.
	offset_bottom = offset_top + get_combined_minimum_size().y


func _configure_row(index: int, view_data: Dictionary) -> void:
	var accent: Color = view_data.get("accent_color", EffectPresentation.BLOOD_RED_BRIGHT)
	_icons[index].texture = view_data.get("icon", null) as Texture2D
	_effect_names[index].text = str(view_data.get("title", "Effect"))
	_badge_labels[index].text = str(view_data.get("badge", "PASSIVE"))
	_badge_labels[index].add_theme_color_override("font_color", accent.lightened(0.30))
	_descriptions[index].text = str(view_data.get("description", ""))

	_set_panel_border(_row_panels[index], accent.darkened(0.25), 0.78)
	_set_panel_border(_icon_frames[index], accent, 1.0)
	_set_panel_border(_badge_panels[index], accent, 0.92)


func _play_show_animation() -> void:
	_kill_animation()
	offset_left = _rest_offset_left + SLIDE_DISTANCE
	offset_right = _rest_offset_right + SLIDE_DISTANCE
	modulate.a = 0.0
	show()

	_animation = create_tween().set_parallel(true)
	_animation.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_animation.tween_property(self, "modulate:a", 1.0, SHOW_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_animation.tween_property(self, "offset_left", _rest_offset_left, SHOW_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_animation.tween_property(self, "offset_right", _rest_offset_right, SHOW_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _hide_after_delay(request_id: int) -> void:
	if not visible:
		_active_card = null
		return

	await get_tree().create_timer(HIDE_DELAY, true, false, true).timeout
	if request_id != _request_serial or not visible:
		return
	_play_hide_animation(request_id)


func _play_hide_animation(request_id: int) -> void:
	_kill_animation()
	var hide_tween := create_tween().set_parallel(true)
	_animation = hide_tween
	hide_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	hide_tween.tween_property(self, "modulate:a", 0.0, HIDE_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	hide_tween.tween_property(self, "offset_left", _rest_offset_left + SLIDE_DISTANCE * 0.65, HIDE_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	hide_tween.tween_property(self, "offset_right", _rest_offset_right + SLIDE_DISTANCE * 0.65, HIDE_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	hide_tween.finished.connect(_finish_hide.bind(request_id, hide_tween), CONNECT_ONE_SHOT)


func _finish_hide(request_id: int, hide_tween: Tween) -> void:
	if request_id != _request_serial:
		return
	if _animation != hide_tween:
		return
	_animation = null
	hide()
	_active_card = null
	offset_left = _rest_offset_left
	offset_right = _rest_offset_right


func _kill_animation() -> void:
	if _animation != null and _animation.is_valid():
		_animation.kill()
	_animation = null


func _set_panel_border(panel: PanelContainer, color: Color, alpha: float) -> void:
	var current_style := panel.get_theme_stylebox("panel")
	if not (current_style is StyleBoxFlat):
		return
	var style := (current_style as StyleBoxFlat).duplicate() as StyleBoxFlat
	style.border_color = Color(color, alpha)
	panel.add_theme_stylebox_override("panel", style)


func _set_mouse_passthrough(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		_set_mouse_passthrough(child)
