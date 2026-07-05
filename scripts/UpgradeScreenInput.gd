extends Node
class_name UpgradeScreenInput

@export var machine: UpgradeMachine
@export var screen_area: Area3D
@export var upgrade_viewport: SubViewport
@export var screen_size := Vector2(1.0, 0.65)
@export var input_y_offset := 0.06
@export var debug_screen_input := true


func _ready() -> void:
	if machine == null:
		machine = get_parent() as UpgradeMachine

	if screen_area == null:
		screen_area = get_node_or_null("../ScreenArea") as Area3D

	if upgrade_viewport == null:
		upgrade_viewport = get_node_or_null("../UpgradeViewport") as SubViewport

	if screen_area:
		screen_area.input_event.connect(_on_screen_input_event)


func _on_screen_input_event(
	_camera: Node,
	event: InputEvent,
	position: Vector3,
	_normal: Vector3,
	_shape_idx: int
) -> void:
	if debug_screen_input and event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		print("[InteractionDebug] ", name, ": ScreenArea input_event angekommen. event=", event, " world_position=", position)

	if upgrade_viewport == null:
		if debug_screen_input:
			print("[InteractionDebug] ", name, ": Viewport fehlt, Event wird nicht weitergeleitet.")
		return

	var local_pos := screen_area.to_local(position)

	var uv := Vector2(
		0.5 - (local_pos.x / screen_size.x),
		0.5 - (local_pos.y / screen_size.y) + input_y_offset
	)

	if uv.x < 0.0 or uv.x > 1.0:
		if debug_screen_input and event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			print("[InteractionDebug] ", name, ": Klick außerhalb Screen-UV auf X. local=", local_pos, " uv=", uv)
		return
	if uv.y < 0.0 or uv.y > 1.0:
		if debug_screen_input and event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			print("[InteractionDebug] ", name, ": Klick außerhalb Screen-UV auf Y. local=", local_pos, " uv=", uv)
		return

	var viewport_event := event.duplicate()
	viewport_event.position = Vector2(
		uv.x * float(upgrade_viewport.size.x),
		uv.y * float(upgrade_viewport.size.y)
	)

	if viewport_event is InputEventMouse:
		viewport_event.global_position = viewport_event.position

	if debug_screen_input and event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		print("[InteractionDebug] ", name, ": leite Klick an SubViewport weiter. uv=", uv, " viewport_position=", viewport_event.position)

	upgrade_viewport.push_input(viewport_event)
	get_viewport().set_input_as_handled()
