extends "res://scripts/main/SatanHolyWaterDialogue.gd"
## The same return cinematic and voice, with an independent cross conversation.

const CRUCIFIX_SENTENCES: Array[String] = [
	"Ein Kreuz? Ernsthaft?",
	"Du glaubst doch nicht, dass dich das hier vor mir schützt.",
	"Steck es weg. Heb es dir für später auf.",
	"Und wehe, du nagelst mir das Ding an die Wand. Hahaha!",
]


func _get_story_sentences() -> Array[String]:
	return CRUCIFIX_SENTENCES
