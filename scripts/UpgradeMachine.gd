extends Node3D
class_name UpgradeMachine

const CARD_SCENE := preload("res://scenes/table/Card3D.tscn")
const EFFECT_OVERVIEW_SCENE := preload("res://scenes/CardEffectOverview.tscn")

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
@export var preview_card_spin_speed := 12.0

var selected_card_id := ""
var _filtered_deck: Array[String] = []
var preview_card: Card3D = null
var _effect_overview_layer: CanvasLayer = null
var _effect_overview: CardEffectOverviewUI = null

@onready var ui: UpgradeUI = $UpgradeViewport/UpgradeUI as UpgradeUI


func _ready() -> void:
	_setup_screen_material()
	_connect_ui()
	_connect_global_refresh_signals()
	ui.configure_costs(attack_cost, health_cost, effect_cost)
	_refresh_card_list()
	GameCurrency.npc_rescue_changed.connect(_sync_rescue_lock)
	CollectionManager.collection_changed.connect(_sync_rescue_lock_from_collection)
	_sync_rescue_lock()


func is_operational() -> bool:
	return GameCurrency.is_npc_rescued("angel")


func _sync_rescue_lock_from_collection(_ids: Array[String]) -> void:
	_sync_rescue_lock()


func _sync_rescue_lock() -> void:
	var enabled := is_operational()
	ui.visible = enabled
	upgrade_viewport.gui_disable_input = not enabled
	var area := get_node_or_null("ScreenArea") as Area3D
	if area != null:
		area.input_ray_pickable = enabled
		area.set_meta("keep_input_ray_pickable_disabled", not enabled)
	var mat := screen_mesh.get_surface_override_material(0) as StandardMaterial3D
	mat.albedo_texture = upgrade_viewport.get_texture() if enabled else null
	mat.albedo_color = Color.WHITE if enabled else Color.BLACK
	mat.emission_enabled = enabled
	if not enabled:
		selected_card_id = ""
		_remove_preview_card()


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
	ui.deck_filter_toggled.connect(_on_deck_filter_toggled)
	ui.attack_pressed.connect(_upgrade_attack)
	ui.health_pressed.connect(_upgrade_health)
	ui.effect_pressed.connect(_roll_effect)
	ui.remove_effect_pressed.connect(_remove_effect)


func _connect_global_refresh_signals() -> void:
	var collection_callback := Callable(self, "_on_collection_changed")
	if CollectionManager.has_signal("collection_changed") and not CollectionManager.is_connected("collection_changed", collection_callback):
		CollectionManager.connect("collection_changed", collection_callback)

	var coins_callback := Callable(self, "_on_coins_changed")
	if GameCurrency.has_signal("coins_changed") and not GameCurrency.is_connected("coins_changed", coins_callback):
		GameCurrency.connect("coins_changed", coins_callback)
	
func _remove_effect(effect_source: String, effect_index: int) -> void:
	if not is_operational() or selected_card_id == "":
		return

	if not CardUpgradeManager.remove_effect_at(selected_card_id, effect_source, effect_index):
		ui.show_message("Effekt konnte nicht entfernt werden")
		return

	ui.refresh_balance()
	ui.set_selected_card(selected_card_id)
	ui.show_message("Effekt entfernt")

	_spawn_preview_card()

func _refresh_card_list() -> void:
	var owned := CollectionManager.get_owned_cards()
	var card_ids := owned.keys()
	_filtered_deck.assign(DeckManager.get_deck_cards() if ui.deck_only else [])
	if ui.deck_only:
		card_ids = card_ids.filter(func(card_id: Variant) -> bool: return _filtered_deck.has(str(card_id)))
	ui.set_cards(card_ids, owned)
	# Filtering away a selection must also clear the machine's upgrade target.
	if selected_card_id != ui.selected_card_id:
		selected_card_id = ui.selected_card_id
		if selected_card_id.is_empty():
			_remove_preview_card()


func _on_deck_filter_toggled(_deck_only: bool) -> void:
	_refresh_card_list()


func _on_collection_changed(_card_ids: Array[String]) -> void:
	_refresh_card_list()
	if selected_card_id.is_empty():
		return
	_spawn_preview_card()


func _on_coins_changed(_coins: float) -> void:
	ui.refresh_balance()


func _on_card_selected(card_id: String) -> void:
	if not is_operational():
		return
	selected_card_id = card_id
	_spawn_preview_card()
	ui.set_selected_card(card_id)

func _process(delta: float) -> void:
	# Deck editing has no change signal. Compare its small card-id list only
	# while filtering, including changes made while this machine stays loaded.
	if ui.deck_only and DeckManager.battle_deck != _filtered_deck:
		_refresh_card_list()
	if preview_card != null and is_instance_valid(preview_card):
		preview_card.rotate_y(deg_to_rad(preview_card_spin_speed) * delta)

func _spawn_preview_card() -> void:
	if not is_operational():
		return
	if card_preview_point == null:
		card_preview_point = get_node_or_null("CardPreviewPoint") as Marker3D

	if card_preview_point == null:
		push_error("UpgradeMachine: CardPreviewPoint fehlt oder NodePath ist falsch.")
		return

	_remove_preview_card()

	var data := CollectionManager.get_display_card(selected_card_id)
	if data.is_empty():
		return

	data = CardUpgradeManager.apply_upgrades(selected_card_id, data)

	preview_card = CARD_SCENE.instantiate() as Card3D
	card_preview_point.add_child(preview_card)
	preview_card.setup(data)

	preview_card.position = preview_card_position_offset
	preview_card.rotation_degrees = preview_card_rotation
	preview_card.scale = Vector3.ONE * preview_card_scale
	_connect_preview_effect_overview(preview_card)


func _remove_preview_card() -> void:
	if preview_card == null or not is_instance_valid(preview_card):
		preview_card = null
		return
	if _effect_overview != null:
		_effect_overview.hide_overview(preview_card)
	preview_card.queue_free()
	preview_card = null


func _connect_preview_effect_overview(card: Card3D) -> void:
	if not is_instance_valid(card):
		return
	if not card.card_hovered.is_connected(_on_preview_card_hovered):
		card.card_hovered.connect(_on_preview_card_hovered)
	if not card.card_unhovered.is_connected(_on_preview_card_unhovered):
		card.card_unhovered.connect(_on_preview_card_unhovered)


func _ensure_effect_overview() -> void:
	if _effect_overview != null and is_instance_valid(_effect_overview):
		return
	if _effect_overview_layer == null or not is_instance_valid(_effect_overview_layer):
		_effect_overview_layer = CanvasLayer.new()
		_effect_overview_layer.name = "EffectOverviewLayer"
		_effect_overview_layer.layer = 40
		add_child(_effect_overview_layer)
	_effect_overview = EFFECT_OVERVIEW_SCENE.instantiate() as CardEffectOverviewUI
	_effect_overview_layer.add_child(_effect_overview)


func _on_preview_card_hovered(card: Card3D) -> void:
	if CardData.get_active_effects(card.card_data).is_empty():
		return
	_ensure_effect_overview()
	if _effect_overview != null:
		_effect_overview.show_for_card(card)


func _on_preview_card_unhovered(card: Card3D) -> void:
	if _effect_overview != null:
		_effect_overview.hide_overview(card)

func _upgrade_attack() -> void:
	if not _can_buy_upgrade():
		return

	var cost := CardUpgradeManager.get_stat_upgrade_cost(selected_card_id, attack_cost)
	if not GameCurrency.spend_coins(cost):
		ui.show_message("Nicht genug Soul Coins")
		ui.refresh_balance()
		return

	CardUpgradeManager.add_attack(selected_card_id, 1)

	ui.refresh_balance()
	ui.set_selected_card(selected_card_id)
	ui.show_message("Angriff um 1 erhöht")

	_spawn_preview_card()

func _upgrade_health() -> void:
	if not _can_buy_upgrade():
		return

	var cost := CardUpgradeManager.get_stat_upgrade_cost(selected_card_id, health_cost)
	if not GameCurrency.spend_coins(cost):
		ui.show_message("Nicht genug Soul Coins")
		ui.refresh_balance()
		return

	CardUpgradeManager.add_health(selected_card_id, 1)

	ui.refresh_balance()
	ui.set_selected_card(selected_card_id)
	ui.show_message("Leben um 1 erhöht")

	_spawn_preview_card()


func _can_buy_upgrade() -> bool:
	return (
		is_operational() and not selected_card_id.is_empty()
		and CollectionManager.get_amount(selected_card_id) > 0
		and CardData.is_combat_card(CardDatabase.get_card(selected_card_id))
	)


func _roll_effect() -> void:
	if not _can_buy_upgrade():
		return

	if CardUpgradeManager.get_free_effect_slots(selected_card_id) <= 0:
		ui.show_message("Alle Effekt-Slots sind belegt")
		return

	var cost := CardUpgradeManager.get_effect_roll_cost(selected_card_id, effect_cost)
	if not GameCurrency.spend_coins(cost):
		ui.show_message("Nicht genug Soul Coins")
		ui.refresh_balance()
		return

	var effects: Array[Dictionary] = EffectDatabase.roll_effects()

	if effects.is_empty():
		CardUpgradeManager.record_effect_roll(selected_card_id, false)
		ui.show_message("Keinen Effekt erhalten")
		ui.refresh_balance()
		ui.set_selected_card(selected_card_id)
		return

	var effect: Dictionary = effects[0]

	if not CardUpgradeManager.add_effect(selected_card_id, effect):
		ui.show_message("Alle Effekt-Slots sind belegt")
		ui.refresh_balance()
		return

	CardUpgradeManager.record_effect_roll(selected_card_id, true)
	ui.refresh_balance()
	ui.set_selected_card(selected_card_id)
	ui.show_message(Localization.format_text("Neuer Effekt: %s", [Localization.localized_arg(str(effect.get("name")))]))

	_spawn_preview_card()
