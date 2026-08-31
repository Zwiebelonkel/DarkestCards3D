extends Node3D
class_name NeonTube

@export var neon_mesh: MeshInstance3D
@export var light: Light3D

@export_group("Brightness")
@export var base_emission_energy: float = 4.0
@export var base_light_energy: float = 2.0

@export_group("Flicker")
@export var flicker_enabled: bool = true
@export_range(0.0, 1.0) var flicker_strength: float = 0.08
@export var flicker_speed: float = 20.0

@export_group("Failures")
@export var random_failures: bool = true
@export var failure_chance_per_second: float = 0.04
@export var failure_min_duration: float = 0.03
@export var failure_max_duration: float = 0.16

@export_group("Startup")
@export var startup_flicker: bool = true
@export var startup_duration: float = 0.8

var _material: StandardMaterial3D
var _rng := RandomNumberGenerator.new()

var _is_enabled := true
var _failure_active := false
var _startup_active := false


func _ready() -> void:
	_rng.randomize()
	_prepare_existing_material()

	if light:
		base_light_energy = light.light_energy

	if startup_flicker:
		_play_startup()
	else:
		_set_brightness(1.0)


func _process(delta: float) -> void:
	if not _is_enabled:
		return

	if _startup_active or _failure_active:
		return

	if flicker_enabled:
		_update_flicker()

	if random_failures:
		if _rng.randf() < failure_chance_per_second * delta:
			_play_failure()


func _prepare_existing_material() -> void:
	if neon_mesh == null:
		push_warning("NeonTube: Kein neon_mesh zugewiesen.")
		return

	var source_material := neon_mesh.get_active_material(0)

	if source_material == null:
		push_warning("NeonTube: Das Mesh besitzt kein Material.")
		return

	if not source_material is StandardMaterial3D:
		push_warning(
			"NeonTube: Das importierte Material ist kein StandardMaterial3D."
		)
		return

	# Duplizieren, damit jede Röhre unabhängig flackert.
	_material = source_material.duplicate() as StandardMaterial3D
	neon_mesh.material_override = _material

	if not _material.emission_enabled:
		_material.emission_enabled = true

	# Der Wert aus Blender/Godot kann übernommen werden.
	if _material.emission_energy_multiplier > 0.0:
		base_emission_energy = _material.emission_energy_multiplier


func _update_flicker() -> void:
	var time := Time.get_ticks_msec() * 0.001

	var wave_a := sin(time * flicker_speed)
	var wave_b := sin(time * flicker_speed * 2.31)
	var noise := _rng.randf_range(-1.0, 1.0)

	var flicker_value := (
		wave_a * 0.45
		+ wave_b * 0.25
		+ noise * 0.30
	)

	var brightness := 1.0 + flicker_value * flicker_strength
	_set_brightness(max(brightness, 0.0))


func _set_brightness(multiplier: float) -> void:
	if _material:
		_material.emission_energy_multiplier = (
			base_emission_energy * multiplier
		)

	if light:
		light.light_energy = base_light_energy * multiplier


func _play_failure() -> void:
	if _failure_active:
		return

	_failure_active = true
	_set_brightness(0.0)

	var duration := _rng.randf_range(
		failure_min_duration,
		failure_max_duration
	)

	await get_tree().create_timer(duration).timeout

	if _is_enabled:
		_set_brightness(1.0)

	_failure_active = false


func _play_startup() -> void:
	if _startup_active:
		return

	_startup_active = true
	_is_enabled = true

	var elapsed := 0.0

	while elapsed < startup_duration:
		var on_duration := _rng.randf_range(0.03, 0.12)
		var off_duration := _rng.randf_range(0.02, 0.09)

		_set_brightness(_rng.randf_range(0.5, 1.1))
		await get_tree().create_timer(on_duration).timeout
		elapsed += on_duration

		_set_brightness(0.0)
		await get_tree().create_timer(off_duration).timeout
		elapsed += off_duration

	_set_brightness(1.0)
	_startup_active = false


func set_enabled(enabled: bool) -> void:
	_is_enabled = enabled

	if enabled:
		_set_brightness(1.0)
	else:
		_set_brightness(0.0)


func toggle() -> void:
	set_enabled(not _is_enabled)
