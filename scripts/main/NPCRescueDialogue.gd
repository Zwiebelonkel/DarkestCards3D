extends "res://scripts/rooms/AngelDialogue.gd"
## Scripted first-visit greetings with each NPC's usual voice and small dialog.

const GREETINGS := {
	"angel": "Du hast mich befreit! Versuch mal, deine Karten upzugraden. Ich habe dir die Upgrade-Maschine freigeschaltet.",
	"dealer": "Ja, du hast mich befreit. Nur damit wir uns verstehen: Umsonst kriegst du hier trotzdem nichts. Auf der Tafel gibt es jeden Tag neue Karten. Bezahlt wird in Soul Coins. Auch von dir.",
	"jester": "Ich brauche zwei Karten: ein Küken und Harald.",
	"prisoner": "*Lacht* *Furzt* *Lacht*",
}
const TITLES := {"angel": "Der Engel", "dealer": "Der Händler", "jester": "Der Jester", "prisoner": "Der Gefangene"}
const VOICE_PITCHES := {"angel": 0.0, "dealer": -16.0, "jester": 6.0, "prisoner": 3.0}

const FART_SOUND := preload("res://assets/sounds/SFX/fart.mp3")
const SENTENCE_END_SOUND := preload("res://assets/sounds/SFX/sentenceEnd.mp3")

var _fart_audio: AudioStreamPlayer3D
var _sentence_end_audio: AudioStreamPlayer3D
var _word_characters_checked := 0
var npc_id := "angel"


func _ready() -> void:
	dialog_name = npc_id.capitalize()
	voice_pitch_offset = VOICE_PITCHES.get(npc_id, 0.0)
	super._ready()
	if npc_id == "jester":
		_sentence_end_audio = AudioStreamPlayer3D.new()
		_sentence_end_audio.name = "SentenceEndSound"
		_sentence_end_audio.stream = SENTENCE_END_SOUND
		_sentence_end_audio.bus = &"SFX"
		_sentence_end_audio.volume_db = -8.0
		_sentence_end_audio.unit_size = 5.0
		_sentence_end_audio.max_distance = 20.0
		add_child(_sentence_end_audio)
	if npc_id == "prisoner":
		_fart_audio = AudioStreamPlayer3D.new()
		_fart_audio.stream = FART_SOUND
		_fart_audio.bus = &"SFX"
		_fart_audio.volume_db = -3.0
		_fart_audio.unit_size = 5.0
		_fart_audio.max_distance = 20.0
		add_child(_fart_audio)


func _get_dialog_title() -> String:
	return TITLES.get(npc_id, "")


func _get_sentences() -> Array[String]:
	return [str(GREETINGS.get(npc_id, ""))]


func _update_click_area() -> void:
	# Automatic conversation without a second world click target.
	if is_instance_valid(_laugh_audio) and is_instance_valid(actor):
		_laugh_audio.global_position = actor.global_position


func _update_pointer_hover() -> void:
	pass


func open_dialog() -> bool:
	_word_characters_checked = 0
	var opened := super.open_dialog()
	if opened and is_instance_valid(_fart_audio):
		_fart_audio.global_position = actor.global_position
		_fart_audio.play()
	return opened


func _advance_dialog_text(delta: float) -> void:
	super._advance_dialog_text(delta)
	_play_completed_word_sound()


func continue_dialog() -> void:
	var was_typing := _is_typing()
	super.continue_dialog()
	if was_typing:
		_play_completed_word_sound()


func _play_completed_word_sound() -> void:
	if not is_instance_valid(_sentence_end_audio) or not _open or _closing:
		return
	var text := _body_label.get_parsed_text()
	var shown := text.length() if _body_label.visible_characters < 0 else mini(_body_label.visible_characters, text.length())
	var completed_word := false
	for index in range(_word_characters_checked, shown):
		if not text[index].strip_edges().is_empty() and (index + 1 == text.length() or text[index + 1].strip_edges().is_empty()):
			completed_word = true
	_word_characters_checked = shown
	# One cue per visible word boundary. A reveal click/long frame plays once
	# rather than stacking all newly revealed words at the same instant.
	if completed_word:
		_sentence_end_audio.global_position = actor.global_position
		_sentence_end_audio.play()


func close_dialog() -> void:
	if is_instance_valid(_sentence_end_audio):
		_sentence_end_audio.stop()
	if is_instance_valid(_fart_audio):
		_fart_audio.stop()
	super.close_dialog()


func _exit_tree() -> void:
	if is_instance_valid(_sentence_end_audio):
		_sentence_end_audio.stop()
	super._exit_tree()
