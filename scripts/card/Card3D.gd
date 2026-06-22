extends Node3D
class_name Card3D

const RARITY_OUTLINE_SHADER := preload("res://assets/shader/rarity_outline.gdshader")
const CARD_SHINE_SHADER := preload("res://assets/shader/card_shine.gdshader")

@onready var card_model: Node3D = $card
@onready var card_outline: Node3D = $cardOutline
@onready var card_image: MeshInstance3D = $CardImage
@onready var name_label: Label3D = $NameLabel
@onready var attack_label: Label3D = $AttackLabel
@onready var defense_label: Label3D = $DefenseLabel
@onready var description_label: Label3D = $DescriptionLabel
@onready var rarity_label: Label3D = $RarityLabel
@onready var area: Area3D = $Area3D

var card_data: Dictionary = {}

# Wie "heftig" sich der Rarity-Shader pro Stufe verhaelt. Reihenfolge
# der Felder: intensity, scroll_speed, band_density, jaggedness,
# pulse_strength, pulse_speed, base_glow.
# common bleibt bewusst praktisch unbewegt/ruhig, exotic ist maximal
# chaotisch und hell.
const RARITY_SHADER_PRESETS := {
	"common": {
		"intensity": 0.0,
		"scroll_speed": 0.0,
		"band_density": 2.0,
		"jaggedness": 0.0,
		"pulse_strength": 0.0,
		"pulse_speed": 0.0,
		"base_glow": 0.18,
	},
	"uncommon": {
		"intensity": 0.5,
		"scroll_speed": 0.5,
		"band_density": 3.0,
		"jaggedness": 0.15,
		"pulse_strength": 0.15,
		"pulse_speed": 1.2,
		"base_glow": 0.22,
	},
	"rare": {
		"intensity": 0.9,
		"scroll_speed": 0.9,
		"band_density": 4.0,
		"jaggedness": 0.3,
		"pulse_strength": 0.2,
		"pulse_speed": 1.6,
		"base_glow": 0.28,
	},
	"epic": {
		"intensity": 1.3,
		"scroll_speed": 1.3,
		"band_density": 5.0,
		"jaggedness": 0.45,
		"pulse_strength": 0.3,
		"pulse_speed": 2.0,
		"base_glow": 0.32,
	},
	"legendary": {
		"intensity": 1.7,
		"scroll_speed": 1.7,
		"band_density": 6.0,
		"jaggedness": 0.55,
		"pulse_strength": 0.35,
		"pulse_speed": 2.4,
		"base_glow": 0.38,
	},
	"mythic": {
		"intensity": 2.1,
		"scroll_speed": 2.1,
		"band_density": 7.0,
		"jaggedness": 0.7,
		"pulse_strength": 0.4,
		"pulse_speed": 2.8,
		"base_glow": 0.42,
	},
	"exotic": {
		"intensity": 2.6,
		"scroll_speed": 2.8,
		"band_density": 8.0,
		"jaggedness": 0.9,
		"pulse_strength": 0.5,
		"pulse_speed": 3.4,
		"base_glow": 0.5,
	},
}

@export_group("Shine-Sweep")
@export var shine_interval_min := 3.0
@export var shine_interval_max := 4.0
@export var shine_sweep_duration := 1.1
@export var shine_z_offset := 0.004

var _shine_mesh: MeshInstance3D = null
var _shine_material: ShaderMaterial = null
var _shine_timer: Timer = null
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_setup_shine_overlay()
	_start_shine_loop()


func setup(data: Dictionary) -> void:
	card_data = data

	var card_name := str(data.get("name", "Unknown"))
	var attack := int(data.get("attack", 0))
	var defense := int(data.get("defense", 0))
	var rarity := str(data.get("rarity", "common")).to_lower()
	var description := str(data.get("description", ""))
	var image_path := str(data.get("image", ""))

	name_label.text = card_name
	attack_label.text = str(attack)
	defense_label.text = str(defense)
	description_label.text = _shorten_description(description)
	rarity_label.text = rarity.to_upper()

	_apply_rarity_style(rarity)
	_apply_card_image(image_path)


func _apply_card_image(image_path: String) -> void:
	if image_path == "":
		return

	var texture := load(image_path)
	if texture == null:
		push_warning("Kartenbild nicht gefunden: " + image_path)
		return

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.roughness = 0.8
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	card_image.material_override = mat


# FIX/Upgrade: Statt eines statischen StandardMaterial3D bekommt der
# Rahmen (card_outline) jetzt einen animierten ShaderMaterial mit
# wandernden Energie-/Riss-Baendern. Die "Heftigkeit" (Geschwindigkeit,
# Dichte, Pulsieren, Eckigkeit) skaliert mit der Rarity-Stufe ueber
# RARITY_SHADER_PRESETS.
func _apply_rarity_style(rarity: String) -> void:
	var color := _get_rarity_color(rarity)
	var preset: Dictionary = RARITY_SHADER_PRESETS.get(rarity, RARITY_SHADER_PRESETS["common"])

	rarity_label.modulate = color
	_apply_rarity_shader_to_all_meshes(card_outline, color, preset)


func _apply_rarity_shader_to_all_meshes(root: Node, color: Color, preset: Dictionary) -> void:
	if root == null:
		return

	if root is MeshInstance3D:
		var mat := ShaderMaterial.new()
		mat.shader = RARITY_OUTLINE_SHADER
		mat.set_shader_parameter("rarity_color", color)
		mat.set_shader_parameter("intensity", preset.get("intensity", 1.0))
		mat.set_shader_parameter("scroll_speed", preset.get("scroll_speed", 1.0))
		mat.set_shader_parameter("band_density", preset.get("band_density", 4.0))
		mat.set_shader_parameter("jaggedness", preset.get("jaggedness", 0.3))
		mat.set_shader_parameter("pulse_strength", preset.get("pulse_strength", 0.25))
		mat.set_shader_parameter("pulse_speed", preset.get("pulse_speed", 2.0))
		mat.set_shader_parameter("base_glow", preset.get("base_glow", 0.35))
		root.material_override = mat

	for child in root.get_children():
		_apply_rarity_shader_to_all_meshes(child, color, preset)


func _get_rarity_color(rarity: String) -> Color:
	match rarity:
		"common":
			return Color(0.55, 0.55, 0.55, 1)
		"uncommon":
			return Color(0.25, 0.85, 0.35, 1)
		"rare":
			return Color(0.2, 0.45, 1.0, 1)
		"epic":
			return Color(0.75, 0.25, 1.0, 1)
		"legendary":
			return Color(1.0, 0.72, 0.12, 1)
		"mythic":
			return Color(0.18, 0.08, 0.45, 1)
		"exotic":
			return Color(1.0, 0.05, 0.05, 1)
		_:
			return Color(0.45, 0.45, 0.45, 1)


func _shorten_description(text: String, max_chars: int = 95) -> String:
	if text.length() <= max_chars:
		return text
	return text.substr(0, max_chars - 3) + "..."


# --- Shine-Sweep-Overlay -------------------------------------------------
#
# Erzeugt ein zusaetzliches MeshInstance3D direkt vor card_image (gleiche
# Mesh-Geometrie, minimal nach vorne versetzt um Z-Fighting zu vermeiden),
# das NUR den additiven Foil-Shine-Shader traegt. Das laeuft komplett
# unabhaengig vom Rarity-Shader und betrifft ALLE Karten gleich, egal
# welche Rarity.
func _setup_shine_overlay() -> void:
	if card_image == null or card_image.mesh == null:
		return

	_shine_mesh = MeshInstance3D.new()
	_shine_mesh.name = "ShineOverlay"
	_shine_mesh.mesh = card_image.mesh
	_shine_mesh.position = card_image.position + Vector3(0, 0, shine_z_offset)
	_shine_mesh.rotation = card_image.rotation
	_shine_mesh.scale = card_image.scale

	_shine_material = ShaderMaterial.new()
	_shine_material.shader = CARD_SHINE_SHADER
	_shine_material.set_shader_parameter("sweep_position", -0.5)
	_shine_mesh.material_override = _shine_material

	# Die Sweep-Mesh soll keine Klicks/Hover der eigentlichen Karten-Area
	# blockieren koennen - sie ist rein optisch und liegt nur knapp vor
	# dem Kartenbild.
	card_image.get_parent().add_child(_shine_mesh)


func _start_shine_loop() -> void:
	if _shine_material == null:
		return

	_shine_timer = Timer.new()
	_shine_timer.one_shot = true
	add_child(_shine_timer)
	_shine_timer.timeout.connect(_run_shine_sweep)

	_schedule_next_shine()


func _schedule_next_shine() -> void:
	if _shine_timer == null:
		return

	var wait_time := _rng.randf_range(shine_interval_min, shine_interval_max)
	_shine_timer.start(wait_time)


func _run_shine_sweep() -> void:
	if _shine_material == null:
		_schedule_next_shine()
		return

	_shine_material.set_shader_parameter("sweep_position", -0.5)

	var tween := create_tween()
	tween.tween_method(_set_sweep_position, -0.5, 1.5, shine_sweep_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	await tween.finished
	_schedule_next_shine()


func _set_sweep_position(value: float) -> void:
	if _shine_material != null:
		_shine_material.set_shader_parameter("sweep_position", value)
