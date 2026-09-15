extends Node3D
class_name RewardRevealEffect

signal started(tier: int, payout_cents: int)

const REVEAL_SHADER := preload("res://assets/shader/rarity_vignette_glow.gdshader")
const FONT := preload("res://fonts/VCR_OSD_MONO_1.001.ttf")
const REVEAL_TIERS: Array[String] = ["uncommon", "rare", "epic", "legendary", "mythic"]

var active := false
var _layer: CanvasLayer
var _flash: ColorRect
var _flash_material: ShaderMaterial
var _popup: PanelContainer
var _icon: TextureRect
var _heading: Label
var _amount: Label
var _detail: Label
var _light: OmniLight3D
var _particles: GPUParticles3D
var _tween: Tween
var _visibility_check: Callable
var _duration := 1.8
var _peak_glow := 0.0
var _peak_light := 0.0
var _ui_scale := 1.0
var _payout_cents := 0


func _ready() -> void:
	Localization.locale_changed.connect(_refresh_localized_amount)
	# Keep the visibility guard responsive when a pause menu stops the game.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 45
	add_child(_layer)
	_flash = ColorRect.new()
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_material = ShaderMaterial.new()
	_flash_material.shader = REVEAL_SHADER
	_flash_material.set_shader_parameter("glow_strength", 0.0)
	_flash_material.set_shader_parameter("vignette_strength", 0.8)
	_flash_material.set_shader_parameter("pulse_amount", 0.08)
	_flash_material.set_shader_parameter("flicker_strength", 0.0)
	_flash_material.set_shader_parameter("aberration_strength", 0.0)
	_flash_material.set_shader_parameter("distortion_strength", 0.0)
	_flash.material = _flash_material
	_layer.add_child(_flash)
	_build_popup()
	_light = OmniLight3D.new()
	_light.omni_range = 1.8
	_light.light_energy = 0.0
	_light.light_specular = 0.0
	add_child(_light)
	cancel()


func play_reward(tier: int, payout_cents: int, tint: Color, symbol: Texture2D, symbol_name: String, multiplier: int, visibility_check: Callable) -> bool:
	if payout_cents <= 0 or not visibility_check.is_valid() or not visibility_check.call():
		return false
	cancel()
	_visibility_check = visibility_check
	var rank := clampi(tier, 0, REVEAL_TIERS.size() - 1)
	var data := RarityEffectsData.get_data(REVEAL_TIERS[rank])
	_duration = 1.65 + rank * 0.14
	_peak_glow = clampf(float(data.screen_flash_strength) * 1.6, 0.24, 1.45)
	_peak_light = 0.65 + rank * 0.25
	_flash_material.set_shader_parameter("rarity_color", tint)
	_light.light_color = tint
	_icon.texture = symbol
	_icon.modulate = tint
	_heading.text = "MEGA-GEWINN!" if rank == 4 else ("GROSSER GEWINN!" if rank >= 2 else "GEWINN!")
	_heading.add_theme_color_override("font_color", tint)
	_payout_cents = payout_cents
	_refresh_localized_amount()
	_detail.text = Localization.format_text("%s × 3  ·  %d× EINSATZ", [Localization.localized_arg(symbol_name), multiplier])
	var style := _popup.get_theme_stylebox("panel") as StyleBoxFlat
	style.border_color = tint
	style.shadow_color = Color(tint, 0.24)
	_place_popup()
	_spawn_particles(data, tint)
	active = true
	_layer.show()
	set_process(true)
	_animate(0.0)
	_tween = create_tween()
	_tween.tween_method(_animate, 0.0, _duration, _duration)
	_tween.tween_callback(cancel)
	started.emit(rank, payout_cents)
	return true


func _process(_delta: float) -> void:
	if active and (not _visibility_check.is_valid() or not _visibility_check.call()):
		cancel()


func _refresh_localized_amount() -> void:
	if is_instance_valid(_amount):
		_amount.text = Localization.format_text("+%s SC", [Localization.decimal(float(_payout_cents) / 100.0)])


func cancel() -> void:
	active = false
	if _tween != null:
		_tween.kill()
		_tween = null
	if _layer != null:
		_layer.hide()
	if _flash_material != null:
		_flash_material.set_shader_parameter("glow_strength", 0.0)
	if _light != null:
		_light.light_energy = 0.0
	if is_instance_valid(_particles):
		_particles.emitting = false
		_particles.hide()
		_particles.queue_free()
		_particles = null
	set_process(false)


func _animate(elapsed: float) -> void:
	var glow := clampf(elapsed / 0.08, 0.0, 1.0) * clampf((1.05 - elapsed) / 0.85, 0.0, 1.0)
	_flash_material.set_shader_parameter("glow_strength", _peak_glow * glow)
	_light.light_energy = _peak_light * glow
	_popup.modulate.a = clampf(elapsed / 0.12, 0.0, 1.0) * clampf((_duration - elapsed) / 0.32, 0.0, 1.0)
	var pop := float(Tween.interpolate_value(0.82, 0.18, minf(elapsed, 0.3), 0.3, Tween.TRANS_BACK, Tween.EASE_OUT))
	_popup.scale = Vector2.ONE * _ui_scale * pop


func _build_popup() -> void:
	_popup = PanelContainer.new()
	_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup.custom_minimum_size = Vector2(420, 146)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("101712", 0.96)
	style.set_border_width_all(2)
	style.set_corner_radius_all(7)
	style.shadow_size = 14
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	_popup.add_theme_stylebox_override("panel", style)
	_layer.add_child(_popup)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	_popup.add_child(column)
	_heading = _label(21)
	column.add_child(_heading)
	var reward_row := HBoxContainer.new()
	reward_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reward_row.alignment = BoxContainer.ALIGNMENT_CENTER
	reward_row.add_theme_constant_override("separation", 14)
	column.add_child(reward_row)
	_icon = TextureRect.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.custom_minimum_size = Vector2(46, 46)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	reward_row.add_child(_icon)
	_amount = _label(43)
	reward_row.add_child(_amount)
	_detail = _label(17)
	_detail.add_theme_color_override("font_color", Color("d8d9cf"))
	column.add_child(_detail)


func _label(font_size: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("fff7de"))
	return label


func _place_popup() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var camera := get_viewport().get_camera_3d()
	var target := camera.unproject_position(global_position)
	_ui_scale = clampf(viewport_size.y / 720.0, 0.65, 1.6)
	_popup.size = _popup.get_combined_minimum_size()
	_popup.pivot_offset = _popup.size * 0.5
	# The announcement sits above the reel center and leaves the buttons free.
	var center := target - Vector2(0, 130) * _ui_scale
	var half_size := _popup.size * _ui_scale * 0.5
	center = center.clamp(half_size + Vector2(18, 30), viewport_size - half_size - Vector2(18, 30))
	_popup.position = center - _popup.size * 0.5


func _spawn_particles(data: Dictionary, tint: Color) -> void:
	_particles = GPUParticles3D.new()
	_particles.name = "RewardParticles"
	_particles.one_shot = true
	_particles.explosiveness = 0.9
	_particles.amount = maxi(int(data.particle_amount * 0.55), 16)
	_particles.lifetime = 1.3
	_particles.local_coords = true
	_particles.visibility_aabb = AABB(Vector3(-2, -1, -1), Vector3(4, 4, 3))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.48, 0.03, 0.03)
	process.direction = Vector3(0, 1, 0.25)
	process.spread = 50.0
	process.gravity = Vector3(0, -1.8, 0)
	process.initial_velocity_min = float(data.particle_speed) * 0.6
	process.initial_velocity_max = float(data.particle_speed)
	process.damping_min = 0.2
	process.damping_max = 0.6
	process.scale_min = 0.025
	process.scale_max = 0.065
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(tint, 0.0), tint, Color(tint, 0.0)])
	gradient.offsets = PackedFloat32Array([0.0, 0.08, 1.0])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	_particles.process_material = process
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = minf(float(data.particle_glow_energy) * 0.45, 5.0)
	mesh.material = material
	_particles.draw_pass_1 = mesh
	add_child(_particles)
	_particles.emitting = true


func _exit_tree() -> void:
	cancel()
