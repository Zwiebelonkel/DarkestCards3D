extends Node3D
## Card-local presentation of event_block_turns. Never owns or ticks the block.

const ENTRY_DURATION := 0.28
const SETTLE_DURATION := 0.16
const EXIT_DURATION := 0.28
const ENTRY_OFFSET := Vector3(0.32, -0.25, 1.80)
const EXIT_OFFSET := Vector3(0.24, -0.20, 1.35)
const SOURCE_TIP := Vector3(-0.067996, -0.000402, -2.664965)
enum Phase { INACTIVE, ENTERING, PINNED, LEAVING }

@onready var motion: Node3D = $PinMotion
var phase := Phase.INACTIVE
var _active := false
var _elapsed := 0.0
var _meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		_meshes.append(node as MeshInstance3D)
	reset()


func reset() -> void:
	_active = false
	phase = Phase.INACTIVE
	_elapsed = 0.0
	motion.transform = Transform3D.IDENTITY
	_set_transparency(0.0)
	hide()
	set_process(false)


func match_decoration(reference: Node3D) -> void:
	if not is_instance_valid(reference):
		return
	var model := $PinMotion/Orientation/Model as Node3D
	# The decoration also inherits its 1.405 group scale. Match its actual
	# world size rather than copying only the knife node's 0.215 local scale.
	var parent_scale := model.get_parent_node_3d().global_basis.get_scale().abs().x
	var model_scale := reference.global_basis.get_scale().abs().x / maxf(parent_scale, 0.001)
	model.scale = Vector3.ONE * model_scale
	model.position = -SOURCE_TIP * model_scale


func sync(turns: int, concealed: bool, animate: bool = true) -> void:
	var active := turns > 0
	var was_active := _active
	_active = active
	if active:
		if not was_active or phase == Phase.LEAVING:
			_elapsed = 0.0
			_set_transparency(0.0)
			phase = Phase.ENTERING if animate and not concealed else Phase.PINNED
			if phase == Phase.ENTERING:
				_apply_entry(0.0)
			else:
				motion.transform = Transform3D.IDENTITY
			set_process(phase == Phase.ENTERING)
		visible = not concealed
	elif was_active:
		if animate and visible and not concealed:
			phase = Phase.LEAVING
			_elapsed = 0.0
			motion.transform = Transform3D.IDENTITY
			set_process(true)
		else:
			reset()
	elif not animate:
		reset()
	if concealed:
		hide()


func _process(delta: float) -> void:
	_elapsed += delta
	if phase == Phase.ENTERING:
		_apply_entry(_elapsed)
		if _elapsed >= ENTRY_DURATION + SETTLE_DURATION:
			phase = Phase.PINNED
			motion.transform = Transform3D.IDENTITY
			set_process(false)
	elif phase == Phase.LEAVING:
		_apply_exit(_elapsed)
		if _elapsed >= EXIT_DURATION:
			reset()


func _apply_entry(elapsed: float) -> void:
	if elapsed < ENTRY_DURATION:
		var t := clampf(elapsed / ENTRY_DURATION, 0.0, 1.0)
		motion.position = ENTRY_OFFSET * (1.0 - t * t * t)
		motion.rotation = Vector3(0.0, 0.0, (1.0 - t) * 0.12)
	else:
		var t := clampf((elapsed - ENTRY_DURATION) / SETTLE_DURATION, 0.0, 1.0)
		motion.position = Vector3.ZERO
		motion.rotation = Vector3(sin(t * TAU * 2.0) * (1.0 - t) * 0.045, 0.0, 0.0)


func _apply_exit(elapsed: float) -> void:
	var t := clampf(elapsed / EXIT_DURATION, 0.0, 1.0)
	motion.position = EXIT_OFFSET * t * t
	motion.rotation = Vector3(0.0, t * 0.18, t * 0.12)
	_set_transparency(t)


func _set_transparency(value: float) -> void:
	for mesh in _meshes:
		mesh.transparency = value
