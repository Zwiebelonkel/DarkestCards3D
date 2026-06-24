extends Node3D
class_name MainScene

const SIDE_COUNT := 4
const SIDE_NAMES := [
	"Game Table",
	"Pack Opening",
	"Collection",
	"Leere Seite",
]
const SIDE_HINTS := [
	"Tisch-Seite: Kartenkampf spielen",
	"Pack-Seite: PackTop ziehen und Karten öffnen",
	"Collection-Seite: Sammlung ansehen",
	"Diese Seite bleibt frei",
]

@export var rotation_step_degrees := 90.0
@export var rotation_duration := 0.45
@export var keyboard_turn_cooldown := 0.12

@onready var scene_pivot: Node3D = $ScenePivot
@onready var camera_pivot: Node3D = $CameraPivot
@onready var side_label: Label = %SideLabel
@onready var hint_label: Label = %HintLabel

var _active_side := 0
var _is_turning := false
var _turn_cooldown_left := 0.0


func _ready() -> void:
	_disable_embedded_scene_controls()
	_update_labels()


func _process(delta: float) -> void:
	_turn_cooldown_left = maxf(_turn_cooldown_left - delta, 0.0)

	if _is_turning or _turn_cooldown_left > 0.0:
		return

	if Input.is_key_pressed(KEY_A):
		_turn_to_side(-1)
	elif Input.is_key_pressed(KEY_D):
		_turn_to_side(1)


func _turn_to_side(direction: int) -> void:
	_is_turning = true
	_turn_cooldown_left = keyboard_turn_cooldown
	_active_side = posmod(_active_side + direction, SIDE_COUNT)
	_update_labels()

	var target_rotation := Vector3(0.0, deg_to_rad(rotation_step_degrees * float(_active_side)), 0.0)
	var tween := create_tween()
	tween.tween_property(camera_pivot, "rotation", target_rotation, rotation_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	_is_turning = false


func _update_labels() -> void:
	side_label.text = SIDE_NAMES[_active_side]
	hint_label.text = SIDE_HINTS[_active_side] + "  |  A/D drehen"


func _disable_embedded_scene_controls() -> void:
	for child in scene_pivot.get_children():
		_disable_embedded_scene_controls_recursive(child)


func _disable_embedded_scene_controls_recursive(node: Node) -> void:
	if node is Camera3D:
		(node as Camera3D).current = false
	if node is AudioListener3D:
		(node as AudioListener3D).current = false
	if node is WorldEnvironment:
		(node as WorldEnvironment).environment = null
	if node is MenuNavigation:
		(node as MenuNavigation).visible = false
		(node as MenuNavigation).process_mode = Node.PROCESS_MODE_DISABLED

	for child in node.get_children():
		_disable_embedded_scene_controls_recursive(child)
