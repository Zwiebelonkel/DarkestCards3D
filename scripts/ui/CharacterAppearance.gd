extends RefCounted
class_name CharacterAppearance

const FACE_DIRECTORY := "res://assets/characters/player/faces"
const HAT_DIRECTORY := "res://assets/characters/player/hats"
const MOUTH_DIRECTORY := "res://assets/characters/player/mouths"
const DEFAULT := {"face": "1", "hat": "satan", "mouth": "", "eye_color": "ffffff"}
const FRAME_SIZE := Vector2i(64, 64)
const CACHE_LIMIT := 16
static var FACES: Dictionary = load_catalogue(FACE_DIRECTORY)
static var HATS: Dictionary = load_catalogue(HAT_DIRECTORY)
static var MOUTHS: Dictionary = load_catalogue(MOUTH_DIRECTORY)
static var _cache: Dictionary = {}


static func load_catalogue(directory: String) -> Dictionary:
	var result := {}
	# ResourceLoader returns logical image names in both the editor and PCKs,
	# where DirAccess would see imported .remap files instead of the images.
	var filenames := Array(ResourceLoader.list_directory(directory))
	filenames.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	for filename: String in filenames:
		if filename.get_extension().to_lower() not in ["png", "webp", "jpg", "jpeg", "svg", "bmp", "tga", "res", "tres"]:
			continue
		var texture := ResourceLoader.load(directory.path_join(filename)) as Texture2D
		if texture == null:
			continue
		if Vector2i(texture.get_size()) != FRAME_SIZE:
			push_warning("Character image must be 64x64; skipping " + directory.path_join(filename))
			continue
		var id := filename.get_basename()
		if not result.has(id):
			result[id] = texture
	return result


static func reload_catalogues() -> void:
	FACES = load_catalogue(FACE_DIRECTORY)
	HATS = load_catalogue(HAT_DIRECTORY)
	MOUTHS = load_catalogue(MOUTH_DIRECTORY)
	_cache.clear()


static func sanitize(value: Variant) -> Dictionary:
	var result: Dictionary = DEFAULT.duplicate()
	if not FACES.has(result["face"]):
		result["face"] = FACES.keys()[0] if not FACES.is_empty() else ""
	if not HATS.has(result["hat"]):
		result["hat"] = HATS.keys()[0] if not HATS.is_empty() else ""
	if not value is Dictionary:
		return result
	var face: Variant = value.get("face")
	var hat: Variant = value.get("hat")
	var mouth: Variant = value.get("mouth")
	var eye_color: Variant = value.get("eye_color")
	if face is String and FACES.has(face):
		result["face"] = face
	if hat is String and (hat.is_empty() or HATS.has(hat)):
		result["hat"] = hat
	# Empty, missing and removed mouth IDs all mean no mouth, including old saves.
	if mouth is String and MOUTHS.has(mouth):
		result["mouth"] = mouth
	# Only six RGB hex digits go over the wire; no alpha, paths or resources.
	if eye_color is String and eye_color.length() == 6 and eye_color.is_valid_hex_number(false):
		result["eye_color"] = eye_color.to_lower()
	return result


static func compose_image(value: Variant) -> Image:
	var appearance := sanitize(value)
	# Some render backends return the texture's backing image directly.
	# Never tint that shared source when another preview asks for a new color.
	var face: Image = FACES[appearance["face"]].get_image().duplicate() if FACES.has(appearance["face"]) else Image.create(64, 64, false, Image.FORMAT_RGBA8)
	face.convert(Image.FORMAT_RGBA8)
	var eye_color := Color.html(appearance["eye_color"])
	_tint_white_pixels(face, eye_color)
	if MOUTHS.has(appearance["mouth"]):
		var mouth: Image = MOUTHS[appearance["mouth"]].get_image().duplicate()
		mouth.convert(Image.FORMAT_RGBA8)
		_tint_white_pixels(mouth, eye_color)
		face.blend_rect(mouth, Rect2i(Vector2i.ZERO, FRAME_SIZE), Vector2i.ZERO)
	if HATS.has(appearance["hat"]):
		var hat: Image = HATS[appearance["hat"]].get_image().duplicate()
		hat.convert(Image.FORMAT_RGBA8)
		face.blend_rect(hat, Rect2i(Vector2i.ZERO, FRAME_SIZE), Vector2i.ZERO)
	return face


static func _tint_white_pixels(image: Image, color: Color) -> void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.0 and minf(pixel.r, minf(pixel.g, pixel.b)) > 0.9:
				image.set_pixel(x, y, Color(color, pixel.a))


static func resources(value: Variant) -> Dictionary:
	var appearance := sanitize(value)
	var key := "%s/%s/%s/%s" % [appearance["face"], appearance["hat"], appearance["mouth"], appearance["eye_color"]]
	if _cache.has(key):
		return _cache[key]
	var composite := compose_image(appearance)
	var glow := composite.duplicate() as Image
	for y in range(glow.get_height()):
		for x in range(glow.get_width()):
			var pixel := glow.get_pixel(x, y)
			if pixel.a <= 0.0 or maxf(pixel.r, maxf(pixel.g, pixel.b)) < 0.01:
				# Emission ignores alpha, so transparent mask pixels need black RGB.
				glow.set_pixel(x, y, Color(0, 0, 0, 0))
	var result := {
		"texture": ImageTexture.create_from_image(composite),
		"emission": ImageTexture.create_from_image(glow),
	}
	if _cache.size() >= CACHE_LIMIT:
		_cache.erase(_cache.keys()[0])
	_cache[key] = result
	return result
