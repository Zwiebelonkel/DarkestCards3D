extends Node


func _ready() -> void:
	GameCurrency.set_process(false)
	for sheet: String in ["satanPanic", "satanKill"]:
		var path := "res://assets/characters/satan/" + sheet
		var source := Image.load_from_file(path + ".png")
		var mask := Image.create(source.get_width(), source.get_height(), false, Image.FORMAT_RGB8)
		mask.fill(Color.BLACK)
		for y in range(source.get_height()):
			for x in range(source.get_width()):
				var color := source.get_pixel(x, y)
				if color.a > 0 and maxf(color.r, maxf(color.g, color.b)) > 0:
					mask.set_pixel(x, y, color)
		if ResourceSaver.save(ImageTexture.create_from_image(mask), path + "_eyes.res", ResourceSaver.FLAG_COMPRESS) != OK:
			get_tree().quit(1)
			return
		print("%s: %dx%d, %d square frames" % [sheet, source.get_width(), source.get_height(), source.get_width() / source.get_height()])
	print("SHOTGUN_ASSETS: PASS")
	get_tree().quit()
