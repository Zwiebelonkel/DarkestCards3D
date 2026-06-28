extends CanvasLayer

## Simple CRT / VHS / Glitch Post-FX for Godot 4.4.
## Put this script on a CanvasLayer and let it auto-create a fullscreen ColorRect named "Screen".
## No SubViewport needed. The shader uses hint_screen_texture.

enum PresetType {
	PUPPETCOMBO,
	VHS_TAPE,
	CLEAN_CRT,
	NIGHTMARE,
}

@export_group("Setup")
@export var auto_create_screen := true
@export var screen_node_path: NodePath = NodePath("Screen")
@export var shader_path := "res://fx/crt_postfx.gdshader"
@export var force_layer_127 := true
@export var ignore_mouse := true
@export var update_viewport_size_each_frame := true

@export_group("Preset")
@export var apply_preset: PresetType = PresetType.PUPPETCOMBO:
	set(value):
		apply_preset = value
		if is_inside_tree():
			_apply_preset_values(value)

@export_group("Master")
@export var effect_enabled := true

@export_group("CRT Curve")
@export_range(0.0, 10.0, 0.01) var crt_curvature := 3.5

@export_group("Scanlines")
@export_range(0.0, 1.0, 0.01) var scanline_intensity := 0.55
@export_range(60.0, 720.0, 1.0) var scanline_count := 240.0
@export_range(-2.0, 2.0, 0.01) var scanline_scroll_speed := 0.12

@export_group("Chroma")
@export_range(0.0, 0.04, 0.0005) var chroma_aberration := 0.004

@export_group("Glitch")
@export_range(0.0, 1.0, 0.01) var glitch_intensity := 0.25
@export_range(0.1, 30.0, 0.1) var glitch_speed := 6.0
@export_range(1.0, 80.0, 1.0) var glitch_block_size := 18.0

@export_group("Atmosphere")
@export_range(0.0, 0.4, 0.005) var noise_intensity := 0.07
@export_range(0.0, 0.3, 0.005) var flicker_intensity := 0.04
@export_range(0.0, 1.5, 0.01) var phosphor_glow := 0.35
@export_range(0.0, 3.0, 0.01) var vignette_strength := 1.1
@export var tint_color := Color(0.949, 1.0, 0.855, 1.0)

var screen_rect: Control = null
var shader_material: ShaderMaterial = null
var _burst_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 4095
	
	if not is_in_group("crt_fx"):
		add_to_group("crt_fx")
	
	_setup_screen_rect()
	_setup_shader_material()
	_apply_preset_values(apply_preset)
	_update_viewport_size_uniform()


func _process(_delta: float) -> void:
	if update_viewport_size_each_frame:
		_update_viewport_size_uniform()


func _setup_screen_rect() -> void:
	var existing: Node = get_node_or_null(screen_node_path)

	if existing is Control:
		screen_rect = existing as Control
	elif auto_create_screen:
		var rect: ColorRect = ColorRect.new()
		rect.name = String(screen_node_path)
		add_child(rect)
		screen_rect = rect
	else:
		push_warning("CrtPostFX: Kein Screen-Control gefunden und auto_create_screen ist aus.")
		return

	_make_fullscreen(screen_rect)

	if ignore_mouse:
		screen_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if screen_rect is ColorRect:
		(screen_rect as ColorRect).color = Color.WHITE

	screen_rect.visible = true
	screen_rect.z_index = 4096


func _make_fullscreen(control: Control) -> void:
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0


func _setup_shader_material() -> void:
	if screen_rect == null:
		return

	if screen_rect.material is ShaderMaterial:
		shader_material = screen_rect.material as ShaderMaterial
	else:
		shader_material = ShaderMaterial.new()
		screen_rect.material = shader_material

	if shader_material.shader == null:
		var shader: Shader = load(shader_path) as Shader
		if shader:
			shader_material.shader = shader
		else:
			push_warning("CrtPostFX: Shader konnte nicht geladen werden: " + shader_path)


func _update_viewport_size_uniform() -> void:
	if shader_material == null:
		return

	var final_size := Vector2(600.0, 338.0)

	if screen_rect != null:
		final_size = screen_rect.size

	if final_size.x <= 1.0 or final_size.y <= 1.0:
		final_size = get_viewport().get_visible_rect().size

	if final_size.x <= 1.0:
		final_size.x = 600.0
	if final_size.y <= 1.0:
		final_size.y = 338.0

	shader_material.set_shader_parameter("viewport_size", final_size)


func _push_all_uniforms() -> void:
	if shader_material == null:
		return

	shader_material.set_shader_parameter("effect_enabled", 1.0 if effect_enabled else 0.0)
	shader_material.set_shader_parameter("crt_curvature", crt_curvature)
	shader_material.set_shader_parameter("scanline_intensity", scanline_intensity)
	shader_material.set_shader_parameter("scanline_count", scanline_count)
	shader_material.set_shader_parameter("scanline_scroll_speed", scanline_scroll_speed)
	shader_material.set_shader_parameter("chroma_aberration", chroma_aberration)
	shader_material.set_shader_parameter("glitch_intensity", glitch_intensity)
	shader_material.set_shader_parameter("glitch_speed", glitch_speed)
	shader_material.set_shader_parameter("glitch_block_size", glitch_block_size)
	shader_material.set_shader_parameter("noise_intensity", noise_intensity)
	shader_material.set_shader_parameter("flicker_intensity", flicker_intensity)
	shader_material.set_shader_parameter("phosphor_glow", phosphor_glow)
	shader_material.set_shader_parameter("vignette_strength", vignette_strength)
	shader_material.set_shader_parameter("tint_color", tint_color)
	_update_viewport_size_uniform()


func _set_uniform(param_name: String, value: Variant) -> void:
	if shader_material:
		shader_material.set_shader_parameter(param_name, value)


func set_effect_enabled(enabled: bool) -> void:
	effect_enabled = enabled
	_set_uniform("effect_enabled", 1.0 if effect_enabled else 0.0)


func apply_runtime_preset(preset: PresetType) -> void:
	apply_preset = preset
	_apply_preset_values(preset)


func _apply_preset_values(preset: PresetType) -> void:
	match preset:
		PresetType.PUPPETCOMBO:
			# Main gameplay preset: subtil, dreckig, aber nicht nervig
			crt_curvature = 1.1
			scanline_intensity = 0.22
			scanline_count = 240.0
			scanline_scroll_speed = 0.035
			chroma_aberration = 0.0018
			glitch_intensity = 0.035
			glitch_speed = 4.0
			glitch_block_size = 24.0
			noise_intensity = 0.025
			flicker_intensity = 0.012
			phosphor_glow = 0.12
			vignette_strength = 0.38
			tint_color = Color(0.97, 1.0, 0.90, 1.0)

		PresetType.VHS_TAPE:
			# VHS sichtbar, aber nicht komplett zerstört
			crt_curvature = 1.3
			scanline_intensity = 0.28
			scanline_count = 360.0
			scanline_scroll_speed = 0.07
			chroma_aberration = 0.003
			glitch_intensity = 0.075
			glitch_speed = 5.5
			glitch_block_size = 28.0
			noise_intensity = 0.045
			flicker_intensity = 0.025
			phosphor_glow = 0.16
			vignette_strength = 0.5
			tint_color = Color(1.0, 0.95, 0.82, 1.0)

		PresetType.CLEAN_CRT:
			# Sehr dezenter CRT Look
			crt_curvature = 0.45
			scanline_intensity = 0.12
			scanline_count = 240.0
			scanline_scroll_speed = 0.015
			chroma_aberration = 0.0008
			glitch_intensity = 0.0
			glitch_speed = 3.0
			glitch_block_size = 24.0
			noise_intensity = 0.01
			flicker_intensity = 0.004
			phosphor_glow = 0.06
			vignette_strength = 0.18
			tint_color = Color(1.0, 1.0, 0.97, 1.0)

		PresetType.NIGHTMARE:
			# Für Jumpscares / Red-Light / Hospital, aber nicht dauerhaft unerträglich
			crt_curvature = 1.8
			scanline_intensity = 0.38
			scanline_count = 240.0
			scanline_scroll_speed = 0.12
			chroma_aberration = 0.006
			glitch_intensity = 0.22
			glitch_speed = 8.0
			glitch_block_size = 20.0
			noise_intensity = 0.075
			flicker_intensity = 0.045
			phosphor_glow = 0.25
			vignette_strength = 0.9
			tint_color = Color(0.88, 1.0, 0.82, 1.0)

	_push_all_uniforms()

func tween_param(param_name: String, target_value: float, duration: float) -> Tween:
	var start_value: float = _get_float_param(param_name)
	var tween: Tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_method(
		func(value: float) -> void:
			_assign_float_param(param_name, value),
		start_value,
		target_value,
		duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	return tween


func glitch_burst(strength := 0.35, duration := 0.25) -> Tween:
	var previous: float = glitch_intensity

	if _burst_tween:
		_burst_tween.kill()

	_assign_float_param("glitch_intensity", strength)

	_burst_tween = create_tween()
	_burst_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_burst_tween.tween_method(
		func(value: float) -> void:
			_assign_float_param("glitch_intensity", value),
		strength,
		previous,
		duration
	).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	return _burst_tween


func _get_float_param(param_name: String) -> float:
	match param_name:
		"crt_curvature": return crt_curvature
		"scanline_intensity": return scanline_intensity
		"scanline_count": return scanline_count
		"scanline_scroll_speed": return scanline_scroll_speed
		"chroma_aberration": return chroma_aberration
		"glitch_intensity": return glitch_intensity
		"glitch_speed": return glitch_speed
		"glitch_block_size": return glitch_block_size
		"noise_intensity": return noise_intensity
		"flicker_intensity": return flicker_intensity
		"phosphor_glow": return phosphor_glow
		"vignette_strength": return vignette_strength
		_:
			if shader_material:
				var current: Variant = shader_material.get_shader_parameter(param_name)
				if current != null:
					return float(current)
			return 0.0


func _assign_float_param(param_name: String, value: float) -> void:
	match param_name:
		"crt_curvature": crt_curvature = value
		"scanline_intensity": scanline_intensity = value
		"scanline_count": scanline_count = value
		"scanline_scroll_speed": scanline_scroll_speed = value
		"chroma_aberration": chroma_aberration = value
		"glitch_intensity": glitch_intensity = value
		"glitch_speed": glitch_speed = value
		"glitch_block_size": glitch_block_size = value
		"noise_intensity": noise_intensity = value
		"flicker_intensity": flicker_intensity = value
		"phosphor_glow": phosphor_glow = value
		"vignette_strength": vignette_strength = value

	_set_uniform(param_name, value)
