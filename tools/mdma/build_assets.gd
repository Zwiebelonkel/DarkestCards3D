extends Node
## Bake export-ready voice resources without changing the supplied recordings.

func _ready() -> void:
	for name: String in ["pablo", "trinity", "steward", "hannah", "seperator"]:
		var stream := AudioStreamMP3.load_from_file("res://assets/sounds/SFX/names/%s.mp3" % name)
		if stream == null or ResourceSaver.save(stream, "res://assets/sounds/SFX/names/%s.res" % name) != OK:
			get_tree().quit(1)
			return
	var image := Image.new()
	if image.load_svg_from_string(FileAccess.get_file_as_string("res://assets/cards/images/silver_bullet.svg")) != OK or ResourceSaver.save(ImageTexture.create_from_image(image), "res://assets/cards/images/silver_bullet.res") != OK:
		get_tree().quit(1)
		return
	for catalog: String in ["menus", "cards", "game"]:
		if not _compile_catalog(catalog):
			get_tree().quit(1)
			return
	print("MDMA_ASSETS: PASS")
	get_tree().quit()


func _compile_catalog(catalog: String) -> bool:
	var csv := FileAccess.open("res://localization/%s.csv" % catalog, FileAccess.READ)
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
	for translation in translations:
		if ResourceSaver.save(translation, "res://localization/%s.%s.translation" % [catalog, translation.locale]) != OK:
			return false
	return true
