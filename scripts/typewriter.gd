extends Label3D
class_name TypewriterLabel3D

@export var characters_per_second := 35.0
@export var start_delay := 0.0
@export var auto_start := false

var _full_text := ""
var _is_typing := false
var _playback_id := 0


func _ready() -> void:
	_full_text = text
	
	if auto_start:
		play(text)


func play(new_text: String) -> void:
	# Network snapshots can update the same Card3D again while its description
	# is still being typed. A boolean alone cannot cancel the old coroutine:
	# the new call sets it back to true, so both calls would append characters.
	_playback_id += 1
	var playback_id := _playback_id
	_full_text = new_text
	text = ""
	_is_typing = true

	if start_delay > 0.0:
		await get_tree().create_timer(start_delay).timeout
		if playback_id != _playback_id or not _is_typing:
			return

	var delay := 1.0 / characters_per_second

	for i in range(new_text.length()):
		if playback_id != _playback_id or not _is_typing:
			return

		text += new_text[i]
		await get_tree().create_timer(delay).timeout

	# A replacement call can arrive while the final character's timer is
	# running. Do not let that superseded call stop the new animation.
	if playback_id != _playback_id:
		return
	_is_typing = false


func skip() -> void:
	_playback_id += 1
	_is_typing = false
	text = _full_text


func clear_text() -> void:
	_playback_id += 1
	_is_typing = false
	_full_text = ""
	text = ""
