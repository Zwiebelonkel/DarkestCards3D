extends "res://scripts/rooms/AngelDialogue.gd"
signal laughing_changed(enabled: bool)
## Scripted conversation without an extra clickable Satan interaction.
const SENTENCES: Array[String] = [
	"Wo warst du?",
	"Du warst draußen, oder?",
	"Mach es lieber nicht nochmal!",
	"Ach egal, scheiß doch, mach was du willst. Fuck you.",
]
var _sentence_index := 0

func _ready() -> void:
	dialog_name = "Satan"
	voice_pitch_offset = -16.0
	super._ready()

func _get_dialog_title() -> String:
	return "Satan"

func _get_sentences() -> Array[String]:
	return [_get_story_sentences()[_sentence_index]]

func _get_story_sentences() -> Array[String]:
	return SENTENCES

func _uses_laughing_text() -> bool:
	return _sentence_index == 3

func _update_click_area() -> void:
	if is_instance_valid(_laugh_audio) and is_instance_valid(actor):
		_laugh_audio.global_position = actor.global_position

func _update_pointer_hover() -> void:
	pass

func continue_dialog() -> void:
	if not _open or _closing:
		return
	if _is_typing() or _sentence_index + 1 >= _get_story_sentences().size():
		super.continue_dialog()
		return
	_sentence_index += 1
	if _sentence_index == 3:
		laughing_changed.emit(true)
	_message = _get_story_sentences()[_sentence_index]
	_text_finished = false
	_typing_characters = 0.0
	_refresh_body_text()
	_body_label.visible_characters = 0
	_layout_modal()
	_sync_dialog_audio()

func close_dialog() -> void:
	laughing_changed.emit(false)
	super.close_dialog()

func _exit_tree() -> void:
	laughing_changed.emit(false)
	super._exit_tree()

func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER]:
		continue_dialog()
		get_viewport().set_input_as_handled()
		return
	super._input(event)
