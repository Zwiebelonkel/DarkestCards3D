extends CanvasLayer
class_name CharacterCustomizer

signal closed

var preview: TextureRect
var hat_previous: Button
var hat_next: Button
var face_previous: Button
var face_next: Button
var mouth_previous: Button
var mouth_next: Button
var eye_picker: ColorPickerButton
var apply_button: Button
var cancel_button: Button
var hat_label: Label
var face_label: Label
var mouth_label: Label
var _draft: Dictionary = CharacterAppearance.DEFAULT.duplicate()
var _panel: PanelContainer
var _stage: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 40
	_build_ui()
	get_viewport().size_changed.connect(_resize)
	Localization.locale_changed.connect(_refresh)
	hide()


func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.008, 0.006, 0.012, 0.94)
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	_panel.name = "CharacterPanel"
	backdrop.add_child(_panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("241e29")
	style.border_color = Color("98695e")
	style.set_border_width_all(2)
	style.set_content_margin_all(22)
	style.set_corner_radius_all(10)
	_panel.add_theme_stylebox_override("panel", style)
	var theme_font := Theme.new()
	theme_font.default_font = preload("res://fonts/VCR_OSD_MONO_1.001.ttf")
	theme_font.default_font_size = 20
	_panel.theme = theme_font
	var frame := VBoxContainer.new()
	frame.add_theme_constant_override("separation", 12)
	_panel.add_child(frame)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)
	var heading := Label.new()
	heading.text = "Create Character"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 28)
	column.add_child(heading)
	hat_label = Label.new()
	hat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hat_label)
	_stage = Control.new()
	_stage.custom_minimum_size = Vector2(280, 320)
	column.add_child(_stage)
	preview = TextureRect.new()
	preview.name = "CharacterPreview"
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(preview)
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.offset_left = 46
	preview.offset_right = -46
	hat_previous = _arrow("HatPrevious", "<", 0.0, 0.18, _cycle.bind("hat", -1))
	hat_next = _arrow("HatNext", ">", 1.0, 0.18, _cycle.bind("hat", 1))
	face_previous = _arrow("FacePrevious", "<", 0.0, 0.43, _cycle.bind("face", -1))
	face_next = _arrow("FaceNext", ">", 1.0, 0.43, _cycle.bind("face", 1))
	face_label = Label.new()
	face_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(face_label)
	var mouths := HBoxContainer.new()
	mouths.name = "MouthSelector"
	mouths.add_theme_constant_override("separation", 12)
	column.add_child(mouths)
	mouth_previous = Button.new()
	mouth_previous.name = "MouthPrevious"
	mouth_previous.text = "<"
	mouth_previous.custom_minimum_size = Vector2(44, 44)
	mouth_previous.pressed.connect(_cycle.bind("mouth", -1))
	mouths.add_child(mouth_previous)
	mouth_label = Label.new()
	mouth_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouth_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mouths.add_child(mouth_label)
	mouth_next = Button.new()
	mouth_next.name = "MouthNext"
	mouth_next.text = ">"
	mouth_next.custom_minimum_size = Vector2(44, 44)
	mouth_next.pressed.connect(_cycle.bind("mouth", 1))
	mouths.add_child(mouth_next)
	var eyes := HBoxContainer.new()
	eyes.alignment = BoxContainer.ALIGNMENT_CENTER
	eyes.add_theme_constant_override("separation", 16)
	column.add_child(eyes)
	var eye_label := Label.new()
	eye_label.text = "Eye and Mouth Color"
	eyes.add_child(eye_label)
	eye_picker = ColorPickerButton.new()
	eye_picker.name = "EyeColor"
	eye_picker.custom_minimum_size = Vector2(100, 42)
	eye_picker.edit_alpha = false
	eye_picker.color_changed.connect(_on_eye_color_changed)
	eyes.add_child(eye_picker)
	var hint := Label.new()
	hint.text = "Your character is visible to other players in multiplayer."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	column.add_child(hint)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 16)
	frame.add_child(actions)
	cancel_button = Button.new()
	cancel_button.text = "Back"
	cancel_button.custom_minimum_size.y = 44
	cancel_button.pressed.connect(close)
	actions.add_child(cancel_button)
	apply_button = Button.new()
	apply_button.text = "Apply Character"
	apply_button.custom_minimum_size.y = 44
	apply_button.pressed.connect(_apply)
	actions.add_child(apply_button)
	_resize()


func _arrow(node_name: String, caption: String, x: float, y: float, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = caption
	button.custom_minimum_size = Vector2(44, 44)
	_stage.add_child(button)
	button.set_anchor(SIDE_LEFT, x)
	button.set_anchor(SIDE_RIGHT, x)
	button.set_anchor(SIDE_TOP, y)
	button.set_anchor(SIDE_BOTTOM, y)
	button.offset_left = -44.0 if x > 0.0 else 0.0
	button.offset_right = 0.0 if x > 0.0 else 44.0
	button.offset_top = -22.0
	button.offset_bottom = 22.0
	button.pressed.connect(callback)
	return button


func _resize() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var panel_size := Vector2(minf(540, viewport_size.x - 24), minf(660, viewport_size.y - 24))
	_panel.size = panel_size
	_panel.position = (viewport_size - panel_size) * 0.5
	_stage.custom_minimum_size.y = minf(240, maxf(viewport_size.y - 440, 180))


func open() -> void:
	CharacterAppearance.reload_catalogues()
	_draft = CharacterAppearance.sanitize(SettingsManager.get_character_appearance())
	eye_picker.color = Color.html(_draft["eye_color"])
	_refresh()
	show()
	hat_next.grab_focus()


func close() -> void:
	eye_picker.get_popup().hide()
	hide()
	closed.emit()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel") and not eye_picker.get_popup().visible:
		get_viewport().set_input_as_handled()
		close()


func _cycle(part: String, direction: int) -> void:
	var options := CharacterAppearance.HATS.keys() if part == "hat" else CharacterAppearance.FACES.keys()
	if part == "hat":
		options = [""] + CharacterAppearance.HATS.keys()
	if part == "mouth":
		options = [""] + CharacterAppearance.MOUTHS.keys()
	if options.is_empty():
		return
	_draft[part] = options[posmod(options.find(_draft[part]) + direction, options.size())]
	_refresh()


func _on_eye_color_changed(color: Color) -> void:
	_draft["eye_color"] = color.to_html(false)
	_refresh()


func _refresh() -> void:
	if preview == null:
		return
	preview.texture = CharacterAppearance.resources(_draft)["texture"]
	if eye_picker.color.to_html(false) != _draft["eye_color"]:
		eye_picker.color = Color.html(_draft["eye_color"])
	hat_label.text = Localization.text("No Hat") if _draft["hat"].is_empty() else Localization.format_text("Character Hat %d / %d", [CharacterAppearance.HATS.keys().find(_draft["hat"]) + 1, CharacterAppearance.HATS.size()])
	face_label.text = Localization.format_text("Character Face %d / %d", [CharacterAppearance.FACES.keys().find(_draft["face"]) + 1, CharacterAppearance.FACES.size()])
	mouth_label.text = Localization.text("No Mouth") if _draft["mouth"].is_empty() else Localization.format_text("Character Mouth %d / %d", [CharacterAppearance.MOUTHS.keys().find(_draft["mouth"]) + 1, CharacterAppearance.MOUTHS.size()])
	hat_previous.disabled = CharacterAppearance.HATS.is_empty()
	hat_next.disabled = hat_previous.disabled
	face_previous.disabled = CharacterAppearance.FACES.size() < 2
	face_next.disabled = face_previous.disabled
	mouth_previous.disabled = CharacterAppearance.MOUTHS.is_empty()
	mouth_next.disabled = mouth_previous.disabled
	hat_previous.tooltip_text = Localization.text("Previous Hat")
	hat_next.tooltip_text = Localization.text("Next Hat")
	face_previous.tooltip_text = Localization.text("Previous Face")
	face_next.tooltip_text = Localization.text("Next Face")
	mouth_previous.tooltip_text = Localization.text("Previous Mouth")
	mouth_next.tooltip_text = Localization.text("Next Mouth")


func _apply() -> void:
	SettingsManager.set_character_appearance(_draft, true)
	close()
