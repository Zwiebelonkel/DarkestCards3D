extends SubViewportContainer
class_name PackPreviewViewport

signal pressed(pack_id: String)

@export var pack_id := ""
@export var pack_name := ""
@export var pack_scene: PackedScene
@export var rotation_speed := 0.8
@export var viewport_size := Vector2i(220, 180)
@export var viewport_fps := 12.0

@onready var viewport: SubViewport = $SubViewport
@onready var camera: Camera3D = $SubViewport/World/Camera3D
@onready var light: OmniLight3D = $SubViewport/World/OmniLight3D
@onready var model_root: Node3D = $SubViewport/World/ModelRoot

var pack_model: Node3D = null
var label: Label = null
var _viewport_timer := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	stretch = true
	custom_minimum_size = Vector2(viewport_size)

	_setup_viewport()
	_setup_camera()
	_setup_light()
	_spawn_pack_model()
	_setup_label()

	await get_tree().process_frame
	_force_viewport_refresh()


func _setup_viewport() -> void:
	viewport.disable_3d = false
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.size = viewport_size
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.handle_input_locally = false


func _setup_camera() -> void:
	camera.current = true
	camera.fov = 35.0
	camera.position = Vector3(0, 0.75, 3.0)
	camera.look_at(Vector3(0, 0.25, 0), Vector3.UP)


func _setup_light() -> void:
	if light == null:
		return

	light.position = Vector3(0, 2.0, 2.0)
	light.light_energy = 2.5


func _spawn_pack_model() -> void:
	for child in model_root.get_children():
		child.queue_free()

	if pack_scene == null:
		return

	pack_model = pack_scene.instantiate() as Node3D
	model_root.add_child(pack_model)

	pack_model.position = Vector3.ZERO
	pack_model.rotation_degrees = Vector3.ZERO
	pack_model.scale = Vector3.ONE * 0.75


func _setup_label() -> void:
	label = Label.new()
	label.text = pack_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(label)


func _force_viewport_refresh() -> void:
	viewport.own_world_3d = false
	await get_tree().process_frame

	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame

	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _process(delta: float) -> void:
	_viewport_timer += delta

	if _viewport_timer < 1.0 / viewport_fps:
		return

	_viewport_timer = 0.0

	if pack_model:
		pack_model.rotate_y(rotation_speed / viewport_fps)

	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			pressed.emit(pack_id)
