extends Node3D
## Shared story rewards: weed at 7, cocaine at 20, MDMA at 25.

const OUTLINE := preload("res://assets/shader/inventory_outline.gdshader")
const PICK_LAYER := 1 << 22
const WEED_SHADER := preload("res://assets/shader/lsd.gdshader")
const COCAINE_SHADER := preload("res://assets/shader/cocaine.gdshader")
const MDMA_SHADER := preload("res://assets/shader/mdma.gdshader")

@export_range(1.0, 300.0, 1.0) var effect_duration := 60.0
@export_range(0.1, 20.0, 0.1) var fade_in_duration := 5.0
@export_range(0.1, 20.0, 0.1) var fade_out_duration := 5.0
@export_range(0.1, 10.0, 0.1) var drop_height := 4.0
@export_range(0.1, 3.0, 0.05) var drop_duration := 0.9
@export_range(200.0, 8000.0, 50.0) var high_cut_hz := 1200.0

@onready var model: Node3D = $Model
@onready var mesh: MeshInstance3D = $Model/Cube
@onready var area: Area3D = $PickArea
@onready var overlay: CanvasLayer = $PsychedelicOverlay
@onready var effect_rect: ColorRect = $PsychedelicOverlay/EffectRect
@onready var mdma_audio: Node3D = $MdmaAudio

var landed := false
var dropping := false
var active := false
var hovered := false
var remaining := 0.0
var _main: Node
var _camera: Camera3D
var _hint: Sprite3D
var _rest := Transform3D.IDENTITY
var _drop_elapsed := 0.0
var _effect_elapsed := 0.0
var _outline: ShaderMaterial
var _effect_material: ShaderMaterial
var _original_overlay: Material
var _high_cut: AudioEffectLowPassFilter
var _admin_package := false
var _hint_modulate := Color.WHITE
var package_kind := "weed"
var _models: Dictionary = {}
var _model_rests: Dictionary = {}
var _hints: Dictionary = {}
var _hint_colors: Dictionary = {}


func _ready() -> void:
	_rest = model.transform
	_models = {"weed": model, "cocaine": $CocaineModel, "mdma": $MdmaModel}
	for kind: String in _models:
		_model_rests[kind] = (_models[kind] as Node3D).transform
		(_models[kind] as Node3D).hide()
	_original_overlay = mesh.material_overlay
	_outline = ShaderMaterial.new()
	_outline.shader = OUTLINE
	_outline.set_shader_parameter("outline_color", Color(1.0, 0.85, 0.0, 1.0))
	# The imported mesh is heavily compressed along Y. Scale in view space so
	# the border stays consistent instead of becoming a thin yellow slab.
	_outline.set_shader_parameter("world_space_size", true)
	_outline.set_shader_parameter("outline_size", 0.008)
	_effect_material = effect_rect.material.duplicate() as ShaderMaterial
	effect_rect.material = _effect_material
	model.hide()
	overlay.hide()
	_set_pickable(false)
	area.input_event.connect(_on_pick_input)


func configure(main: Node, hint: Sprite3D, cocaine_hint: Sprite3D = null) -> void:
	_main = main
	_camera = main.main_camera
	_hint = hint
	_hint_modulate = hint.modulate
	_hint.hide()
	_hints = {"weed": hint, "cocaine": cocaine_hint}
	for kind: String in _hints:
		var sprite := _hints[kind] as Sprite3D
		if sprite != null:
			_hint_colors[kind] = sprite.modulate
			sprite.hide()
	_select_kind(GameCurrency.get_story_package_kind())
	GameCurrency.progression_changed.connect(_on_progression_changed)
	GameCurrency.story_package_queued.connect(_on_package_queued)
	CollectionManager.collection_changed.connect(func(_cards: Array[String]): _on_progression_changed(0, 0, 0))


func _on_package_queued() -> void:
	if active or _admin_package:
		return
	landed = false
	dropping = false
	model.hide()
	_set_pickable(false)


func _select_kind(kind: String) -> void:
	if kind == package_kind:
		return
	model.transform = _model_rests[package_kind]
	model.hide()
	mesh.material_overlay = _original_overlay
	if is_instance_valid(_hint):
		_hint.hide()
	package_kind = kind
	model = _models[kind] as Node3D
	mesh = model.get_node("Cube" if kind == "weed" else "Model/Cube") as MeshInstance3D
	_rest = _model_rests[kind]
	model.transform = _rest
	_original_overlay = mesh.material_overlay
	_hint = _hints.get(kind) as Sprite3D
	_hint_modulate = _hint_colors.get(kind, Color.WHITE)
	_effect_material.shader = {"weed": WEED_SHADER, "cocaine": COCAINE_SHADER, "mdma": MDMA_SHADER}[kind]
	landed = false
	dropping = false
	_set_pickable(false)


func _on_progression_changed(_level: int, _xp: int, _required: int) -> void:
	if not _admin_package and not GameCurrency.is_story_package_available(package_kind):
		if not active:
			landed = false
			dropping = false
			model.hide()
			_set_pickable(false)


func _context_is_safe() -> bool:
	return (is_instance_valid(_main) and is_instance_valid(_camera)
		and not get_tree().paused and _main._satan_jumpscare_context_is_safe()
		and not GameCurrency.is_training_session())


func _process(delta: float) -> void:
	if active:
		_effect_elapsed += delta
		remaining = maxf(effect_duration - _effect_elapsed, 0.0)
		var fade_in := _effect_elapsed / maxf(minf(fade_in_duration, effect_duration * 0.5), 0.01)
		var fade_out := remaining / maxf(minf(fade_out_duration, effect_duration * 0.5), 0.01)
		_set_effect_strength(smoothstep(0.0, 1.0, clampf(minf(fade_in, fade_out), 0.0, 1.0)))
		if remaining <= 0.0:
			clear_effect()
	if not is_instance_valid(_main):
		return
	var safe := _context_is_safe()
	if not active and not _admin_package:
		_select_kind(GameCurrency.get_story_package_kind())
	if safe and GameCurrency.admin_weed_drop_pending:
		GameCurrency.admin_weed_drop_pending = false
		clear_effect()
		_select_kind(GameCurrency.get_story_package_kind())
		landed = false
		_admin_package = true
		_begin_drop()
	if not landed and not dropping and not active and GameCurrency.is_story_package_available(package_kind) and safe:
		_begin_drop()
	if dropping:
		# A deterministic accelerating fall and small landing bounce, without
		# waking physics bodies or depending on collision triangles in the GLB.
		_drop_elapsed += delta
		var t := clampf(_drop_elapsed / drop_duration, 0.0, 1.0)
		model.position = _rest.origin + Vector3.UP * drop_height * (1.0 - t * t)
		if t >= 1.0:
			var bounce := clampf((_drop_elapsed - drop_duration) / 0.2, 0.0, 1.0)
			model.position.y += sin(bounce * PI) * 0.075
			if bounce >= 1.0:
				model.transform = _rest
				dropping = false
				landed = true
	_set_pickable(landed and not active and (_admin_package or GameCurrency.is_story_package_available(package_kind)) and safe)
	_set_hovered(area.input_ray_pickable and _pointer_hits(get_viewport().get_mouse_position()))


func _begin_drop() -> void:
	dropping = true
	_drop_elapsed = 0.0
	model.transform = _rest
	model.position.y += drop_height
	model.show()


func _set_effect_strength(strength: float) -> void:
	_effect_material.set_shader_parameter("effect_mix", strength)
	if is_instance_valid(_hint):
		_hint.modulate = _hint_modulate * Color(1, 1, 1, strength)
	if _high_cut != null:
		# Logarithmic frequency movement sounds even as the highs soften/return.
		_high_cut.cutoff_hz = exp(lerpf(log(20000.0), log(high_cut_hz), strength))
	if package_kind == "cocaine" and is_instance_valid(_main) and is_instance_valid(_main.music):
		_main.music.set_cocaine_effect_strength(strength)
	if package_kind == "mdma":
		mdma_audio.set_strength(strength)
		if is_instance_valid(_main) and is_instance_valid(_main.music):
			_main.music.set_mdma_effect_strength(strength)


func _set_pickable(enabled: bool) -> void:
	area.input_ray_pickable = enabled
	area.collision_layer = PICK_LAYER if enabled else 0
	area.set_meta("keep_input_ray_pickable_disabled", not enabled)
	if not enabled:
		_set_hovered(false)


func _pointer_hits(pointer: Vector2) -> bool:
	if not get_viewport().get_visible_rect().has_point(pointer):
		return false
	var origin := _camera.project_ray_origin(pointer)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + _camera.project_ray_normal(pointer) * _camera.far)
	query.collide_with_areas = true
	return get_world_3d().direct_space_state.intersect_ray(query).get("collider") == area


func _set_hovered(value: bool) -> void:
	if hovered == value:
		return
	hovered = value
	mesh.material_overlay = _outline if hovered else _original_overlay


func _on_pick_input(camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape: int) -> void:
	if camera != _camera or not area.input_ray_pickable or not _context_is_safe():
		return
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	# Commit before removing the object. A failed write leaves it available.
	if not GameCurrency.consume_story_package(package_kind, _admin_package):
		return
	_admin_package = false
	get_viewport().set_input_as_handled()
	landed = false
	_set_pickable(false)
	model.hide()
	_start_effect()


func _start_effect() -> void:
	if active:
		return
	active = true
	_main.music.set_weed_effect_active(package_kind == "weed")
	_effect_elapsed = 0.0
	remaining = effect_duration
	_set_effect_strength(0.0)
	overlay.show()
	if is_instance_valid(_hint):
		_hint.show()
	if package_kind == "mdma":
		# Voices start once the image has faded in, then follow the same lifetime.
		_main.scene_pivot.get_node("GameTable")._get_or_create_lowpass()
		mdma_audio.start(_camera, minf(fade_in_duration, effect_duration * 0.5))
		return
	if package_kind == "cocaine":
		return
	# The existing gunshot hearing recovery owns the first Master effect.
	# Reserve that slot first, then append an independent effect we can remove.
	_main.scene_pivot.get_node("GameTable")._get_or_create_lowpass()
	var master := AudioServer.get_bus_index("Master")
	_high_cut = AudioEffectLowPassFilter.new()
	_high_cut.resource_name = "WeedHighCut"
	_high_cut.cutoff_hz = 20000.0
	_high_cut.resonance = 0.35
	_high_cut.db = AudioEffectFilter.FILTER_24DB
	AudioServer.add_bus_effect(master, _high_cut)


func clear_effect() -> void:
	if is_instance_valid(mdma_audio):
		mdma_audio.stop()
	if active and is_instance_valid(_main) and is_instance_valid(_main.music):
		_main.music.set_weed_effect_active(false)
		if package_kind == "cocaine":
			_main.music.set_cocaine_effect_strength(0.0)
		if package_kind == "mdma":
			_main.music.set_mdma_effect_strength(0.0)
	active = false
	remaining = 0.0
	if is_instance_valid(overlay):
		overlay.hide()
	if is_instance_valid(_hint):
		_hint.hide()
		_hint.modulate = _hint_modulate
	var master := AudioServer.get_bus_index("Master")
	if master >= 0 and _high_cut != null:
		for index in range(AudioServer.get_bus_effect_count(master) - 1, -1, -1):
			if AudioServer.get_bus_effect(master, index) == _high_cut:
				AudioServer.remove_bus_effect(master, index)
	_high_cut = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if is_instance_valid(area):
			_set_pickable(false)


func _exit_tree() -> void:
	clear_effect()
