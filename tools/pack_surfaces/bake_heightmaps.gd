extends Node

## Offline, deterministic maps. Runtime only samples these mipmapped resources.
const SIZE := 512
const OUTPUT := "res://assets/cards/pack/surfaces/"


func _ready() -> void:
	var grain := FastNoiseLite.new()
	grain.seed = 3817
	grain.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	grain.frequency = 0.115
	grain.fractal_octaves = 3
	grain.fractal_gain = 0.42
	_save_map("basic", grain.get_seamless_image(SIZE, SIZE, false, false, 0.15))

	var warped := FastNoiseLite.new()
	warped.seed = 7251
	warped.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	warped.frequency = 0.027
	warped.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	warped.fractal_octaves = 4
	warped.domain_warp_enabled = true
	warped.domain_warp_amplitude = 62.0
	warped.domain_warp_frequency = 0.018
	_save_map("ultra", warped.get_seamless_image(SIZE, SIZE, false, false, 0.15))

	var dust := FastNoiseLite.new()
	dust.seed = 9113
	dust.frequency = 0.085
	dust.fractal_octaves = 3
	var rng := RandomNumberGenerator.new()
	rng.seed = 88021
	var craters: Array[Vector3] = []
	for index in range(42):
		craters.append(Vector3(rng.randf_range(0.0, SIZE), rng.randf_range(0.0, SIZE), rng.randf_range(10.0, 46.0)))
	var lunar := Image.create(SIZE, SIZE, false, Image.FORMAT_L8)
	for y in range(SIZE):
		for x in range(SIZE):
			var height := 0.54 + dust.get_noise_2d(x, y) * 0.085
			for crater in craters:
				var dx := absf(x - crater.x)
				var dy := absf(y - crater.y)
				dx = minf(dx, SIZE - dx)
				dy = minf(dy, SIZE - dy)
				var distance := sqrt(dx * dx + dy * dy) / crater.z
				if distance < 1.3:
					var bowl := -0.31 * (1.0 - smoothstep(0.0, 0.91, distance))
					var rim := 0.18 * exp(-pow((distance - 0.94) / 0.13, 2.0))
					height += bowl + rim
			var value := clampf(height, 0.0, 1.0)
			lunar.set_pixel(x, y, Color(value, value, value))
	_save_map("god", lunar)
	print("PACK_HEIGHTMAP_BAKE: PASS")
	get_tree().quit()


func _save_map(pack_id: String, image: Image) -> void:
	image.convert(Image.FORMAT_L8)
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	texture.resource_name = pack_id + "_foil_height"
	var error := ResourceSaver.save(texture, OUTPUT + pack_id + "_height.res", ResourceSaver.FLAG_COMPRESS)
	if error != OK:
		push_error("Could not save " + pack_id + " height map: " + str(error))
		get_tree().quit(1)
	print("BAKED ", pack_id, " ", image.get_size(), " mipmaps=", image.get_mipmap_count())
