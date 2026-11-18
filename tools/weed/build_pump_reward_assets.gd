extends Node
## Bake the story-item pixel icons and compile card, menu and group catalogs.

func _ready() -> void:
	var error := OK
	for icon: String in ["toilet_paper", "holy_water", "jester_eye", "crucifix"]:
		var image := Image.new()
		error = image.load_svg_from_string(FileAccess.get_file_as_string("res://assets/cards/images/" + icon + ".svg"))
		if error == OK:
			error = ResourceSaver.save(ImageTexture.create_from_image(image), "res://assets/cards/images/" + icon + ".res")
		if error != OK:
			push_error("Could not bake card icon: " + error_string(error))
			get_tree().quit(1)
			return
	for catalog: String in ["cards", "menus", "game"]:
		var csv := FileAccess.open("res://localization/" + catalog + ".csv", FileAccess.READ)
		var header := csv.get_csv_line()
		var translations: Array[Translation] = []
		for index in range(1, header.size()):
			var translation := Translation.new()
			translation.locale = header[index]
			translations.append(translation)
		while not csv.eof_reached():
			var row := csv.get_csv_line()
			if row.size() != header.size() or row[0].is_empty():
				continue
			for index in range(translations.size()):
				translations[index].add_message(row[0], row[index + 1])
		csv.close()
		for translation: Translation in translations:
			error = ResourceSaver.save(translation, "res://localization/%s.%s.translation" % [catalog, translation.locale])
			if error != OK:
				push_error("Could not compile localization: " + error_string(error))
				get_tree().quit(1)
				return
	print("PUMP_REWARD_ASSETS: PASS")
	get_tree().quit()
