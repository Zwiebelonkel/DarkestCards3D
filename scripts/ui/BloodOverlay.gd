extends CanvasLayer
## A reusable, non-interactive blood border below the lens and pixel passes.

signal finished

@export_range(0.1, 20.0, 0.1) var duration := 9.0
@export_range(0.0, 3.0, 0.05) var hold_seconds := 0.9

@onready var blood_rect: ColorRect = $BloodRect

var active := false
var _material: ShaderMaterial
var _tween: Tween
var _random := RandomNumberGenerator.new()


func _ready() -> void:
	_material = blood_rect.material.duplicate() as ShaderMaterial
	blood_rect.material = _material
	_random.randomize()
	clear()


func play(seconds: float = -1.0) -> void:
	clear()
	active = true
	blood_rect.show()
	_material.set_shader_parameter("fade_progress", 0.0)
	_material.set_shader_parameter("pattern_seed", _random.randf_range(0.0, 100.0))
	var length := maxf(duration if seconds < 0.0 else seconds, 0.01)
	var hold := minf(hold_seconds, length * 0.25)
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_BOUND)
	_tween.tween_interval(hold)
	_tween.tween_property(_material, "shader_parameter/fade_progress", 1.0, length - hold)
	_tween.tween_callback(func() -> void:
		_tween = null
		active = false
		blood_rect.hide()
		finished.emit()
	)


func clear() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	active = false
	if _material != null:
		_material.set_shader_parameter("fade_progress", 1.0)
	if is_instance_valid(blood_rect):
		blood_rect.hide()


func _exit_tree() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
