extends "res://scripts/main/SatanHolyWaterDialogue.gd"

const SHOTGUN_SENTENCES: Array[String] = [
	"Was zur Hölle?! Das tut weh!",
	"Bitte … schieß nicht nochmal!",
]


func _get_story_sentences() -> Array[String]:
	return SHOTGUN_SENTENCES


func _uses_laughing_text() -> bool:
	return false
