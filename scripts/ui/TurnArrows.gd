extends CanvasLayer
class_name TurnArrows

## Edge navigation lives below the camera filters and never captures the
## full screen. Hover reveals a button; only a completed click requests a turn.
signal turn_requested(direction: int)

const BUTTON_SIZE := Vector2(48, 56)
const EDGE_MARGIN := 12.0

class ArrowButton extends BaseButton:
	var direction := 1

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		button_down.connect(queue_redraw)
		button_up.connect(queue_redraw)

	func _draw() -> void:
		var center := size * 0.5
		var color := Color("f4e4c1") if is_hovered() else Color("cfc4b0")
		if is_pressed():
			color = Color("e9b563")
		var backdrop := Rect2(center - Vector2(18, 23), Vector2(36, 46))
		draw_rect(backdrop, Color(0.035, 0.025, 0.02, 0.86))
		draw_rect(backdrop, Color(0.55, 0.45, 0.29, 0.65), false, 1.0)
		# Seven square rows make a crisp chevron without font/glyph fallback.
		for row in range(7):
			var offset := float(3 - absi(3 - row)) * 4.0 - 8.0
			var x := offset if direction > 0 else -offset - 8.0
			draw_rect(Rect2(center + Vector2(x, row * 4.0 - 14.0), Vector2(8, 4)), color)


var left_button: BaseButton
var right_button: BaseButton
var _turn_allowed: Callable
var _pointer_inside := true
var _pressed_button: BaseButton


func _ready() -> void:
	layer = 0
	# Only this presentation continues during pause, so it can immediately
	# disappear. The turn predicate and GUI state always respect tree pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	left_button = _make_button(-1)
	right_button = _make_button(1)
	# Native Window exposes these signals; embedded SubViewports instead
	# provide pointer coordinates through their parent input surface.
	if get_viewport().has_signal("mouse_entered"):
		get_viewport().connect("mouse_entered", _on_pointer_entered)
		get_viewport().connect("mouse_exited", _on_pointer_exited)
	SettingsManager.presentation_settings_changed.connect(refresh)
	refresh()


func configure(turn_allowed: Callable) -> void:
	_turn_allowed = turn_allowed
	refresh()


func _make_button(direction: int) -> BaseButton:
	var button := ArrowButton.new()
	button.name = "Left" if direction < 0 else "Right"
	button.direction = direction
	button.size = BUTTON_SIZE
	button.hide()
	add_child(button)
	button.button_down.connect(func(): _pressed_button = button)
	button.button_up.connect(func():
		if _pressed_button == button:
			_pressed_button = null
	)
	button.pressed.connect(_on_arrow_pressed.bind(direction))
	return button


func _process(_delta: float) -> void:
	refresh()


func refresh() -> void:
	if not is_node_ready() or not is_inside_tree():
		return
	var allowed := (
		SettingsManager.turn_arrows_enabled and not get_tree().paused
		and _turn_allowed.is_valid() and bool(_turn_allowed.call())
	)
	var viewport_size := get_viewport().get_visible_rect().size
	var pointer := get_viewport().get_mouse_position()
	var edge_width := clampf(viewport_size.x * 0.066, 64.0, 108.0)
	var inside := _pointer_inside and Rect2(Vector2.ZERO, viewport_size).has_point(pointer)
	_update_button(left_button, allowed and inside and pointer.x <= edge_width, EDGE_MARGIN, pointer.y, viewport_size.y)
	_update_button(right_button, allowed and inside and pointer.x >= viewport_size.x - edge_width, viewport_size.x - EDGE_MARGIN - BUTTON_SIZE.x, pointer.y, viewport_size.y)


func _update_button(button: BaseButton, shown: bool, x: float, pointer_y: float, height: float) -> void:
	if not shown and _pressed_button == button:
		_pressed_button = null
	button.disabled = not shown
	button.visible = shown
	# Keep a pressed button still until release; dragging away cancels the click.
	if button != _pressed_button:
		button.position = Vector2(x, clampf(pointer_y - BUTTON_SIZE.y * 0.5, EDGE_MARGIN, maxf(EDGE_MARGIN, height - EDGE_MARGIN - BUTTON_SIZE.y)))


func is_pointer_over_arrow() -> bool:
	if not is_node_ready():
		return false
	var pointer := get_viewport().get_mouse_position()
	return (left_button.visible and left_button.get_global_rect().has_point(pointer)) or (right_button.visible and right_button.get_global_rect().has_point(pointer))


func _on_arrow_pressed(direction: int) -> void:
	if SettingsManager.turn_arrows_enabled and not get_tree().paused and _turn_allowed.is_valid() and bool(_turn_allowed.call()):
		turn_requested.emit(direction)
	refresh()


func _on_pointer_entered() -> void:
	_pointer_inside = true
	refresh()


func _on_pointer_exited() -> void:
	_pointer_inside = false
	refresh()
