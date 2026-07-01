extends Node
class_name PackShopScreenInput

@export var screen_area: Area3D
@export var pack_shop_viewport: SubViewport
@export var screen_size := Vector2(1.0, 0.65)
@export var input_y_offset := 0.06


func _ready() -> void:
	if screen_area == null:
		screen_area = get_node_or_null("../ScreenArea") as Area3D

	if pack_shop_viewport == null:
		pack_shop_viewport = get_node_or_null("../PackShopViewport") as SubViewport

	if screen_area:
		screen_area.input_event.connect(_on_screen_input_event)


func _on_screen_input_event(
	_camera: Node,
	event: InputEvent,
	position: Vector3,
	_normal: Vector3,
	_shape_idx: int
) -> void:
	if pack_shop_viewport == null:
		return

	var local_pos := screen_area.to_local(position)

	var uv := Vector2(
		0.5 - (local_pos.x / screen_size.x),
		0.5 - (local_pos.y / screen_size.y) + input_y_offset
	)

	if uv.x < 0.0 or uv.x > 1.0:
		return

	if uv.y < 0.0 or uv.y > 1.0:
		return

	var viewport_event := event.duplicate()
	viewport_event.position = Vector2(
		uv.x * float(pack_shop_viewport.size.x),
		uv.y * float(pack_shop_viewport.size.y)
	)

	if viewport_event is InputEventMouse:
		viewport_event.global_position = viewport_event.position

	pack_shop_viewport.push_input(viewport_event)
	get_viewport().set_input_as_handled()
