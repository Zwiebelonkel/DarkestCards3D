extends Node

const APPEARANCE := preload("res://scripts/ui/CharacterAppearance.gd")


func _ready() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://expected.json"))
	var passed: bool = APPEARANCE.FACES.size() == expected["faces"].size() and APPEARANCE.HATS.size() == expected["hats"].size() and APPEARANCE.MOUTHS.size() == expected["mouths"].size()
	for face: String in expected["faces"]:
		passed = passed and APPEARANCE.FACES.has(face)
	for hat: String in expected["hats"]:
		passed = passed and APPEARANCE.HATS.has(hat)
	for mouth: String in expected["mouths"]:
		passed = passed and APPEARANCE.MOUTHS.has(mouth)
	for face: String in APPEARANCE.FACES:
		for hat: String in APPEARANCE.HATS:
			for mouth: String in [""] + APPEARANCE.MOUTHS.keys():
				passed = passed and APPEARANCE.compose_image({"face": face, "hat": hat, "mouth": mouth}).get_size() == Vector2i(64, 64)
	print("CHARACTER_CATALOGUE_EXPORT: %s faces=%d hats=%d mouths=%d" % ["PASS" if passed else "FAIL", APPEARANCE.FACES.size(), APPEARANCE.HATS.size(), APPEARANCE.MOUTHS.size()])
	get_tree().quit(0 if passed else 1)
