extends Control

signal closed
signal story_requested(level: int)
signal training_requested(indices: Array[int], enemies: Array[Dictionary])

const RULES := preload("res://scripts/match/OfflineMatchRules.gd")
const LEVEL_MAP := preload("res://scripts/ui/StoryLevelMap.gd")
var _body: VBoxContainer
var _title: Label
var _hint: Label
var _next: Button
var _back: Button
var _story_scroll: ScrollContainer
var level_map: Control
var _mode := ""
var _step := 0
var _selected_level := 1
var _pool: Array[Dictionary] = []
var _indices: Array[int] = [0, 1, 2, 3, 4]
var _enemies: Array[Dictionary] = []
var _catalog: Array[Dictionary] = []
var _own_selectors: Array[OptionButton] = []
var _margin: MarginContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color("292a29")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	_margin = margin
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var theme_data := Theme.new()
	theme_data.default_font = Localization.FONT
	theme_data.default_font_size = 20
	for type_name in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("403b32") if state != "disabled" else Color("302e29")
			style.border_color = Color("d9bb80") if state in ["hover", "pressed", "focus"] else Color("8b795c")
			style.set_border_width_all(2)
			style.set_corner_radius_all(6)
			style.content_margin_left = 12
			style.content_margin_right = 12
			theme_data.set_stylebox(state, type_name, style)
		theme_data.set_color("font_color", type_name, Color("f5ebd7"))
		theme_data.set_color("font_disabled_color", type_name, Color("a79ead"))
	theme = theme_data
	_title = _label("", 28)
	column.add_child(_title)
	_body = VBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_body)
	_hint = _label("")
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_hint)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 20)
	column.add_child(footer)
	_back = _button("Zurück", _go_back)
	footer.add_child(_back)
	_next = _button("", _advance)
	_next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_next)
	Localization.locale_changed.connect(_refresh_language)
	resized.connect(_fit_width)
	_fit_width.call_deferred()
	hide()


func _fit_width() -> void:
	var side := maxi(24, int((size.x - 1100) * 0.5))
	_margin.add_theme_constant_override("margin_left", side)
	_margin.add_theme_constant_override("margin_right", side)


func _label(text_value: String, font_size: int = 18) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("ded3c0"))
	return label


func _button(caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 44
	button.pressed.connect(action)
	return button


func _clear_body() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_own_selectors.clear()
	level_map = null
	_story_scroll = null


func open_story() -> void:
	_mode = "story"
	_selected_level = mini(GameCurrency.story_completed_level + 1, RULES.LEVEL_COUNT)
	show()
	_build_story()


func _build_story() -> void:
	_clear_body()
	_title.text = Localization.format_text("Story - %d / 100 abgeschlossen", [GameCurrency.story_completed_level])
	_story_scroll = ScrollContainer.new()
	_story_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_story_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(_story_scroll)
	level_map = LEVEL_MAP.new()
	_story_scroll.add_child(level_map)
	level_map.selected_level = _selected_level
	level_map.level_selected.connect(_select_story)
	_story_scroll.resized.connect(_fit_map)
	_fit_map.call_deferred()
	_scroll_to_selected.call_deferred()
	_select_story(_selected_level)


func _fit_map() -> void:
	if is_instance_valid(level_map) and is_instance_valid(_story_scroll):
		level_map.fit_viewport(_story_scroll.size.y)


func _scroll_to_selected() -> void:
	if is_instance_valid(_story_scroll) and is_instance_valid(level_map):
		_story_scroll.scroll_vertical = int(maxi(_selected_level - 3, 0) * level_map.row_height)


func _select_story(level: int) -> void:
	_selected_level = level
	var rewards := RULES.story_rewards(level)
	_hint.text = Localization.format_text("Level %d - Kartenwert %d - Sieg: %d XP + %d Münzen (vor Boni)", [level, RULES.story_card_value(level), rewards["xp"], rewards["coins"]])
	_next.text = Localization.format_text("Level %d starten", [level])
	_next.disabled = DeckManager.is_empty() or not GameCurrency.is_story_level_unlocked(level)
	if DeckManager.is_empty():
		_hint.text = Localization.text("Stelle zuerst dein Kampfdeck in der Sammlung zusammen.")
	level_map.refresh()


func open_training() -> void:
	_mode = "training"
	_step = 0
	_pool = DeckManager.get_deck_card_data()
	_indices.assign([0, 1, 2, 3, 4])
	_catalog.assign(CardDatabase.get_combat_cards())
	_catalog.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"]))
	_enemies.clear()
	for index in range(RULES.TRAINING_DECK_SIZE):
		_enemies.append(RULES.training_card(100, 500))
	show()
	_build_training()


func _build_training() -> void:
	_clear_body()
	_title.text = Localization.text("Training - 1 / 2 - Dein Deck" if _step == 0 else "Training - 2 / 2 - Gegnerdeck")
	_next.text = Localization.text("Gegnerdeck zusammenstellen" if _step == 0 else "Training starten")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 14)
	scroll.add_child(rows)
	var explanation := _label(Localization.text("Wähle fünf verschiedene Kopien aus deinem Kampfdeck." if _step == 0 else "Pro Platz: echte Karte oder Trainingskarte mit eigenen Werten."))
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(explanation)
	for index in range(RULES.TRAINING_DECK_SIZE):
		if _step == 0:
			_build_own_row(rows, index)
		else:
			_build_enemy_row(rows, index)
	_validate_training()


func _card_caption(card: Dictionary) -> String:
	return "%s - %d / %d" % [Localization.text(str(card.get("name", ""))), int(card.get("attack", 0)), int(card.get("defense", 0))]


func _selector(parent: Control) -> OptionButton:
	var selector := OptionButton.new()
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector.fit_to_longest_item = false
	selector.custom_minimum_size = Vector2(120, 40)
	parent.add_child(selector)
	return selector


func _build_own_row(parent: Control, index: int) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	row.add_child(_label("%d. " % (index + 1)))
	var selector := _selector(row)
	for pool_index in range(_pool.size()):
		selector.add_item("%d - %s" % [pool_index + 1, _card_caption(_pool[pool_index])])
	selector.select(_indices[index] if _indices[index] < _pool.size() else -1)
	selector.item_selected.connect(func(value: int) -> void:
		_indices[index] = value
		_validate_training()
	)
	_own_selectors.append(selector)


func _build_enemy_row(parent: Control, index: int) -> void:
	var column := VBoxContainer.new()
	parent.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	row.add_child(_label("%d. " % (index + 1)))
	var selector := _selector(row)
	selector.add_item(Localization.text("Trainingskarte"))
	var selected := 0
	for catalog_index in range(_catalog.size()):
		selector.add_item(_card_caption(_catalog[catalog_index]))
		if str(_enemies[index].get("id", "")) == str(_catalog[catalog_index]["id"]):
			selected = catalog_index + 1
	selector.select(selected)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 12)
	column.add_child(stats)
	stats.add_child(_label(Localization.text("Angriff")))
	var attack := _stat_input(stats, 0, int(_enemies[index].get("attack", 100)))
	stats.add_child(_label(Localization.text("Verteidigung")))
	var defense := _stat_input(stats, 1, int(_enemies[index].get("defense", 500)))
	stats.visible = selected == 0
	attack.value_changed.connect(func(value: float) -> void: _enemies[index]["attack"] = int(value))
	defense.value_changed.connect(func(value: float) -> void: _enemies[index]["defense"] = int(value))
	selector.item_selected.connect(func(value: int) -> void:
		_enemies[index] = RULES.training_card(int(attack.value), int(defense.value)) if value == 0 else _catalog[value - 1].duplicate(true)
		stats.visible = value == 0
	)


func _stat_input(parent: Control, minimum: int, value: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = RULES.MAX_TRAINING_STAT
	spin.step = 1
	spin.value = value
	spin.custom_minimum_size.x = 135
	parent.add_child(spin)
	return spin


func _validate_training() -> void:
	_next.disabled = RULES.training_player_deck(_pool, _indices).size() != RULES.TRAINING_DECK_SIZE
	_hint.text = Localization.text("Training: keine XP, Münzen oder Fortschritte.")
	if _pool.size() < RULES.TRAINING_DECK_SIZE:
		_hint.text = Localization.text("Dein Kampfdeck benötigt mindestens fünf Karten. Ergänze es in der Sammlung.")
	elif _next.disabled:
		_hint.text = Localization.text("Wähle jede Kartenkopie höchstens einmal.")


func _advance() -> void:
	if _next.disabled:
		return
	if _mode == "story":
		story_requested.emit(_selected_level)
	elif _step == 0:
		_step = 1
		_build_training()
	else:
		# Commit edits still focused in a SpinBox before copying its value.
		get_viewport().gui_release_focus()
		training_requested.emit(_indices.duplicate(), _enemies.duplicate(true))


func _go_back() -> void:
	if _mode == "training" and _step == 1:
		_step = 0
		_build_training()
	else:
		closed.emit()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_back()


func _refresh_language() -> void:
	if not visible:
		return
	if _mode == "story":
		_build_story()
	else:
		_build_training()
