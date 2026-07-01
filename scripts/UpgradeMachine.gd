extends Node3D
class_name UpgradeMachine

const CARD_SCENE := preload("res://scenes/table/Card3D.tscn")

@export var upgrade_viewport: SubViewport
@export var screen_mesh: MeshInstance3D
@export var card_preview_point: Marker3D

@export var attack_cost := 5
@export var health_cost := 5
@export var effect_cost := 12

@export_group("Preview Card")
@export var preview_card_position_offset := Vector3.ZERO
@export var preview_card_rotation := Vector3(-90, 0, 0)
@export var preview_card_scale := 0.55
@export var preview_card_spin_speed := 35.0

var selected_card_id := ""
var preview_card: Card3D = null

@onready var ui: Control = $UpgradeViewport/UpgradeUI


func _ready() -> void:
	_setup_screen_material()
	_connect_ui()
	_refresh_card_list()


func _setup_screen_material() -> void:
	if upgrade_viewport == null:
		upgrade_viewport = $UpgradeViewport

	if screen_mesh == null:
		screen_mesh = $MachineModel/ScreenMesh

	upgrade_viewport.disable_3d = true
	upgrade_viewport.gui_disable_input = false
	upgrade_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var tex := upgrade_viewport.get_texture()

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.emission_enabled = true
	mat.emission_texture = tex
	mat.emission_energy_multiplier = 1.4
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	screen_mesh.set_surface_override_material(0, mat)


func _connect_ui() -> void:
	ui.card_selected.connect(_on_card_selected)
	ui.attack_pressed.connect(_upgrade_attack)
	ui.health_pressed.connect(_upgrade_health)
	ui.effect_pressed.connect(_roll_effect)


func _refresh_card_list() -> void:
	var owned := CollectionManager.get_owned_cards()
	ui.set_cards(owned.keys())


func _on_card_selected(card_id: String) -> void:
	selected_card_id = card_id
	_spawn_preview_card()
	ui.set_selected_card(card_id)

func _process(delta: float) -> void:
	if preview_card != null and is_instance_valid(preview_card):
		preview_card.rotate_y(deg_to_rad(preview_card_spin_speed) * delta)

func _spawn_preview_card() -> void:
	if card_preview_point == null:
		card_preview_point = get_node_or_null("CardPreviewPoint") as Marker3D

	if card_preview_point == null:
		push_error("UpgradeMachine: CardPreviewPoint fehlt oder NodePath ist falsch.")
		return

	if preview_card != null and is_instance_valid(preview_card):
		preview_card.queue_free()

	var data := CardDatabase.get_card(selected_card_id)
	if data.is_empty():
		return

	data = CardUpgradeManager.apply_upgrades(selected_card_id, data)

	preview_card = CARD_SCENE.instantiate() as Card3D
	add_child(preview_card)
	preview_card.setup(data)

	preview_card.global_position = card_preview_point.global_position + preview_card_position_offset
	preview_card.rotation_degrees = preview_card_rotation
	preview_card.scale = Vector3.ONE * preview_card_scale

func _upgrade_attack() -> void:
	if selected_card_id == "":
		return

	if not GameCurrency.spend_coins(attack_cost):
		ui.show_message("Nicht genug Soul Coins")
		ui.refresh_balance()
		return

	CardUpgradeManager.add_attack(selected_card_id, 1)

	ui.refresh_balance()
	ui.set_selected_card(selected_card_id)
	ui.show_message("+1 Angriff")

	_spawn_preview_card()

func _upgrade_health() -> void:
	if selected_card_id == "":
		return

	if not GameCurrency.spend_coins(health_cost):
		ui.show_message("Nicht genug Soul Coins")
		ui.refresh_balance()
		return

	CardUpgradeManager.add_health(selected_card_id, 1)

	ui.refresh_balance()
	ui.set_selected_card(selected_card_id)
	ui.show_message("+1 Leben")

	_spawn_preview_card()


func _roll_effect() -> void:
	if selected_card_id == "":
		return

	if CardUpgradeManager.get_active_effect_count(selected_card_id) >= CardData.MAX_EFFECTS_PER_CARD:
		ui.show_message("Maximal 2 Effects")
		return

	if not GameCurrency.spend_coins(effect_cost):
		ui.show_message("Nicht genug Soul Coins")
		ui.refresh_balance()
		return

	var effects: Array[Dictionary] = EffectDatabase.roll_effects()

	if effects.is_empty():
		ui.show_message("Kein Effekt gerollt")
		ui.refresh_balance()
		return

	var effect: Dictionary = effects[0]

	if not CardUpgradeManager.add_effect(selected_card_id, effect):
		ui.show_message("Maximal 2 Effects")
		ui.refresh_balance()
		return

	ui.refresh_balance()
	ui.set_selected_card(selected_card_id)
	ui.show_message("Effekt: " + str(effect.get("name")))

	_spawn_preview_card()
