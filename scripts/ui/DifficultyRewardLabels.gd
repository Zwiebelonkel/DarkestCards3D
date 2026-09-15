extends Node3D

const DIFFICULTIES := {
	"EasyButton": ["easy", "Easy"],
	"NormalButton": ["normal", "Normal"],
	"HardButton": ["hard", "Hard"],
	"InsaneButton": ["insane", "Insane"],
}
const FONT := preload("res://fonts/VCR_OSD_MONO_1.001.ttf")
var _caption: Label3D


func _ready() -> void:
	_caption = Label3D.new()
	_caption.font = FONT
	_caption.font_size = 44
	_caption.pixel_size = 0.002
	_caption.position = Vector3(0.0, -0.055, 1.46)
	_caption.rotation_degrees.x = -90.0
	_caption.modulate = Color("bdb3a3")
	_caption.outline_size = 0
	add_child(_caption)
	Localization.locale_changed.connect(refresh_labels)
	refresh_labels()


func refresh_labels() -> void:
	if is_instance_valid(_caption):
		_caption.text = Localization.text("Siegbelohnung · vor Boni")
	for node_name: String in DIFFICULTIES:
		var button := get_node_or_null(node_name) as Table3DButton
		if button == null:
			continue
		var difficulty: String = DIFFICULTIES[node_name][0]
		button.label_text = Localization.format_text("%s\n%s SC / %d XP", [
			Localization.localized_arg(DIFFICULTIES[node_name][1]),
			GameCurrency.format_coins(GameCurrency.get_match_coins("win", difficulty), true),
			GameCurrency.get_match_xp("win", difficulty),
		])
