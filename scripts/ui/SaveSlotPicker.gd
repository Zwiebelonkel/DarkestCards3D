extends GridContainer

## Preview-only controls. MainMenu commits selection only when Play is pressed.
signal slot_selected(slot: int)

const FONT := preload("res://fonts/VCR_OSD_MONO_1.001.ttf")
var slot_buttons: Array[Button] = []
var _titles: Array[Label] = []
var _badges: Array[Label] = []
var _summaries: Array[Label] = []
var _selected_slot := 1


func _ready() -> void:
	columns = SaveSlots.SLOT_COUNT
	add_theme_constant_override("h_separation", 12)
	add_theme_constant_override("v_separation", 10)
	for slot in range(1, SaveSlots.SLOT_COUNT + 1):
		var button := Button.new()
		button.name = "Slot%d" % slot
		button.custom_minimum_size = Vector2(0, 106)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.add_theme_stylebox_override("normal", _style(Color("18171d"), Color("64534e")))
		button.add_theme_stylebox_override("hover", _style(Color("24212a"), Color("bda598")))
		button.add_theme_stylebox_override("pressed", _style(Color("302528"), Color("e6bcb0")))
		button.add_theme_stylebox_override("hover_pressed", _style(Color("3a2b2d"), Color("ffe0c4")))
		button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, Color("fff0bf")))
		button.pressed.connect(_on_pressed.bind(slot))
		add_child(button)
		slot_buttons.append(button)
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_theme_constant_override("margin_left", 14)
		margin.add_theme_constant_override("margin_right", 14)
		margin.add_theme_constant_override("margin_top", 12)
		margin.add_theme_constant_override("margin_bottom", 10)
		button.add_child(margin)
		var content := VBoxContainer.new()
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_theme_constant_override("separation", 9)
		margin.add_child(content)
		var heading := HBoxContainer.new()
		heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(heading)
		var title := _label(21, Color("ead9c7"))
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.add_child(title)
		_titles.append(title)
		var badge := _label(12, Color("f3c49c"))
		badge.clip_text = false
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		heading.add_child(badge)
		_badges.append(badge)
		var summary := _label(16, Color("bcb4ae"))
		content.add_child(summary)
		_summaries.append(summary)
	resized.connect(_update_columns)
	_update_columns()


func refresh(selected_slot: int) -> void:
	_selected_slot = clampi(selected_slot, 1, SaveSlots.SLOT_COUNT)
	for index in range(slot_buttons.size()):
		var slot := index + 1
		var selected := slot == _selected_slot
		var summary := SaveSlots.get_slot_summary(slot)
		slot_buttons[index].set_pressed_no_signal(selected)
		_titles[index].text = Localization.format_text("save_slot_title", [slot])
		_badges[index].text = Localization.text("save_slot_selected") if selected else ""
		if bool(summary.get("exists", false)):
			_summaries[index].text = Localization.format_text("save_slot_stats", [
				int(summary.get("level", 1)), int(summary.get("xp", 0)),
				GameCurrency.format_coins(float(summary.get("coins", 0.0))), int(summary.get("card_count", 0)),
			])
		else:
			_summaries[index].text = Localization.text("save_slot_new")
		slot_buttons[index].tooltip_text = _titles[index].text + "\n" + _summaries[index].text


func _on_pressed(slot: int) -> void:
	refresh(slot)
	slot_selected.emit(slot)


func _update_columns() -> void:
	columns = 1 if size.x > 0.0 and size.x < 640.0 else SaveSlots.SLOT_COUNT


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.clip_text = true
	return label


func _style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.set_border_width_all(2)
	style.border_color = border
	style.set_corner_radius_all(3)
	return style
