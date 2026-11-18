extends Node3D

const MACHINE_SCENES := [
	preload("res://scenes/UpgradeShop.tscn"),
	preload("res://scenes/PackShopMachine.tscn"),
]
const CRT_SCENE := preload("res://scenes/crt.tscn")

var _failures: Array[String] = []
var _checks := 0
var _presses := 0
var _downs := 0
var _ups := 0


func _ready() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error(message)


func _run() -> void:
	if not str(DeckManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Run with tests/run_match_feature_tests.ps1 to isolate player saves.")
		get_tree().quit(1)
		return
	GameCurrency._rescued_npcs["angel"] = true
	for scene: PackedScene in MACHINE_SCENES:
		await _check_machine(scene)
	if DisplayServer.get_name() != "headless":
		await _check_crt_rendering()
	else:
		print("SCREEN_INPUT_TESTS: CRT pixel checks skipped; use -Visual to render them.")
	print("SCREEN_INPUT_TESTS: %s (%d checks)" % ["PASS" if _failures.is_empty() else "FAIL", _checks])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check_machine(scene: PackedScene) -> void:
	var holder := Node3D.new()
	add_child(holder)
	var machine := scene.instantiate() as Node3D
	holder.add_child(machine)
	var viewport := machine.get_node("UpgradeViewport" if machine is UpgradeMachine else "PackShopViewport") as SubViewport
	var ui := viewport.get_child(0) as Control
	# Keep the real mesh, collider, viewport and forwarding script. A small
	# calibration button makes offsets visible without purchasing any upgrades.
	ui.hide()
	(ui.get_node("CRTPostFXLayer/Screen") as Control).hide()
	var area := machine.get_node("ScreenArea") as Area3D
	area.input_ray_pickable = false
	var mesh := machine.get_node("MachineModel/ScreenMesh") as MeshInstance3D
	var quad := mesh.mesh as QuadMesh
	var camera := Camera3D.new()
	holder.add_child(camera)
	var button := Button.new()
	button.size = Vector2(20, 16)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func(): _presses += 1)
	button.button_down.connect(func(): _downs += 1)
	button.button_up.connect(func(): _ups += 1)
	viewport.add_child(button)
	await get_tree().process_frame
	viewport.notify_mouse_entered()
	for transformed in [false, true]:
		if transformed:
			holder.position = Vector3(4.0, -1.2, 2.5)
			holder.rotation = Vector3(0.14, 0.61, -0.09)
			holder.scale = Vector3(1.4, 0.8, 2.1)
		for y in [0.025, 0.5, 0.975]:
			for x in [0.025, 0.5, 0.975]:
				var uv := Vector2(x, y)
				var target := uv * Vector2(viewport.size)
				button.position = target - button.size * 0.5
				# Derive the hit from visible QuadMesh coordinates rather than
				# copying the forwarding script's Area3D coordinate calculation.
				var hit := mesh.to_global(Vector3((x - 0.5) * quad.size.x, (0.5 - y) * quad.size.y, 0.0))
				var label := "%s %s %s" % [machine.name, "transformed" if transformed else "original", uv]
				var motion := InputEventMouseMotion.new()
				motion.position = Vector2(137, 81)
				motion.global_position = motion.position
				area.input_event.emit(camera, motion, hit, Vector3.FORWARD, 0)
				_expect(viewport.gui_get_hovered_control() == button, label + " hovers the visible button")
				_expect(motion.position == Vector2(137, 81), label + " preserves the source event")
				var before := Vector3i(_downs, _ups, _presses)
				_send_button(area, camera, hit, true)
				_expect(button.button_pressed and _downs == before.x + 1 and _presses == before.z, label + " begins a press without activating early")
				_send_button(area, camera, hit, false)
				_expect(not button.button_pressed and _ups == before.y + 1 and _presses == before.z + 1, label + " activates exactly once on release")
	# All four outside edges must be rejected, even if a Control extends past
	# the viewport. A non-mouse event must also leave the button untouched.
	for uv: Vector2 in [Vector2(-0.02, 0.5), Vector2(1.02, 0.5), Vector2(0.5, -0.02), Vector2(0.5, 1.02)]:
		button.position = uv * Vector2(viewport.size) - button.size * 0.5
		var hit := mesh.to_global(Vector3((uv.x - 0.5) * quad.size.x, (0.5 - uv.y) * quad.size.y, 0.0))
		var before := _presses
		_send_button(area, camera, hit, true)
		_send_button(area, camera, hit, false)
		_expect(_presses == before, str(machine.name) + " rejects outside UV " + str(uv))
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	var before := _presses
	area.input_event.emit(camera, key, mesh.global_position, Vector3.FORWARD, 0)
	_expect(_presses == before, str(machine.name) + " ignores non-mouse input safely")
	holder.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _send_button(area: Area3D, camera: Camera3D, hit: Vector3, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = Vector2(137, 81)
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	area.input_event.emit(camera, event, hit, Vector3.FORWARD, 0)


func _check_crt_rendering() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1000, 650)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var background := ColorRect.new()
	background.size = Vector2(viewport.size)
	background.color = Color.BLACK
	viewport.add_child(background)
	var markers: Array[Rect2i] = [Rect2i(35, 23, 30, 14), Rect2i(485, 318, 30, 14), Rect2i(935, 608, 30, 14)]
	var colors := [Color.RED, Color.GREEN, Color.BLUE]
	for index in range(markers.size()):
		var rect := ColorRect.new()
		rect.position = Vector2(markers[index].position)
		rect.size = Vector2(markers[index].size)
		rect.color = colors[index]
		viewport.add_child(rect)
	var crt := CRT_SCENE.instantiate() as CanvasLayer
	crt.set_script(null)
	var screen := crt.get_node("Screen") as ColorRect
	var material := screen.material.duplicate() as ShaderMaterial
	screen.material = material
	for parameter in ["crt_curvature", "chroma_aberration", "glitch_intensity", "noise_intensity", "flicker_intensity", "phosphor_glow", "scanline_intensity", "vignette_strength"]:
		material.set_shader_parameter(parameter, 0.0)
	viewport.add_child(crt)
	# Sampling must follow both viewport heights without a controller script.
	for configuration: Vector2i in [Vector2i(650, 1), Vector2i(720, 1), Vector2i(720, 0)]:
		viewport.size.y = configuration.x
		background.size = Vector2(viewport.size)
		var enabled := configuration.y == 1
		material.set_shader_parameter("effect_enabled", 1.0 if enabled else 0.0)
		# A disabled effect must bypass spatial effects too; this catches the
		# old duplicate fragment block overwriting the pass-through result.
		material.set_shader_parameter("crt_curvature", 0.0 if enabled else 8.0)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		var mode := ("enabled" if enabled else "disabled") + "-" + str(viewport.size.y)
		_expect(image.save_png("res://screen-input-crt-%s.png" % mode) == OK, "CRT " + mode + " image saved")
		for index in range(markers.size()):
			var expected := markers[index]
			var center := expected.position + expected.size / 2
			var bounds := _marker_bounds(image, center, index)
			_expect(bounds == expected, "CRT %s marker %d stays at %s (got %s)" % [mode, index, expected, bounds])
	viewport.queue_free()
	await get_tree().process_frame


func _marker_bounds(image: Image, center: Vector2i, channel: int) -> Rect2i:
	var low := Vector2i(image.get_width(), image.get_height())
	var high := Vector2i(-1, -1)
	for x in range(image.get_width()):
		if _is_marker(image.get_pixel(x, center.y), channel):
			low.x = mini(low.x, x)
			high.x = x
	for y in range(image.get_height()):
		if _is_marker(image.get_pixel(center.x, y), channel):
			low.y = mini(low.y, y)
			high.y = y
	return Rect2i(low, high - low + Vector2i.ONE)


func _is_marker(color: Color, channel: int) -> bool:
	return color[channel] > 0.65 and color[(channel + 1) % 3] < 0.25 and color[(channel + 2) % 3] < 0.25
