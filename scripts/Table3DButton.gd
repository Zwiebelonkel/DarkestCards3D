extends Node3D
class_name Table3DButton

signal pressed

@export var label_text := "Button":
	set(value):
		label_text = value
		if is_node_ready():
			_refresh_localized_label()
@export var disabled := false
@export var hover_outline_material: Material
@export var press_sfx: AudioStreamPlayer3D


@export_group("Model Parts")
@export var glow_root: Node3D
@export var button_mesh: Node3D

@export_group("Hover Press")
@export var hover_press_distance := 0.08
@export var hover_anim_time := 0.08

var _default_overlays: Dictionary = {}
var _button_start_pos: Vector3
var _tween: Tween
var _label_base_pixel_size := 0.0
var _label_available_size := Vector2(1.45, 0.72)

@onready var label: Label3D = $Label3D
@onready var area: Area3D = $Area3D


func _ready() -> void:
	_label_base_pixel_size = label.pixel_size
	var collision := get_node_or_null("Area3D/CollisionShape3D") as CollisionShape3D
	if collision != null and collision.shape is BoxShape3D:
		var button_size := (collision.shape as BoxShape3D).size
		_label_available_size = Vector2(button_size.x * 0.88, button_size.z * 0.70)
	_refresh_localized_label()
	Localization.locale_changed.connect(_refresh_localized_label)

	area.input_event.connect(_on_input_event)
	area.mouse_entered.connect(_on_mouse_entered)
	area.mouse_exited.connect(_on_mouse_exited)

	if glow_root == null:
		glow_root = $model

	if button_mesh == null:
		button_mesh = $model/ButtonMesh # ggf. Pfad anpassen

	if button_mesh:
		_button_start_pos = button_mesh.position

	_cache_default_overlays(glow_root)
	_update_visual()


## Fit long translated captions to the existing physical button. Only the
## printed font size changes; hit targets and hover animation stay untouched.
func _refresh_localized_label() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or label == null:
		return
	label.text = Localization.text(label_text)
	var width := 0.0
	var lines := label.text.split("\n")
	for line: String in lines:
		width = maxf(width, label.font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x)
	var height := label.font.get_height(label.font_size) * float(lines.size())
	var footprint := Vector2(width * absf(label.scale.x), height * absf(label.scale.y)) * _label_base_pixel_size
	var fit := minf(1.0, minf(_label_available_size.x / maxf(footprint.x, 0.001), _label_available_size.y / maxf(footprint.y, 0.001)))
	label.pixel_size = _label_base_pixel_size * fit


func _cache_default_overlays(node: Node) -> void:
	if node is MeshInstance3D:
		_default_overlays[node] = node.material_overlay

	for child in node.get_children():
		_cache_default_overlays(child)


func set_disabled(value: bool) -> void:
	disabled = value
	_update_visual()


func _update_visual() -> void:
	label.modulate = Color(0.45, 0.45, 0.45, 1.0) if disabled else Color.WHITE


func _on_input_event(_camera, event, _pos, _normal, _shape_idx) -> void:
	if disabled or not is_visible_in_tree():
		return

	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
			_play_press_sfx()
			pressed.emit()


func _on_mouse_entered() -> void:
	if disabled or not is_visible_in_tree():
		return

	_set_hover_overlay(true)
	_move_button(true)


func _on_mouse_exited() -> void:
	_set_hover_overlay(false)
	_move_button(false)


func _set_hover_overlay(active: bool) -> void:
	for mesh in _default_overlays.keys():
		if is_instance_valid(mesh):
			mesh.material_overlay = hover_outline_material if active else _default_overlays[mesh]


func _move_button(down: bool) -> void:
	if button_mesh == null:
		return

	if _tween:
		_tween.kill()

	var target_pos := _button_start_pos
	if down:
		target_pos.y -= hover_press_distance

	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.tween_property(button_mesh, "position", target_pos, hover_anim_time)
	
func _play_press_sfx() -> void:
	if press_sfx == null:
		return
	
	if press_sfx.playing:
		press_sfx.stop()
	
	press_sfx.play()
