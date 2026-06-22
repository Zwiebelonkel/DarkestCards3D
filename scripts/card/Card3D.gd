extends Node3D
class_name Card3D

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
var base_scale := Vector3.ONE


func _ready() -> void:
	base_scale = scale

	if area:
		area.mouse_entered.connect(_on_mouse_entered)
		area.mouse_exited.connect(_on_mouse_exited)


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


func _apply_rarity_style(rarity: String) -> void:
	var color := _get_rarity_color(rarity)

	rarity_label.modulate = color
	_apply_material_to_all_meshes(card_outline, color)


func _apply_material_to_all_meshes(root: Node, color: Color) -> void:
	if root == null:
		return

	if root is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.45
		mat.roughness = 0.35
		mat.metallic = 0.2
		root.material_override = mat

	for child in root.get_children():
		_apply_material_to_all_meshes(child, color)


func _get_rarity_color(rarity: String) -> Color:
	match rarity:
		"common":
			return Color(0.55, 0.55, 0.55, 1) # grau
		"uncommon":
			return Color(0.25, 0.85, 0.35, 1) # grün
		"rare":
			return Color(0.2, 0.45, 1.0, 1) # blau
		"epic":
			return Color(0.75, 0.25, 1.0, 1) # violett
		"legendary":
			return Color(1.0, 0.72, 0.12, 1) # gold
		"mythic":
			return Color(0.18, 0.08, 0.45, 1) # dunkel violett/bläulich
		"exotic":
			return Color(1.0, 0.05, 0.05, 1) # knallrot
		_:
			return Color(0.45, 0.45, 0.45, 1)


func _shorten_description(text: String, max_chars: int = 95) -> String:
	if text.length() <= max_chars:
		return text

	return text.substr(0, max_chars - 3) + "..."


func _on_mouse_entered() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", base_scale * 1.08, 0.12)


func _on_mouse_exited() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", base_scale, 0.12)
