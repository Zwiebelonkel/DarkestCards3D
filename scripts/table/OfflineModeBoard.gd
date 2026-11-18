extends Node3D

## The same viewport-on-a-mesh interaction used by the upgrade machines.
## Nothing in this viewport is attached to the player's screen canvas.
const MENU := preload("res://scripts/ui/OfflineModeMenu.gd")
const BOARD_SIZE := Vector2(5.5, 3.6)
const TEXTURE_SIZE := Vector2i(1320, 864)
const SLIDE_OFFSET := Vector3(-12.0, 0, 0)
const SLIDE_DURATION := 0.32

var camera: Camera3D
var focus_controller: ScreenCameraFocus
var focus_area: Area3D
var focus_marker: Marker3D
var viewport: SubViewport
var menu: Control
var _tokens: Array[Node3D] = []
var _pointer_inside := false
var _dragging := false
var _last_pointer := Vector2.ZERO
var _board_body: Node3D
var _slide_tween: Tween
var _is_open := false


func _ready() -> void:
	position = Vector3(0, 0.25, 0)
	_board_body = Node3D.new()
	_board_body.name = "SlidingBoard"
	add_child(_board_body)
	_build_frame()
	viewport = SubViewport.new()
	viewport.name = "BoardViewport"
	viewport.size = TEXTURE_SIZE
	viewport.disable_3d = true
	viewport.gui_disable_input = false
	viewport.gui_embed_subwindows = true
	viewport.handle_input_locally = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	menu = MENU.new()
	menu.name = "BoardContent"
	viewport.add_child(menu)
	var surface := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = BOARD_SIZE
	surface.mesh = quad
	surface.rotation_degrees.x = -90
	surface.position.y = 0.052
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = viewport.get_texture()
	material.albedo_color = Color(0.72, 0.72, 0.72)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	surface.material_override = material
	_board_body.add_child(surface)
	focus_area = Area3D.new()
	focus_area.name = "BoardArea"
	focus_area.rotation_degrees.x = -90
	focus_area.position.y = surface.position.y
	focus_area.collision_layer = 0
	focus_area.collision_mask = 0
	add_child(focus_area)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(BOARD_SIZE.x, BOARD_SIZE.y, 0.08)
	collision.shape = shape
	focus_area.add_child(collision)
	focus_marker = Marker3D.new()
	focus_marker.name = "BoardCamera"
	add_child(focus_marker)
	focus_area.set_meta("focus_camera_marker", focus_marker)
	focus_area.set_meta("focus_fov", 49.0)
	for index in range(10):
		_tokens.append(_make_token())
	hide_board(false)


func _build_frame() -> void:
	_box(Vector3(BOARD_SIZE.x + 0.28, 0.10, BOARD_SIZE.y + 0.28), Vector3.ZERO, Color("33251c"))
	for side in [-1.0, 1.0]:
		_box(Vector3(0.10, 0.09, BOARD_SIZE.y + 0.12), Vector3(side * (BOARD_SIZE.x * 0.5 + 0.05), 0.045, 0), Color("987c4a"))
		_box(Vector3(BOARD_SIZE.x + 0.12, 0.09, 0.10), Vector3(0, 0.045, side * (BOARD_SIZE.y * 0.5 + 0.05)), Color("987c4a"))
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			_box(Vector3(0.20, 0.015, 0.20), Vector3(x * BOARD_SIZE.x * 0.5, 0.095, z * BOARD_SIZE.y * 0.5), Color("c2a36e"))


func _box(dimensions: Vector3, location: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = dimensions
	mesh.mesh = box
	mesh.position = location
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color * Color(0.35, 0.35, 0.35, 1.0)
	material.roughness = 0.85
	mesh.material_override = material
	_board_body.add_child(mesh)


func _make_token() -> Node3D:
	var token := Node3D.new()
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.10
	cylinder.bottom_radius = 0.12
	cylinder.height = 0.045
	cylinder.radial_segments = 24
	mesh.mesh = cylinder
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("9c8357")
	mesh.material_override = material
	token.add_child(mesh)
	var label := Label3D.new()
	label.name = "Number"
	label.font = Localization.FONT
	label.font_size = 44
	label.pixel_size = 0.0019
	label.outline_size = 0
	label.rotation_degrees.x = -90
	label.position.y = 0.024
	token.add_child(label)
	_board_body.add_child(token)
	return token


func set_focus_controller(controller: ScreenCameraFocus) -> void:
	focus_controller = controller
	focus_controller.register_screen(focus_area, 0, 0)


func show_board() -> void:
	_stop_slide()
	_is_open = true
	if not visible:
		_board_body.position = SLIDE_OFFSET
	show()
	menu.set_process_input(true)
	focus_area.input_ray_pickable = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_update_camera_marker()
	# Opening the board requests the same eased focus as hovering a machine.
	if is_instance_valid(focus_controller):
		focus_controller.set_context(0, true, 0)
		focus_controller.focus_screen(focus_area)
	# Only the visible board moves; camera framing stays at its resting pose.
	_slide_tween = create_tween()
	_slide_tween.tween_property(_board_body, "position", Vector3.ZERO, SLIDE_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func hide_board(animated: bool = true) -> void:
	if animated and not _is_open:
		return
	_is_open = false
	_stop_slide()
	if is_instance_valid(focus_controller) and visible:
		# GameTable takes over the current pose for its return/match tween.
		# Release even if pointer exit has already started the focus return.
		focus_controller.release_camera()
	menu.set_process_input(false)
	if is_instance_valid(focus_area):
		focus_area.input_ray_pickable = false
	if is_instance_valid(viewport):
		viewport.gui_release_focus()
		if _pointer_inside:
			viewport.notify_mouse_exited()
	_pointer_inside = false
	_dragging = false
	if animated and visible:
		_slide_tween = create_tween()
		_slide_tween.tween_property(_board_body, "position", SLIDE_OFFSET, SLIDE_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		_slide_tween.tween_callback(_finish_hide)
	else:
		_finish_hide()


func is_open() -> bool:
	return _is_open


func _stop_slide() -> void:
	if _slide_tween != null:
		_slide_tween.kill()
		_slide_tween = null


func _finish_hide() -> void:
	hide()
	menu.hide()
	_board_body.position = SLIDE_OFFSET
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for token in _tokens:
		token.hide()


func _process(_delta: float) -> void:
	if not visible:
		return
	_sync_tokens()


func _update_camera_marker() -> void:
	if not is_instance_valid(camera):
		return
	var view_size := camera.get_viewport().get_visible_rect().size
	var aspect := view_size.x / maxf(view_size.y, 1.0)
	var half_span := maxf(BOARD_SIZE.y * 0.5, BOARD_SIZE.x * 0.5 / maxf(aspect, 0.1))
	var distance := half_span * 1.18 / tan(deg_to_rad(49.0 * 0.5))
	focus_marker.position = Vector3(0, distance * 0.96, distance * 0.28)
	focus_marker.look_at(to_global(Vector3.ZERO), Vector3.UP)


func _sync_tokens() -> void:
	for token in _tokens:
		token.hide()
	if not is_instance_valid(menu.level_map) or not menu.visible:
		return
	var map: Control = menu.level_map
	var scroll: ScrollContainer = menu._story_scroll
	var clip := scroll.get_global_rect().grow(-20)
	var index := 0
	for level_index in range(map.buttons.size()):
		var button: Button = map.buttons[level_index]
		# The actual clickable footprint lives in the board viewport. Its
		# raised wooden token and number are genuine world-space geometry.
		button.modulate.a = 0.0
		var center := button.get_global_rect().get_center()
		if not clip.has_point(center) or index >= _tokens.size():
			continue
		var token := _tokens[index]
		token.position = Vector3((center.x / TEXTURE_SIZE.x - 0.5) * BOARD_SIZE.x, 0.079, (center.y / TEXTURE_SIZE.y - 0.5) * BOARD_SIZE.y)
		var label := token.get_node("Number") as Label3D
		label.text = str(level_index + 1)
		label.modulate = Color("17131a") if not button.disabled else Color("635d68")
		var material := (token.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
		material.albedo_color = (Color("3b3442") if button.disabled else (Color("edd09b") if level_index + 1 == map.selected_level else Color("ac9263"))) * Color(0.35, 0.35, 0.35, 1.0)
		token.show()
		index += 1


func board_to_screen(pixel: Vector2) -> Vector2:
	var local := Vector3((pixel.x / TEXTURE_SIZE.x - 0.5) * BOARD_SIZE.x, (0.5 - pixel.y / TEXTURE_SIZE.y) * BOARD_SIZE.y, 0)
	return camera.unproject_position(focus_area.to_global(local))


func pointer_to_board(pointer: Vector2) -> Vector2:
	var origin := camera.project_ray_origin(pointer)
	var direction := camera.project_ray_normal(pointer)
	var plane := Plane(focus_area.global_basis.z.normalized(), focus_area.global_position)
	var hit: Variant = plane.intersects_ray(origin, direction)
	if hit == null:
		return Vector2.INF
	var local := focus_area.to_local(hit)
	return Vector2((0.5 + local.x / BOARD_SIZE.x) * TEXTURE_SIZE.x, (0.5 - local.y / BOARD_SIZE.y) * TEXTURE_SIZE.y)


func _input(event: InputEvent) -> void:
	if not _is_open or not visible or not menu.visible or get_tree().paused or not is_instance_valid(camera):
		return
	if event is InputEventKey:
		for window in viewport.get_embedded_subwindows():
			if window.visible:
				# Let the open card picker handle Escape before closing the board.
				viewport.push_input(event, true)
				get_viewport().set_input_as_handled()
				return
	if event.is_action_pressed("ui_cancel"):
		menu._go_back()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		viewport.push_input(event, true)
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouse:
		return
	if _slide_tween != null and _slide_tween.is_running():
		return
	var point := pointer_to_board(event.position)
	var inside := Rect2(Vector2.ZERO, Vector2(TEXTURE_SIZE)).has_point(point)
	if inside != _pointer_inside:
		_pointer_inside = inside
		if inside:
			viewport.notify_mouse_entered()
		else:
			viewport.notify_mouse_exited()
	if not inside and not _dragging:
		return
	var forwarded := event.duplicate() as InputEventMouse
	forwarded.position = point if point.is_finite() else Vector2(-100, -100)
	forwarded.global_position = forwarded.position
	if forwarded is InputEventMouseMotion:
		forwarded.relative = forwarded.position - _last_pointer
	_last_pointer = forwarded.position
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	viewport.push_input(forwarded, true)
	get_viewport().set_input_as_handled()
