extends "res://scripts/main/SatanHolyWaterDialogue.gd"
## The existing story-item return camera, with the laugh on the final third line.

const SILVER_BULLET_SENTENCES: Array[String] = [
	"Was willst du mit dieser Kugel?",
	"Hä?",
	"Für deinen Arsch?",
]


func _get_story_sentences() -> Array[String]:
	return SILVER_BULLET_SENTENCES


func _uses_laughing_text() -> bool:
	return _sentence_index == 2
