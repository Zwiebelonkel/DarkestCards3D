extends Control
class_name PackShopUI

signal pack_buy_pressed(pack_id: String)

const VCR_FONT := preload("res://fonts/VCR_OSD_MONO_1.001.ttf")

@onready var balance_label: Label = $Panel/MarginContainer/VBoxContainer/BalanceLabel
@onready var pack_choices: HBoxContainer = $Panel/MarginContainer/VBoxContainer/PackChoices
@onready var info_label: Label = $Panel/MarginContainer/VBoxContainer/InfoLabel
@onready var buy_button: Button = $Panel/MarginContainer/VBoxContainer/BuyButton
@onready var message_label: Label = $Panel/MarginContainer/VBoxContainer/MessageLabel

var pack_entries: Array[Dictionary] = []
var selected_pack_id := ""
var message_tween: Tween = null
var _pack_buttons: Array[BaseButton] = []
var _pack_models: Array[Node3D] = []
var _buy_locked := false

const PACK_SCENE := preload("res://assets/cards/pack/pack.glb")
const PACK_VARIANT_COLORS := {
	"basic": Color(0.95, 0.24, 0.2, 1.0),
	"rare": Color(0.25, 0.42, 1.0, 1.0),
	"god": Color(1.0, 0.76, 0.18, 1.0)
}


func _ready() -> void:
	buy_button.pressed.connect(_on_buy_pressed)

	refresh_balance()
	show_message("")


func set_packs(packs: Dictionary) -> void:
	pack_entries.clear()
	_clear_pack_choices()

	for pack_id in packs.keys():
		var data: Dictionary = packs[pack_id]

		pack_entries.append({
			"id": str(pack_id),
			"data": data
		})

		_add_pack_choice(pack_entries.size() - 1)

	if pack_entries.is_empty():
		info_label.text = "NO PACKS AVAILABLE"
		buy_button.disabled = true
		return

	_select_pack(0)


func refresh_balance() -> void:
	balance_label.text = "SOUL COINS: " + str(GameCurrency.coins)


func show_message(text: String) -> void:
	if message_label == null:
		return

	if message_tween:
		message_tween.kill()
		message_tween = null

	if text == "":
		message_label.visible = false
		return

	message_label.text = text
	message_label.visible = true
	message_label.modulate.a = 1.0

	message_tween = create_tween()
	message_tween.tween_interval(1.2)
	message_tween.tween_property(message_label, "modulate:a", 0.0, 0.25)
	message_tween.tween_callback(func():
		if message_label:
			message_label.visible = false
	)


func _select_pack(index: int) -> void:
	if index < 0 or index >= pack_entries.size():
		return

	var entry := pack_entries[index]
	var data: Dictionary = entry.get("data", {})

	selected_pack_id = str(entry.get("id", ""))

	var name := str(data.get("name", selected_pack_id))
	var cost := int(data.get("cost", 0))
	var card_count := int(data.get("card_count", 0))
	var description := str(data.get("description", ""))

	info_label.text = "%s\nPRICE: %d SOUL COINS\nCARDS: %d\n%s" % [
		name,
		cost,
		card_count,
		description
	]

	_update_choice_selection()
	buy_button.disabled = _buy_locked or selected_pack_id == ""


func _on_buy_pressed() -> void:
	if selected_pack_id == "":
		return

	pack_buy_pressed.emit(selected_pack_id)
	
func set_buy_locked(locked: bool) -> void:
	_buy_locked = locked
	buy_button.disabled = locked or selected_pack_id == ""
	for button in _pack_buttons:
		button.disabled = locked


func _process(delta: float) -> void:
	for model in _pack_models:
		if is_instance_valid(model):
			model.rotation_degrees.y += 38.0 * delta
			model.rotation_degrees.x = -8.0 + sin(Time.get_ticks_msec() * 0.0018) * 3.0


func _clear_pack_choices() -> void:
	_pack_buttons.clear()
	_pack_models.clear()
	for child in pack_choices.get_children():
		child.queue_free()


func _add_pack_choice(index: int) -> void:
	var entry := pack_entries[index]
	var pack_id := str(entry.get("id", ""))
	var data: Dictionary = entry.get("data", {})

	var wrapper := PanelContainer.new()
	wrapper.custom_minimum_size = Vector2(0, 210)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pack_choices.add_child(wrapper)

	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(stack)

	var viewport_container := SubViewportContainer.new()
	viewport_container.custom_minimum_size = Vector2(0, 142)
	viewport_container.stretch = true
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(viewport_container)

	var viewport := SubViewport.new()
	viewport.size = Vector2i(220, 150)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(viewport)

	var root := Node3D.new()
	viewport.add_child(root)

	var camera := Camera3D.new()
	camera.position = Vector3(0, 0.35, 4.2)
	camera.fov = 38.0
	camera.current = true
	root.add_child(camera)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 25, 0)
	light.light_energy = 2.0
	root.add_child(light)

	var model := PACK_SCENE.instantiate() as Node3D
	model.scale = Vector3.ONE * 0.8
	model.rotation_degrees = Vector3(-8, 25, 0)
	root.add_child(model)
	_apply_pack_variant(model, pack_id)
	_pack_models.append(model)

	var label := Label.new()
	label.text = str(data.get("name", pack_id))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", VCR_FONT)
	label.add_theme_font_size_override("font_size", 26)
	stack.add_child(label)

	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.pressed.connect(func(): _select_pack(index))
	wrapper.add_child(button)
	_pack_buttons.append(button)


func _update_choice_selection() -> void:
	for i in _pack_buttons.size():
		var entry := pack_entries[i]
		_pack_buttons[i].text = "SELECTED" if str(entry.get("id", "")) == selected_pack_id else ""


func _apply_pack_variant(root: Node, pack_id: String) -> void:
	var color: Color = PACK_VARIANT_COLORS.get(pack_id, Color.WHITE)
	for child in root.get_children():
		_apply_pack_variant(child, pack_id)
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		var surface_count := 1
		if mesh_instance.mesh:
			surface_count = mesh_instance.mesh.get_surface_count()
		for surface in surface_count:
			var material := StandardMaterial3D.new()
			material.albedo_color = color
			material.emission_enabled = true
			material.emission = color * 0.18
			material.roughness = 0.45
			mesh_instance.set_surface_override_material(surface, material)
