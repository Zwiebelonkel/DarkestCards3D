extends Label3D
class_name TypewriterLabel3D

@export var characters_per_second := 35.0
@export var start_delay := 0.0
@export var auto_start := false

var _full_text := ""
var _is_typing := false


func _ready() -> void:
	_full_text = text
	
	if auto_start:
		play(text)


func play(new_text: String) -> void:
	_full_text = new_text
	text = ""
	_is_typing = true

	if start_delay > 0.0:
		await get_tree().create_timer(start_delay).timeout

	var delay := 1.0 / characters_per_second

	for i in range(_full_text.length()):
		if not _is_typing:
			return

		text += _full_text[i]
		await get_tree().create_timer(delay).timeout

	_is_typing = false


func skip() -> void:
	_is_typing = false
	text = _full_text


func clear_text() -> void:
	_is_typing = false
	_full_text = ""
	text = ""
