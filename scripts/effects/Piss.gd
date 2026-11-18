extends Node3D
signal emitting_changed(emitting: bool)
## Adapted from WaitingForHeavenStandalone's supplied Piss scene.
## World-space ballistic stream; the source project remains untouched.

@export var spray_seconds := 2.2
@export var flight_seconds := 0.95
@export var target_drop := 1.5
@export_range(0.0, 0.5, 0.01) var circle_radius := 0.12
@export_range(0.0, 3.0, 0.05) var circle_speed := 0.9

@onready var particles: GPUParticles3D = $PissParticles
@onready var piss_sfx: AudioStreamPlayer = $PissSFX

var active := false
var source_position := Vector3.ZERO
var target_position := Vector3.ZERO
var launch_velocity := Vector3.ZERO
var gravity := Vector3(0, -9.8, 0)
var _camera: Camera3D
var _actor: Sprite3D
var _table_surface: MeshInstance3D
var _available: Callable
var _material: ParticleProcessMaterial
var _elapsed := 0.0
var _drain_remaining := 0.0
var _random := RandomNumberGenerator.new()
var _spraying := false
var _aim_at_table := false


func _ready() -> void:
	_material = particles.process_material.duplicate() as ParticleProcessMaterial
	particles.process_material = _material
	particles.local_coords = false
	# The authored Piss node follows Satan; existing droplets stay in world space.
	particles.top_level = true
	_random.randomize()
	stop_pissing(true)


func configure(camera: Camera3D, actor: Sprite3D, table_surface: MeshInstance3D, available: Callable) -> void:
	_aim_at_table = false
	_camera = camera
	_actor = actor
	_table_surface = table_surface
	_available = available


func configure_table_event(table_surface: MeshInstance3D, available: Callable) -> void:
	_aim_at_table = true
	_table_surface = table_surface
	_available = available
	flight_seconds = 0.65
	circle_radius = 0.45


func start_pissing() -> void:
	if active or not _context_is_safe():
		return
	active = true
	_elapsed = 0.0
	_drain_remaining = 0.0
	_update_trajectory()
	particles.show()
	particles.restart()
	particles.emitting = true
	_set_spraying(true)
	piss_sfx.pitch_scale = _random.randf_range(0.92, 1.08)
	piss_sfx.play()


func stop_pissing(immediate: bool = false) -> void:
	particles.emitting = false
	_set_spraying(false)
	piss_sfx.stop()
	if immediate:
		active = false
		_drain_remaining = 0.0
		particles.hide()
		particles.restart()
		particles.emitting = false
	else:
		_drain_remaining = particles.lifetime + particles.trail_lifetime


func _set_spraying(value: bool) -> void:
	if _spraying == value:
		return
	_spraying = value
	emitting_changed.emit(value)


func _context_is_safe() -> bool:
	return ((_aim_at_table or (is_instance_valid(_camera) and is_instance_valid(_actor)))
		and is_instance_valid(_table_surface) and _available.is_valid() and _available.call())


func _process(delta: float) -> void:
	if not active:
		return
	if not _context_is_safe():
		stop_pissing(true)
		return
	if particles.emitting:
		_update_trajectory()
		_elapsed += delta
		if _elapsed >= spray_seconds:
			stop_pissing()
	else:
		_drain_remaining -= delta
		if _drain_remaining <= 0.0:
			stop_pissing(true)


func _update_trajectory() -> void:
	# This is the real, editable child node in GameTable.tscn. Never replace its pose.
	source_position = global_position
	# Gently circle the aim; keep the editable source fixed and let already
	# emitted droplets continue on their own world-space trajectories.
	var phase := _elapsed * TAU * circle_speed
	if _aim_at_table:
		var surface := _table_surface.get_aabb()
		target_position = _table_surface.to_global(Vector3(surface.get_center().x, surface.end.y, surface.get_center().z))
		target_position += Vector3(cos(phase), 0.0, sin(phase)) * circle_radius
	else:
		var forward := -_camera.global_basis.z
		forward.y = 0.0
		forward = forward.normalized()
		target_position = _camera.global_position - Vector3.UP * target_drop + forward * 0.2
		var right := forward.cross(Vector3.UP)
		target_position += (right * cos(phase) + Vector3.UP * sin(phase)) * circle_radius
	var travel_time := maxf(flight_seconds, 0.1)
	launch_velocity = (target_position - source_position - gravity * 0.5 * travel_time * travel_time) / travel_time
	particles.global_transform = Transform3D(Basis.IDENTITY, source_position)
	_material.gravity = gravity
	_material.direction = launch_velocity.normalized()
	_material.initial_velocity_min = launch_velocity.length()
	_material.initial_velocity_max = launch_velocity.length()
	particles.lifetime = travel_time
	var bounds := AABB(Vector3.ZERO, Vector3.ZERO)
	for index in range(21):
		bounds = bounds.expand(trajectory_position(float(index) / 20.0 * travel_time) - source_position)
	particles.visibility_aabb = bounds.grow(0.5)


func trajectory_position(seconds: float) -> Vector3:
	return source_position + launch_velocity * seconds + gravity * 0.5 * seconds * seconds
