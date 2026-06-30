extends Control
class_name PiskelTool

const PISKEL_URL := "https://www.piskelapp.com/p/create/sprite"
const SAVE_DIR := "user://piskel_assets"

@onready var status_label: Label = %StatusLabel
@onready var preview: TextureRect = %Preview
@onready var open_embedded_button: Button = %OpenEmbeddedButton
@onready var open_external_button: Button = %OpenExternalButton
@onready var import_button: Button = %ImportButton
@onready var close_embed_button: Button = %CloseEmbedButton
@onready var back_button: Button = %BackButton
@onready var file_dialog: FileDialog = %FileDialog

var _iframe_id := "piskel_embed_frame"
var _overlay_id := "piskel_embed_overlay"


func _ready() -> void:
	open_embedded_button.pressed.connect(_open_embedded_piskel)
	open_external_button.pressed.connect(_open_external_piskel)
	import_button.pressed.connect(_show_import_dialog)
	close_embed_button.pressed.connect(_close_embedded_piskel)
	back_button.pressed.connect(_go_back)
	file_dialog.file_selected.connect(_import_sprite)
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	_update_status("Piskel ist bereit. Im Web-Export wird Piskel als eingebettetes Overlay geöffnet; im Editor/Desktop öffnet sich Piskel extern.")


func _open_embedded_piskel() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(_build_embed_script(), true)
		_update_status("Piskel wurde eingebettet geöffnet. Exportiere dein Sprite in Piskel als PNG und importiere die Datei anschließend hier.")
		return

	_open_external_piskel()
	_update_status("Eingebettetes Piskel ist nur im Web-Export verfügbar. Piskel wurde stattdessen extern geöffnet.")


func _open_external_piskel() -> void:
	var err := OS.shell_open(PISKEL_URL)
	if err == OK:
		_update_status("Piskel wurde im Browser geöffnet. Exportiere dort ein PNG und importiere es danach hier.")
	else:
		_update_status("Piskel konnte nicht geöffnet werden. URL: %s" % PISKEL_URL)


func _show_import_dialog() -> void:
	file_dialog.popup_centered_ratio(0.75)


func _import_sprite(path: String) -> void:
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		_update_status("Die ausgewählte Datei konnte nicht als Bild geladen werden.")
		return

	var safe_name := path.get_file().get_basename().to_snake_case()
	if safe_name.is_empty():
		safe_name = "piskel_sprite"
	var target_path := "%s/%s.png" % [SAVE_DIR, safe_name]
	var save_err := image.save_png(target_path)
	if save_err != OK:
		_update_status("Sprite konnte nicht gespeichert werden: %s" % error_string(save_err))
		return

	preview.texture = ImageTexture.create_from_image(image)
	_update_status("Sprite importiert und gespeichert unter: %s" % ProjectSettings.globalize_path(target_path))


func _close_embedded_piskel() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(_build_close_script(), true)
	_update_status("Piskel-Overlay geschlossen.")


func _go_back() -> void:
	_close_embedded_piskel()
	get_tree().change_scene_to_file("res://scenes/main/MainMenu.tscn")


func _update_status(message: String) -> void:
	status_label.text = message


func _build_embed_script() -> String:
	return """
(function () {
	const overlayId = '%s';
	const iframeId = '%s';
	document.getElementById(overlayId)?.remove();
	const overlay = document.createElement('div');
	overlay.id = overlayId;
	overlay.style.cssText = 'position:fixed;inset:4vh 4vw;z-index:999999;background:#120d18;border:2px solid #9a1420;border-radius:14px;box-shadow:0 16px 70px rgba(0,0,0,.65);overflow:hidden;';
	const iframe = document.createElement('iframe');
	iframe.id = iframeId;
	iframe.src = '%s';
	iframe.allow = 'clipboard-read; clipboard-write; fullscreen';
	iframe.style.cssText = 'width:100%%;height:100%%;border:0;background:#1b1324;';
	overlay.appendChild(iframe);
	document.body.appendChild(overlay);
})();
""" % [_overlay_id, _iframe_id, PISKEL_URL]


func _build_close_script() -> String:
	return "document.getElementById('%s')?.remove();" % _overlay_id
