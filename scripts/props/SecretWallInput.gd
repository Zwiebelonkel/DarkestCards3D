extends Node3D

const REVEAL := preload("res://scripts/ui/SecretCardReveal.gd")
const PANEL_SIZE := Vector2(2.8, 1.05)
const PIXELS := Vector2i(840, 315)
const VIEW_SIDE := 2

var camera: Camera3D
var focus_controller: ScreenCameraFocus
@onready var focus_area: Area3D = $InputArea
@onready var viewport: SubViewport = $TextViewport
@onready var entry: LineEdit = $TextViewport/Panel/Content/Command/SecretText
@onready var status: Label = $TextViewport/Panel/Content/Status
var _enabled := false
var _reveal_card: Card3D
var _last_pointer := Vector2.ZERO
var _inside := false


func _ready() -> void:
	# Bind to this instance's viewport when nested inside the room scene.
	var screen := $Screen as MeshInstance3D
	var material := screen.material_override.duplicate() as StandardMaterial3D
	material.albedo_texture = viewport.get_texture()
	screen.material_override = material
	focus_area.set_meta("focus_camera_marker", $FocusCamera)
	focus_area.set_meta("focus_fov", 49.0)
	entry.text_submitted.connect(_submit)
	Localization.locale_changed.connect(_refresh_text)
	_refresh_text()


func _refresh_text() -> void:
	entry.placeholder_text = Localization.text("Text eingeben …")
	status.text = Localization.text("Mit Enter bestätigen")


func is_busy() -> bool:
	return is_instance_valid(_reveal_card) or (_enabled and entry.has_focus())


func set_interaction_enabled(enabled: bool) -> void:
	_enabled = enabled
	entry.editable = enabled and not is_instance_valid(_reveal_card)
	if not enabled:
		entry.release_focus()
		if _inside:
			_inside = false
			viewport.notify_mouse_exited()
		# A context change must not leave a floating reveal in another room.
		if is_instance_valid(_reveal_card):
			_reveal_card.queue_free()
			_reveal_card = null


func handle_key(event: InputEvent) -> bool:
	if not _enabled or get_tree().paused or not event is InputEventKey:
		return false
	if is_instance_valid(_reveal_card):
		return true
	if not entry.has_focus():
		return false
	if event.is_action_pressed("ui_cancel"):
		entry.release_focus()
	else:
		viewport.push_input(event, true)
	return true


func _submit(text: String) -> void:
	if not _enabled or get_tree().paused or is_instance_valid(_reveal_card) or not is_instance_valid(camera):
		return
	var instance := CollectionManager.redeem_wall_secret(text)
	if instance.is_empty():
		if text.strip_edges().to_lower() == "dman" and CollectionManager.has_discovered_card("dman"):
			status.text = Localization.text("Bereits entdeckt.")
		else:
			status.text = Localization.text("Keine Antwort.")
		return
	entry.clear()
	entry.release_focus()
	status.text = "DMAN"
	_reveal_card = REVEAL.play(self, instance, camera, global_position)
	entry.editable = false


func panel_to_screen(pixel: Vector2) -> Vector2:
	var local := Vector3((pixel.x / PIXELS.x - 0.5) * PANEL_SIZE.x, (0.5 - pixel.y / PIXELS.y) * PANEL_SIZE.y, 0)
	return camera.unproject_position(to_global(local))


func _input(event: InputEvent) -> void:
	if not _enabled or not is_visible_in_tree() or get_tree().paused or not is_instance_valid(camera):
		return
	if not event is InputEventMouse or is_instance_valid(_reveal_card):
		return
	var ray := camera.project_ray_normal(event.position)
	if ray.dot(global_basis.z) >= 0.0:
		return
	var hit: Variant = Plane(global_basis.z.normalized(), global_position).intersects_ray(camera.project_ray_origin(event.position), ray)
	if hit == null:
		return
	var local := to_local(hit)
	var point := Vector2((0.5 + local.x / PANEL_SIZE.x) * PIXELS.x, (0.5 - local.y / PANEL_SIZE.y) * PIXELS.y)
	var inside := Rect2(Vector2.ZERO, Vector2(PIXELS)).has_point(point)
	if inside != _inside:
		_inside = inside
		if inside:
			viewport.notify_mouse_entered()
		else:
			viewport.notify_mouse_exited()
	if not inside:
		if event is InputEventMouseButton and event.pressed:
			entry.release_focus()
		return
	var forwarded := event.duplicate() as InputEventMouse
	forwarded.position = point
	forwarded.global_position = point
	if forwarded is InputEventMouseMotion:
		forwarded.relative = point - _last_pointer
	_last_pointer = point
	viewport.push_input(forwarded, true)
	get_viewport().set_input_as_handled()
