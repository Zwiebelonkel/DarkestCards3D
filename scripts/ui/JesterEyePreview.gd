extends Sprite3D

## Private, transparent 3D view keeps the eye above the camera-mounted tray.
const EYE := preload("res://assets/environments/props/eye/eye.glb")
var model_scene: PackedScene = EYE
var normalize_model := false
var eye: Node3D
var viewport: SubViewport

func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.85, 0.9, 1.0)
	environment.ambient_light_energy = 0.65
	world.environment = environment
	viewport.add_child(world)
	var camera := Camera3D.new()
	camera.position.z = 3.5
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.8
	viewport.add_child(camera)
	camera.current = true
	var light := OmniLight3D.new()
	light.position = Vector3(-2, 3, 4)
	light.light_energy = 1.4
	viewport.add_child(light)
	eye = Node3D.new()
	viewport.add_child(eye)
	var model := model_scene.instantiate() as Node3D
	eye.add_child(model)
	if normalize_model:
		var bounds := AABB()
		var found := false
		for child in model.find_children("*", "MeshInstance3D", true, false):
			var mesh := child as MeshInstance3D
			if mesh.mesh == null:
				continue
			var relative := model.global_transform.affine_inverse() * mesh.global_transform
			var box: AABB = relative * mesh.get_aabb()
			bounds = bounds.merge(box) if found else box
			found = true
		if found:
			var factor := 2.0 / maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
			model.scale = Vector3.ONE * factor
			model.position = -bounds.get_center() * factor
	texture = viewport.get_texture()
	no_depth_test = true
	render_priority = 88
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR

func follow_pointer(pointer: Vector2, camera: Camera3D, delta: float) -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# A target on a plane in front of the tray lets the eye track the entire
	# screen while retaining a visible iris at its most extreme angles.
	var origin := camera.to_local(global_position)
	var target := camera.to_local(camera.project_position(pointer, maxf(-origin.z * 0.55, camera.near)))
	var direction := (target - origin).normalized()
	var desired := Basis.looking_at(direction, Vector3.UP, true).get_rotation_quaternion()
	eye.quaternion = eye.quaternion.slerp(desired, 1.0 - exp(-12.0 * delta))

func suspend() -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
