extends Node3D
class_name DamageNumber3D

## A transient number at the point of impact, independent of the struck card.
## Pure presentation: no gameplay RNG, card ownership or combat state changes.
signal finished

const FONT := preload("res://fonts/VCR_OSD_MONO_1.001.ttf")
const LIFETIME := 1.05
const FADE_START := 0.72
const BLINK_INTERVAL := 0.115
const POP_PEAK_TIME := 0.07
const POP_SETTLE_TIME := 0.20
const PIXEL_SIZE := 0.0048
const DAMAGE_COLOR := Color("ff5750")
const FLASH_COLOR := Color("fff4ce")
const BLOCK_COLOR := Color("a8d6e7")
const HEALING_COLOR := Color("39ff70")

var damage_amount := 0
var amount := 0
var is_healing := false
var label: Label3D
var _elapsed := 0.0
var _origin := Vector3.ZERO
var _rise := Vector3.UP
var _drift := Vector3.ZERO
var _unit_scale := 1.0


func _ready() -> void:
	# Remain in the 3D render, beneath the game's existing CanvasLayer filters.
	# A dying card may fly away or be freed while its number finishes rising.
	top_level = true
	label = Label3D.new()
	label.name = "Damage"
	label.font = FONT
	label.font_size = 64
	label.pixel_size = PIXEL_SIZE
	label.outline_size = 10
	label.outline_modulate = Color("180d13")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.shaded = false
	label.no_depth_test = true
	label.render_priority = 20
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(label)
	set_process(false)


func show_damage(value: int, origin: Vector3, camera: Camera3D, lane: int = 0, unit_scale: float = 1.0) -> void:
	is_healing = false
	damage_amount = maxi(value, 0)
	amount = damage_amount
	label.name = "Damage"
	var text := "-%d" % damage_amount if damage_amount > 0 else "0"
	_show_number(text, origin, camera, lane, unit_scale)


func show_healing(value: int, origin: Vector3, camera: Camera3D, lane: int = 0, unit_scale: float = 1.0) -> void:
	is_healing = true
	damage_amount = 0
	amount = maxi(value, 0)
	label.name = "Healing"
	_show_number("+%d" % amount, origin, camera, lane, unit_scale)


func _show_number(text: String, origin: Vector3, camera: Camera3D, lane: int, unit_scale: float) -> void:
	_unit_scale = maxf(unit_scale, 0.001)
	_elapsed = 0.0
	label.text = text
	# Even unusually large upgraded hits keep their complete numeric value.
	var text_width := FONT.get_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, -1, label.font_size).x
	label.pixel_size = minf(PIXEL_SIZE, 0.90 / maxf(text_width + label.outline_size * 2.0, 1.0))
	var up := Vector3.UP
	var right := Vector3.RIGHT
	var toward_viewer := Vector3.BACK
	if is_instance_valid(camera):
		up = camera.global_basis.y.normalized()
		right = camera.global_basis.x.normalized()
		toward_viewer = camera.global_basis.z.normalized()
	# Deterministic lanes separate simultaneous hit/reflection/counter numbers.
	var side := -1.0 if posmod(lane, 2) == 0 else 1.0
	var row := float(posmod(lane, 8) / 2)
	_origin = origin + (up * (0.18 + row * 0.54) + right * side * 0.36 + toward_viewer * 0.12) * _unit_scale
	_rise = up * 0.65 * _unit_scale
	_drift = right * side * 0.10 * _unit_scale
	_animate(0.0)
	show()
	set_process(true)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= LIFETIME:
		set_process(false)
		hide()
		finished.emit()
		queue_free()
		return
	_animate(_elapsed)


func _animate(elapsed: float) -> void:
	var progress := clampf(elapsed / LIFETIME, 0.0, 1.0)
	global_position = _origin + _rise * progress + _drift * progress
	var pop := 1.0
	if elapsed < POP_PEAK_TIME:
		pop = lerpf(0.38, 1.28, 1.0 - pow(1.0 - elapsed / POP_PEAK_TIME, 3.0))
	elif elapsed < POP_SETTLE_TIME:
		pop = lerpf(1.28, 1.0, (elapsed - POP_PEAK_TIME) / (POP_SETTLE_TIME - POP_PEAK_TIME))
	global_basis = Basis.from_scale(Vector3.ONE * _unit_scale * pop)
	var bright := elapsed < FADE_START and floori(elapsed / BLINK_INTERVAL) % 2 == 0
	var color := FLASH_COLOR if bright else (DAMAGE_COLOR if damage_amount > 0 else BLOCK_COLOR)
	if is_healing:
		color = Color.WHITE if bright else HEALING_COLOR
	var fade := 1.0 - clampf((elapsed - FADE_START) / (LIFETIME - FADE_START), 0.0, 1.0)
	color.a = fade * (1.0 if bright or elapsed >= FADE_START else 0.72)
	label.modulate = color
	label.outline_modulate = Color(0.09, 0.035, 0.05, fade)
