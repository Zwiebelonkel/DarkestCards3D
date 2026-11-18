extends Node3D
## Two clipped number drums. A shared material uses per-instance roll positions.

const MAX_PRESSURE := 6.0
const REST_EPSILON := 0.0001

var text := "2.8"
var _pressure := 2.8
var _target_steps := 28.0
var _roll_steps := 28.0

@onready var units: MeshInstance3D = $Units
@onready var tenths: MeshInstance3D = $Tenths


func _ready() -> void:
	# Finish the short mechanical movement even if the pause menu just opened.
	process_mode = Node.PROCESS_MODE_ALWAYS
	visibility_changed.connect(_on_visibility_changed)
	_apply_roll()
	set_process(false)


func set_pressure(value: float, immediate: bool = false) -> void:
	_pressure = clampf(value, 0.0, MAX_PRESSURE)
	text = "%.1f" % _pressure
	_target_steps = _pressure * 10.0
	if not is_node_ready():
		_roll_steps = _target_steps
		return
	if immediate or not is_visible_in_tree():
		_roll_steps = _target_steps
		_apply_roll()
		set_process(false)
	else:
		set_process(absf(_target_steps - _roll_steps) > REST_EPSILON)


func _process(delta: float) -> void:
	# Track fast valve turns promptly, then seat the last digit without overshoot.
	var speed := maxf(5.5, absf(_target_steps - _roll_steps) * 20.0)
	_roll_steps = move_toward(_roll_steps, _target_steps, speed * delta)
	if absf(_target_steps - _roll_steps) <= REST_EPSILON:
		_roll_steps = _target_steps
		set_process(false)
	_apply_roll()


func get_roll_positions() -> Vector2:
	var whole := floorf(_roll_steps / 10.0)
	var last := fposmod(_roll_steps, 10.0)
	# The left drum is engaged only while the right drum crosses from 9 to 0.
	return Vector2(whole + clampf(last - 9.0, 0.0, 1.0), last)


func is_rolling() -> bool:
	return absf(_target_steps - _roll_steps) > REST_EPSILON


func _apply_roll() -> void:
	var positions := get_roll_positions()
	units.set_instance_shader_parameter("roll_steps", positions.x)
	tenths.set_instance_shader_parameter("roll_steps", positions.y)


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		set_pressure(_pressure, true)
