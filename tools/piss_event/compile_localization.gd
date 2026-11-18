extends Node


func _ready() -> void:
	var csv := FileAccess.open("res://localization/game.csv", FileAccess.READ)
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
		if ResourceSaver.save(translation, "res://localization/game.%s.translation" % translation.locale) != OK:
			get_tree().quit(1)
			return
	print("PISS_LOCALIZATION: PASS")
	get_tree().quit()
