extends Node3D
class_name PackShopMachine

const PACK_TYPES := {
	"basic": {
		"name": "BASIC PACK",
		"cost": 5,
		"card_count": 5,
		"description": "Normal cards. Cheap and solid."
	},
	"rare": {
		"name": "RARE PACK",
		"cost": 15,
		"card_count": 7,
		"description": "More cards. Better rare chance."
	},
	"god": {
		"name": "GOD PACK",
		"cost": 35,
		"card_count": 10,
		"description": "Expensive. Big reveal energy."
	}
}

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
	if pack_opening_screen == null:
		ui.show_message("Pack screen missing")
		_play_error()
		return

	if not PACK_TYPES.has(pack_id):
		ui.show_message("Unknown pack")
		_play_error()
		return

	var data: Dictionary = PACK_TYPES[pack_id]

	if pack_opening_screen.buy_pack(pack_id, data):
		ui.refresh_balance()
		ui.show_message(str(data.get("name", "PACK")) + " BOUGHT")
		ui.set_buy_locked(true)
		_play_buy()
	else:
		ui.refresh_balance()
		ui.show_message("BUY FAILED")
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
	ui.show_message("READY")
