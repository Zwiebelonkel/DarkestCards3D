extends "res://scripts/rooms/AngelDialogue.gd"
## Uses the shared NPC voice/typewriter without the Jester's sentence-end cue.

const SENTENCES: Array[String] = ["*Lacht*", "*Lacht*", "*Furzt*", "*Lacht*", "*Scheisst sich ein*"]
const FART_SOUND := preload("res://assets/sounds/SFX/fart.mp3")
# Jester uses +6; retain its syllable variation, shifted three semitones down.
const VOICE_PITCH_OFFSET := 3.0

var _sentence_index := 0
var _fart_audio: AudioStreamPlayer3D


func _ready() -> void:
	dialog_name = "Prisoner"
	voice_pitch_offset = VOICE_PITCH_OFFSET
	actor.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	super._ready()
	_fart_audio = AudioStreamPlayer3D.new()
	_fart_audio.name = "FartSound"
	_fart_audio.stream = FART_SOUND
	_fart_audio.bus = &"SFX"
	_fart_audio.volume_db = -3.0
	_fart_audio.unit_size = 5.0
	_fart_audio.max_distance = 20.0
	add_child(_fart_audio)


func _update_click_area() -> void:
	super._update_click_area()
	if is_instance_valid(npc_area) and is_instance_valid(actor) and is_inside_tree():
		# This prisoner stays in its authored pose; its hit box follows that
		# fixed sprite plane instead of turning toward the camera.
		npc_area.global_transform = actor.global_transform


func _get_sentences() -> Array[String]:
	# The shared controller chooses from this pool. A single current sentence
	# makes this conversation deterministic instead of picking a random line.
	return [SENTENCES[_sentence_index]]


func _get_dialog_title() -> String:
	return "Der Gefangene"


func open_dialog() -> bool:
	if not _can_open():
		return false
	_sentence_index = 0
	return super.open_dialog()


func continue_dialog() -> void:
	if not _open or _closing:
		return
	if _is_typing() or _sentence_index + 1 >= SENTENCES.size():
		super.continue_dialog()
		return
	_sentence_index += 1
	_message = SENTENCES[_sentence_index]
	_text_finished = false
	_typing_characters = 0.0
	_body_label.text = Localization.text(_message)
	_body_label.visible_characters = 0
	_layout_modal()
	_sync_dialog_audio()
	_fart_audio.stop()
	if _message in ["*Furzt*", "*Scheisst sich ein*"]:
		_fart_audio.global_position = actor.global_position
		_fart_audio.play()


func close_dialog() -> void:
	if is_instance_valid(_fart_audio):
		_fart_audio.stop()
	super.close_dialog()


func _exit_tree() -> void:
	if is_instance_valid(_fart_audio):
		_fart_audio.stop()
	super._exit_tree()
