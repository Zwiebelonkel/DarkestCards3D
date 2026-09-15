extends Node3D
class_name StartingHandSlots

const FONT := preload("res://fonts/VCR_OSD_MONO_1.001.ttf")
const SLOT_SIZE := Vector2(0.50, 0.70)
const SLOT_SPACING := 0.65
const SLOT_Y := -0.65
const LOCKED_COLOR := Color("75636a")
const OPEN_COLOR := Color("d4b77b")
const FILLED_COLOR := Color("8aceb2")

var camera: Camera3D
var _frames: Array[MeshInstance3D] = []
var _locks: Array[Node3D] = []
var _slot_labels: Array[Label3D] = []
var _title: Label3D
var _hint: Label3D
var _unlocked_slots := 0
var _selected_indices: Array[int] = []


func setup(view_camera: Camera3D) -> void:
	camera = view_camera
	top_level = true
	global_transform = Transform3D(camera.global_basis, camera.global_transform * Vector3(0, 0, -2.8))
	_title = _label("Title", "", Vector3(0, -0.13, 0), 0.0027, 26, OPEN_COLOR)
	_hint = _label("Hint", "", Vector3(0, -1.20, 0), 0.0026, 24, Color("ddd5cd"))
	for index in range(5):
		var center := Vector3((index - 2) * SLOT_SPACING, SLOT_Y, 0)
		var frame := _panel("Slot%d" % (index + 1), center, SLOT_SIZE + Vector2(0.018, 0.018), LOCKED_COLOR)
		_frames.append(frame)
		_panel("Inset%d" % index, center + Vector3(0, 0, 0.002), SLOT_SIZE, Color("171319"))
		var lock := Node3D.new()
		lock.name = "Lock%d" % index
		lock.position = center + Vector3(0, 0.08, 0.005)
		add_child(lock)
		# A simple padlock built from geometry remains readable with the pixel font.
		_lock_bar(lock, Vector3(0, -0.035, 0), Vector2(0.13, 0.105))
		_lock_bar(lock, Vector3(-0.048, 0.055, 0), Vector2(0.024, 0.08))
		_lock_bar(lock, Vector3(0.048, 0.055, 0), Vector2(0.024, 0.08))
		_lock_bar(lock, Vector3(0, 0.10, 0), Vector2(0.12, 0.024))
		_locks.append(lock)
		_slot_labels.append(_label("State%d" % index, "", center + Vector3(0, -0.13, 0.006), 0.0024, 24, LOCKED_COLOR))
		_label("Order%d" % index, "%d" % (index + 1), center + Vector3(0, -0.40, 0), 0.0024, 24, OPEN_COLOR)
	refresh()


func refresh() -> void:
	var unlocked := CollectionManager.get_starting_hand_slot_count()
	var selected := DeckManager.get_starting_deck_indices()
	_unlocked_slots = unlocked
	_selected_indices = selected
	_title.text = "STARTKARTEN"
	_hint.text = "" if unlocked == 0 else ""
	for index in range(5):
		var locked := index >= unlocked
		var filled := index < selected.size() and selected[index] >= 0
		_set_frame_color(index, LOCKED_COLOR if locked else (FILLED_COLOR if filled else OPEN_COLOR))
		_locks[index].visible = locked
		_slot_labels[index].visible = not filled
		_slot_labels[index].text = Localization.format_text("GESPERRT\nSTUFE %d", [(index + 1)]) if locked else "KARTE\nHIERHER ZIEHEN"
		_slot_labels[index].modulate = Color("beaeb4") if locked else OPEN_COLOR


func card_position(index: int) -> Vector3:
	return global_transform * Vector3((index - 2) * SLOT_SPACING, SLOT_Y, 0.025)


func contains_pointer(pointer: Vector2) -> bool:
	var point: Variant = _pointer_on_plane(pointer)
	if point == null:
		return false
	return Rect2(Vector2(-1.65, -1.38), Vector2(3.3, 1.42)).has_point(Vector2(point.x, point.y))


func slot_at(pointer: Vector2) -> int:
	var point: Variant = _pointer_on_plane(pointer)
	if point == null:
		return -1
	for index in range(5):
		var center := Vector2((index - 2) * SLOT_SPACING, SLOT_Y)
		if Rect2(center - SLOT_SIZE * 0.5, SLOT_SIZE).has_point(Vector2(point.x, point.y)):
			return index
	return -1


func highlight_drop(pointer: Vector2, deck_index: int) -> void:
	# Pointer movement only updates frame colors; don't resolve the entire
	# owned-card inventory again on every rendered drag frame.
	for index in range(5):
		var filled := index < _selected_indices.size() and _selected_indices[index] >= 0
		_set_frame_color(index, LOCKED_COLOR if index >= _unlocked_slots else (FILLED_COLOR if filled else OPEN_COLOR))
	var target := slot_at(pointer)
	if target >= 0 and target < _unlocked_slots and deck_index >= 0:
		_set_frame_color(target, Color("efffb0"))


func _pointer_on_plane(pointer: Vector2) -> Variant:
	var plane := Plane(global_basis.z, global_position)
	var hit: Variant = plane.intersects_ray(camera.project_ray_origin(pointer), camera.project_ray_normal(pointer))
	return to_local(hit as Vector3) if hit != null else null


func _set_frame_color(index: int, color: Color) -> void:
	(_frames[index].material_override as StandardMaterial3D).albedo_color = color


func _panel(node_name: String, at: Vector3, size: Vector2, color: Color) -> MeshInstance3D:
	var panel := MeshInstance3D.new()
	panel.name = node_name
	var quad := QuadMesh.new()
	quad.size = size
	panel.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	panel.material_override = material
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	panel.position = at
	add_child(panel)
	return panel


func _lock_bar(parent: Node3D, at: Vector3, size: Vector2) -> void:
	var bar := _panel("Bar", Vector3.ZERO, size, LOCKED_COLOR)
	bar.reparent(parent, false)
	bar.position = at


func _label(node_name: String, text: String, at: Vector3, pixel_size: float, font_size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.name = node_name
	label.font = FONT
	label.text = text
	label.pixel_size = pixel_size
	label.font_size = font_size
	label.modulate = color
	label.outline_size = 4
	label.outline_modulate = Color("09090c")
	label.position = at
	add_child(label)
	return label
