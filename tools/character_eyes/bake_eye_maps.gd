extends Node
## One-shot baker. The saved maps are normal textures, including in exports.

const SHEETS := {
	"satan": ["satan", "satanHover", "satanLaught", "satanDeath", "satanPanic", "satanKill"],
	"angel": ["angel", "angelHover"],
	"baclmarketDealer": ["blackmarketDealer", "dealerHover"],
	"jester": ["jester", "jesterHover"],
	"prisoner": ["prisoner", "prisonerHover"],
}


func _ready() -> void:
	GameCurrency.set_process(false)
	for folder: String in SHEETS:
		for sheet: String in SHEETS[folder]:
			var path := "res://assets/characters/" + folder + "/" + sheet
			# Read authored pixels in this editor-only baker, before GPU compression.
			var source := Image.load_from_file(path + ".png")
			var mask := Image.create(source.get_width(), source.get_height(), false, Image.FORMAT_RGB8)
			mask.fill(Color.BLACK)
			for y in range(source.get_height()):
				for x in range(source.get_width()):
					var color := source.get_pixel(x, y)
					if color.a <= 0.0 or maxf(color.r, maxf(color.g, color.b)) <= 0.0:
						continue
					# All visible, nonblack artwork emits in its original color.
					mask.set_pixel(x, y, color)
			var result := ResourceSaver.save(ImageTexture.create_from_image(mask), path + "_eyes.res", ResourceSaver.FLAG_COMPRESS)
			if result != OK:
				push_error("Could not save eye map: " + path)
				get_tree().quit(1)
				return
		var base := "res://assets/characters/" + folder + "/" + str(SHEETS[folder][0])
		var material := StandardMaterial3D.new()
		material.resource_name = "Character emission: " + folder
		material.set_meta(&"character_eye_glow", true)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		material.roughness = 1.0
		material.vertex_color_use_as_albedo = true
		material.albedo_texture = load(base + ".png")
		material.emission_enabled = true
		material.emission = Color.WHITE
		material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		material.emission_energy_multiplier = 3.0
		material.emission_texture = load(base + "_eyes.res")
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.billboard_keep_scale = true
		if ResourceSaver.save(material, "res://assets/characters/" + folder + "/eye_glow.tres") != OK:
			get_tree().quit(1)
			return
	print("CHARACTER_EYE_MAPS_BAKED")
	get_tree().quit()
