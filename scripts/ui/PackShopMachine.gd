extends Node3D
class_name PackShopMachine

const PACK_TYPES := PackDefinition.PACK_TYPES

@onready var pack_opening_screen: PackOpeningScreen = $PackOpeningScreen
@export var pack_shop_viewport: SubViewport
@export var screen_mesh: MeshInstance3D

@onready var ui: PackShopUI = $PackShopViewport/PackShopUI as PackShopUI
@onready var buy_sfx: AudioStreamPlayer3D = $BuySFX
@onready var error_sfx: AudioStreamPlayer3D = $ErrorSFX


func _ready() -> void:
	_setup_screen_material()
	_connect_ui()
	
	if pack_opening_screen:
		pack_opening_screen.pack_ready_for_next_purchase.connect(_on_pack_ready_for_next_purchase)

	ui.set_packs(PACK_TYPES)
	ui.refresh_balance()


func _setup_screen_material() -> void:
	if pack_shop_viewport == null:
		pack_shop_viewport = $PackShopViewport

	if screen_mesh == null:
		screen_mesh = $MachineModel/ScreenMesh

	pack_shop_viewport.disable_3d = true
	pack_shop_viewport.gui_disable_input = false
	pack_shop_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var tex := pack_shop_viewport.get_texture()

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.emission_enabled = true
	mat.emission_texture = tex
	mat.emission_energy_multiplier = 1.4
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	screen_mesh.set_surface_override_material(0, mat)


func _connect_ui() -> void:
	ui.pack_buy_pressed.connect(_on_pack_buy_pressed)


func _on_pack_buy_pressed(pack_id: String) -> void:
	if ui.locked:
		return

	if pack_opening_screen == null:
		ui.show_message("Pack-Öffnung fehlt")
		_play_error()
		return

	if not PACK_TYPES.has(pack_id):
		ui.show_message("Unbekanntes Pack")
		_play_error()
		return

	var data: Dictionary = PACK_TYPES[pack_id]
	if not PackDefinition.is_unlocked(pack_id, GameCurrency.get_level()):
		ui.refresh_balance()
		ui.show_message(PackDefinition.get_unlock_message(pack_id))
		_play_error()
		return

	var quantity := ui.get_purchase_quantity()
	# Payment emits coins_changed synchronously. Keep the chosen amount stable
	# until the entire purchase has either started or been rejected.
	ui.set_buy_locked(true)
	if pack_opening_screen.buy_pack(pack_id, data, quantity):
		ui.refresh_balance()
		if quantity > 1:
			ui.show_message(Localization.format_text("%d PACKS GEKAUFT · NACHEINANDER AUFREISSEN", [quantity]))
		else:
			ui.show_message(Localization.format_text("%s GEKAUFT · PACK AUFREISSEN", [Localization.localized_arg(str(data.get("name", "Pack")))]))
		_play_buy()
	else:
		ui.set_buy_locked(false)
		ui.refresh_balance()
		ui.show_message("Kauf fehlgeschlagen")
		_play_error()


func _play_buy() -> void:
	if buy_sfx:
		buy_sfx.play()


func _play_error() -> void:
	if error_sfx:
		error_sfx.play()
		
func _on_pack_ready_for_next_purchase() -> void:
	ui.set_buy_locked(false)
	ui.refresh_balance()
	ui.show_message("Bereit für das nächste Pack")
