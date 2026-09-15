extends Node
class_name CardDiorama

## A card illustration is a window onto a private 3D world. Its projection is
## derived from the real viewer in the illustration's local coordinates, so
## rotating or moving the card reveals the sides of the objects inside it.
const APERTURE_HEIGHT := 2.0
const TEXTURE_SIZE := Vector2i(560, 340)

var _image: MeshInstance3D
var _viewport: SubViewport
var _camera: Camera3D
var _room: Node3D
var _aperture_size := Vector2(0.56, 0.34)


func configure(image: MeshInstance3D, room_scene: PackedScene) -> void:
	_image = image
	if is_instance_valid(_viewport):
		remove_child(_viewport)
		_viewport.queue_free()
	_viewport = SubViewport.new()
	_viewport.name = "DioramaViewport"
	_viewport.size = TEXTURE_SIZE
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.gui_disable_input = true
	_viewport.handle_input_locally = false
	_viewport.physics_object_picking = false
	_viewport.audio_listener_enable_3d = false
	_viewport.audio_listener_enable_2d = false
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_room = room_scene.instantiate() as Node3D
	_viewport.add_child(_room)
	_camera = Camera3D.new()
	_camera.name = "WindowCamera"
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_viewport.add_child(_camera)
	_camera.current = true
	if image.mesh is QuadMesh:
		_aperture_size = (image.mesh as QuadMesh).size
	# Keep one physical scale in X, Y and Z. The texture aspect must agree with
	# the actual illustration rather than stretching a differently sized room.
	_viewport.size.x = roundi(TEXTURE_SIZE.y * _aperture_size.aspect())
	set_process(true)
	_update_camera()


func get_texture() -> ViewportTexture:
	return _viewport.get_texture() if is_instance_valid(_viewport) else null


func _process(_delta: float) -> void:
	_update_camera()


func _update_camera() -> void:
	if not is_instance_valid(_viewport):
		return
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if not is_instance_valid(_image) or not _image.is_inside_tree() or not _image.is_visible_in_tree():
		return
	var source_viewport := _image.get_viewport()
	if source_viewport is SubViewport and source_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED:
		return
	var viewer := source_viewport.get_camera_3d()
	if not is_instance_valid(viewer) or (_image.layers & viewer.cull_mask) == 0:
		return
	var viewer_local := _image.to_local(viewer.global_position)
	if viewer.projection == Camera3D.PROJECTION_ORTHOGONAL:
		# Parallel rays have a vanishing point at infinity. A remote eye gives
		# the same parallax without coupling it to the orthographic camera pan.
		viewer_local = _image.global_basis.inverse() * viewer.global_basis.z * 1000.0
	if viewer_local.z <= 0.001:
		return
	if not _is_on_screen(viewer, source_viewport.get_visible_rect()):
		return
	var eye := viewer_local * (APERTURE_HEIGHT / _aperture_size.y)
	_camera.position = eye
	# The near plane IS the card window. An asymmetric frustum keeps all four
	# aperture corners fixed while the real contents behind them shift in depth.
	_camera.set_frustum(APERTURE_HEIGHT, -Vector2(eye.x, eye.y), eye.z, eye.z + 30.0)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _is_on_screen(viewer: Camera3D, screen: Rect2) -> bool:
	var half_size := _aperture_size * 0.5
	var rect := Rect2()
	var initialized := false
	for corner in [Vector2(-1.0, -1.0), Vector2(-1.0, 1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0)]:
		var world_corner := _image.to_global(Vector3(corner.x * half_size.x, corner.y * half_size.y, 0.0))
		if viewer.is_position_behind(world_corner):
			continue
		var point := viewer.unproject_position(world_corner)
		if not initialized:
			rect = Rect2(point, Vector2.ZERO)
			initialized = true
		else:
			rect = rect.expand(point)
	return initialized and rect.size.x >= 2.0 and rect.size.y >= 2.0 and screen.intersects(rect)
