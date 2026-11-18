extends Control

signal level_selected(level: int)

const RULES := preload("res://scripts/match/OfflineMatchRules.gd")
var buttons: Array[Button] = []
var row_height := 64.0
var selected_level := 1


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	for level in range(1, RULES.LEVEL_COUNT + 1):
		var button := Button.new()
		button.custom_minimum_size = Vector2(110, 44)
		button.pressed.connect(_select.bind(level))
		add_child(button)
		buttons.append(button)
	resized.connect(_layout)
	refresh()


func fit_viewport(height: float) -> void:
	# Nine row intervals means at most ten intersecting buttons, including
	# partial rows during smooth scrolling, at any window size.
	row_height = maxf(64.0, height / 9.0)
	custom_minimum_size.y = row_height * RULES.LEVEL_COUNT
	_layout()


func refresh() -> void:
	for index in range(buttons.size()):
		var level := index + 1
		var button := buttons[index]
		button.disabled = not GameCurrency.is_story_level_unlocked(level)
		button.text = "%d%s" % [level, "  ✓" if level <= GameCurrency.story_completed_level else ""]
		button.modulate = Color("e9c98c") if level == selected_level else Color.WHITE
		button.tooltip_text = Localization.text("Gesperrt") if button.disabled else Localization.format_text("Level %d", [level])
	queue_redraw()


func _select(level: int) -> void:
	if not GameCurrency.is_story_level_unlocked(level):
		return
	selected_level = level
	refresh()
	level_selected.emit(level)


func _center(index: int) -> Vector2:
	var steps := [0.2, 0.5, 0.8, 0.5]
	return Vector2(60.0 + maxf(size.x - 120.0, 0.0) * float(steps[index % 4]), (index + 0.5) * row_height)


func _layout() -> void:
	for index in range(buttons.size()):
		buttons[index].size = Vector2(110, 44)
		buttons[index].position = _center(index) - buttons[index].size * 0.5
	queue_redraw()


func _draw() -> void:
	for index in range(RULES.LEVEL_COUNT - 1):
		var start := _center(index)
		var end := _center(index + 1)
		if index + 1 <= GameCurrency.story_completed_level:
			draw_line(start, end, Color("c8a86c"), 3.0, true)
		else:
			draw_dashed_line(start, end, Color("605862"), 2.0, 7.0, true)
