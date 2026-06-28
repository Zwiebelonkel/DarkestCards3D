extends Node3D
class_name StreetLanternFlicker

# ========================================
# REFERENCES
# ========================================
@export_group("References")
@export var light: Light3D
@export var bulb_mesh: MeshInstance3D

# ========================================
# LIGHT SETTINGS
# ========================================
@export_group("Light")
@export var base_energy: float = 3.5
@export var min_energy: float = 0.05
@export var max_energy: float = 4.5

# ========================================
# FLICKER SETTINGS
# ========================================
@export_group("Flicker")
@export var flicker_enabled: bool = true
@export var time_between_flickers_min: float = 2.0
@export var time_between_flickers_max: float = 7.0
@export var flicker_duration_min: float = 0.25
@export var flicker_duration_max: float = 1.2
@export var flicker_step_min: float = 0.03
@export var flicker_step_max: float = 0.12
@export var chance_light_goes_out: float = 0.25

# ========================================
# EMISSION SETTINGS
# ========================================
@export_group("Bulb Emission")
@export var use_bulb_emission: bool = true
@export var emission_multiplier: float = 1.2

@export_group("Shootable")
@export var can_be_shot := true
@export var start_enabled := true
@export var destroy_on_first_shot := true
@export var shot_energy_drop_time := 0.08
@export var disable_flicker_when_shot := true
@export var broken_bulb_color := Color(0.03, 0.03, 0.03, 1.0)
@export var shot_sfx: AudioStreamPlayer3D
@export var sparks_particles: GPUParticles3D

# ========================================
# INTERNAL
# ========================================
var next_flicker_time: float = 0.0
var flicker_timer: float = 0.0
var flicker_step_timer: float = 0.0
var current_flicker_duration: float = 0.0
var is_flickering: bool = false

var target_energy: float = 0.0
var bulb_material: StandardMaterial3D

var is_shot_out := false
var original_light_energy := 1.0
var original_bulb_material: Material = null


func _ready() -> void:
	randomize()
	
	# Falls Light nicht im Inspector gesetzt ist:
	# Versuche den aktuellen Node "." als Light3D zu holen.
	if light == null:
		light = get_node_or_null(".") as Light3D
	
	if light == null:
		push_warning("StreetLanternFlicker: Kein Light3D zugewiesen.")
		return
	
	original_light_energy = base_energy
	
	light.light_energy = base_energy
	target_energy = base_energy
	
	setup_bulb_material()
	
	if bulb_mesh:
		original_bulb_material = bulb_mesh.material_override
	
	choose_next_flicker_time()
	
	if not start_enabled:
		shoot_out_light()

func _process(delta: float) -> void:
	if is_shot_out:
		if light:
			light.light_energy = 0.0
		return
	if not flicker_enabled:
		return
	
	if light == null:
		return
	
	if is_flickering:
		process_flicker(delta)
	else:
		process_idle(delta)
	
	update_bulb_emission()


func process_idle(delta: float) -> void:
	next_flicker_time -= delta
	
	light.light_energy = lerp(light.light_energy, base_energy, delta * 8.0)
	
	if next_flicker_time <= 0.0:
		start_flicker()


func start_flicker() -> void:
	is_flickering = true
	flicker_timer = 0.0
	flicker_step_timer = 0.0
	current_flicker_duration = randf_range(flicker_duration_min, flicker_duration_max)


func process_flicker(delta: float) -> void:
	flicker_timer += delta
	flicker_step_timer -= delta
	
	if flicker_step_timer <= 0.0:
		flicker_step_timer = randf_range(flicker_step_min, flicker_step_max)
		
		var goes_out: bool = randf() < chance_light_goes_out
		
		if goes_out:
			target_energy = min_energy
		else:
			target_energy = randf_range(min_energy, max_energy)
	
	light.light_energy = lerp(light.light_energy, target_energy, delta * 25.0)
	
	if flicker_timer >= current_flicker_duration:
		stop_flicker()


func stop_flicker() -> void:
	is_flickering = false
	target_energy = base_energy
	choose_next_flicker_time()


func choose_next_flicker_time() -> void:
	next_flicker_time = randf_range(time_between_flickers_min, time_between_flickers_max)


func setup_bulb_material() -> void:
	if not use_bulb_emission:
		return
	
	if bulb_mesh == null:
		return
	
	var mat: Material = bulb_mesh.get_active_material(0)
	
	if mat is StandardMaterial3D:
		bulb_material = mat.duplicate() as StandardMaterial3D
	else:
		bulb_material = StandardMaterial3D.new()
	
	bulb_material.emission_enabled = true
	bulb_material.emission = Color(1.0, 0.85, 0.55)
	bulb_material.emission_energy_multiplier = base_energy * emission_multiplier
	
	bulb_mesh.set_surface_override_material(0, bulb_material)


func update_bulb_emission() -> void:
	if not use_bulb_emission:
		return
	
	if bulb_material == null:
		return
	
	var normalized_energy: float = clamp(light.light_energy / max_energy, 0.0, 1.0)
	bulb_material.emission_energy_multiplier = normalized_energy * max_energy * emission_multiplier

func on_shot(damage: int, hit_position: Vector3, hit_normal: Vector3) -> void:
	if not can_be_shot:
		return
	
	if is_shot_out:
		return
	
	shoot_out_light()


func hit_by_gun(damage: int) -> void:
	if not can_be_shot:
		return
	
	if is_shot_out:
		return
	
	shoot_out_light()


func shoot_out_light() -> void:
	if is_shot_out:
		return
	
	is_shot_out = true
	
	# GANZ WICHTIG:
	# Alle Flicker-Werte sofort auf 0 setzen,
	# sonst setzt dein Flicker-Code das Licht evtl. wieder hoch.
	base_energy = 0.0
	target_energy = 0.0
	
	if light:
		light.light_energy = 0.0
		light.visible = true
	
	if shot_sfx:
		shot_sfx.play()
	
	if sparks_particles:
		sparks_particles.restart()
		sparks_particles.emitting = true
	
	make_bulb_dark()
	
	print("Light shot out sofort: ", name)

func make_bulb_dark() -> void:
	if bulb_mesh == null:
		return
	
	var mat := StandardMaterial3D.new()
	mat.albedo_color = broken_bulb_color
	mat.emission_enabled = false
	mat.roughness = 1.0
	
	bulb_mesh.material_override = mat


func reset_shootable_light() -> void:
	is_shot_out = false
	
	if light:
		light.light_energy = original_light_energy
	
	if bulb_mesh:
		bulb_mesh.material_override = original_bulb_material
