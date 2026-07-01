extends Node3D
class_name Table3DButton

signal pressed

@export var label_text := "Button"
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

@onready var label: Label3D = $Label3D
@onready var area: Area3D = $Area3D


func _ready() -> void:
	label.text = label_text

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
	if disabled:
		return

	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
			_play_press_sfx()
			pressed.emit()


func _on_mouse_entered() -> void:
	if disabled:
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
