extends Node
## CSV-backed presentation only. Gameplay IDs, saved data and network state
## remain canonical regardless of the local player's selected language.

signal locale_changed

const SUPPORTED_LOCALES := ["de", "en", "es", "fr", "pl"]
const LANGUAGE_NAMES := {"de": "Deutsch", "en": "English", "es": "Español", "fr": "Français", "pl": "Polski"}
const DEFAULT_LOCALE := "de"
const FONT := preload("res://fonts/VCR_OSD_MONO_1.001.ttf")
const MESSAGE_CACHE_LIMIT := 1024

var _locale := DEFAULT_LOCALE
var _formatted_sources: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The original pixel font lacks œ and several Polish letters. Godot's
	# bundled fallback covers them on every export, without a system font.
	var pixel_font: Font = FONT
	pixel_font.fallbacks = [ThemeDB.fallback_font]
	TranslationServer.set_locale(_locale)


func get_locale() -> String:
	return _locale


func set_locale(value: String) -> void:
	var requested := value.replace("-", "_").get_slice("_", 0).to_lower()
	if requested not in SUPPORTED_LOCALES:
		requested = "en"
	if _locale == requested and TranslationServer.get_locale() == requested:
		return
	_locale = requested
	TranslationServer.set_locale(_locale)
	_refresh_formatted_labels(get_tree().root)
	locale_changed.emit()


func text(source: String) -> String:
	if source.is_empty():
		return source
	# Status messages can outlive the language in which they were generated.
	# Reformat those from their template without replaying a gameplay action.
	if _formatted_sources.has(source):
		var original: Dictionary = _formatted_sources[source]
		var updated := format_text(original["source"], original["values"])
		return updated.to_upper() if original.get("uppercase", false) else updated
	return str(TranslationServer.translate(source))


func format_text(source: String, values: Array) -> String:
	var result := _render(source, values)
	if not values.is_empty():
		if _formatted_sources.size() >= MESSAGE_CACHE_LIMIT and not _formatted_sources.has(result):
			_formatted_sources.erase(_formatted_sources.keys()[0])
		_formatted_sources[result] = {"source": source, "values": values.duplicate(true)}
		if result.to_upper() != result:
			_formatted_sources[result.to_upper()] = {"source": source, "values": values.duplicate(true), "uppercase": true}
	return result


func _refresh_formatted_labels(node: Node) -> void:
	# Native Godot labels already update literal CSV keys. Formatted messages
	# additionally need their original template and arguments to be reapplied.
	# This walk happens only on an explicit language switch.
	if node.auto_translate_mode != Node.AUTO_TRANSLATE_MODE_DISABLED:
		# BaseButton also includes textless controls such as TurnArrows.ArrowButton.
		if node is Label or node is Label3D or node is RichTextLabel or node is Button:
			if _formatted_sources.has(node.text):
				node.text = text(node.text)
		if node is Control and _formatted_sources.has(node.tooltip_text):
			node.tooltip_text = text(node.tooltip_text)
		if node is Label3D and node.has_meta("localization_text_bounds"):
			var bounds: Vector2 = node.get_meta("localization_text_bounds")
			fit_text_3d(node, bounds.x, bounds.y)
		for child in node.get_children():
			_refresh_formatted_labels(child)


func localized_arg(source: String) -> Dictionary:
	# Mark authored names explicitly; unmarked Steam names and user text are
	# inserted verbatim even if they happen to match a translation key.
	return {"localization_source": source}


func _render(source: String, values: Array) -> String:
	var rendered: Array = []
	for value: Variant in values:
		if value is Dictionary and value.has("localization_source"):
			rendered.append(str(TranslationServer.translate(str(value["localization_source"]))))
		else:
			rendered.append(value)
	return str(TranslationServer.translate(source)) % rendered


func rarity_name(rarity: String, uppercase: bool = false) -> String:
	var source := str({"common": "COMMON", "uncommon": "UNCOMMON", "rare": "RARE", "epic": "EPIC", "legendary": "LEGENDARY", "mythic": "MYTHIC", "exotic": "EXOTIC", "secret": "SECRET"}.get(rarity.to_lower(), rarity))
	var translated := text(source)
	return translated.to_upper() if uppercase else translated.capitalize()


func decimal(value: float, digits: int = 2) -> String:
	var formatted := ("%." + str(clampi(digits, 0, 8)) + "f") % value
	return formatted if _locale == "en" else formatted.replace(".", ",")


func fit_text_3d(label: Label3D, width: float, height: float = 0.0) -> void:
	# Measure the rendered translation, including fallback glyphs, in the
	# existing local 3D surface. Restore the original size for shorter text.
	if not label.has_meta("localization_base_pixel_size"):
		label.set_meta("localization_base_pixel_size", label.pixel_size)
	label.set_meta("localization_text_bounds", Vector2(width, height))
	var base_size := float(label.get_meta("localization_base_pixel_size"))
	var lines := text(label.text).split("\n")
	var measured_width := 0.0
	for line: String in lines:
		measured_width = maxf(measured_width, label.font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x)
	measured_width *= base_size * absf(label.scale.x)
	var fit := minf(1.0, width / maxf(measured_width, 0.001))
	if height > 0.0:
		var measured_height := label.font.get_height(label.font_size) * lines.size() * base_size * absf(label.scale.y)
		fit = minf(fit, height / maxf(measured_height, 0.001))
	label.pixel_size = base_size * fit
