extends RefCounted
## A one-pixel contour around the actual controls, not their labels or rows.

const SLIDER_ICONS := [&"grabber", &"grabber_highlight", &"grabber_disabled"]
const SLIDER_STYLES := [&"slider", &"grabber_area", &"grabber_area_highlight"]
const CHECKBOX_ICONS := [
	&"checked", &"unchecked", &"checked_disabled", &"unchecked_disabled",
	&"radio_checked", &"radio_unchecked", &"radio_checked_disabled", &"radio_unchecked_disabled",
]
const CHECK_BUTTON_ICONS := [
	&"on", &"off", &"on_disabled", &"off_disabled",
	&"on_mirrored", &"off_mirrored", &"on_disabled_mirrored", &"off_disabled_mirrored",
]


static func apply_to(root: Node) -> void:
	if root is Slider:
		_outline_slider(root as Slider)
	elif root is CheckBox:
		_outline_icons(root as Control, CHECKBOX_ICONS)
	elif root is CheckButton:
		_outline_icons(root as Control, CHECK_BUTTON_ICONS)
	for child in root.get_children():
		apply_to(child)


static func _outline_slider(slider: Slider) -> void:
	for style_name: StringName in SLIDER_STYLES:
		var original := slider.get_theme_stylebox(style_name)
		if original is StyleBoxFlat:
			var outlined := original.duplicate() as StyleBoxFlat
			outlined.set_border_width_all(1)
			outlined.border_color = Color.WHITE
			slider.add_theme_stylebox_override(style_name, outlined)
	_outline_icons(slider, SLIDER_ICONS)


static func _outline_icons(control: Control, icon_names: Array) -> void:
	for icon_name: StringName in icon_names:
		if not control.has_theme_icon(icon_name):
			continue
		var texture := control.get_theme_icon(icon_name)
		var source := texture.get_image()
		if source == null or source.is_empty():
			continue
		var outlined := source.duplicate() as Image
		outlined.convert(Image.FORMAT_RGBA8)
		# Draw inside the original silhouette. Texture size, control minimum size,
		# the checkmark and the theme's hover/disabled fill remain unchanged.
		for y in source.get_height():
			for x in source.get_width():
				var color := source.get_pixel(x, y)
				if color.a > 0.0 and _is_edge(source, x, y):
					outlined.set_pixel(x, y, Color(1.0, 1.0, 1.0, _edge_coverage(source, x, y)))
		control.add_theme_icon_override(icon_name, ImageTexture.create_from_image(outlined))


static func _is_edge(source: Image, x: int, y: int) -> bool:
	for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var neighbor := Vector2i(x, y) + offset
		if (
			neighbor.x < 0 or neighbor.x >= source.get_width()
			or neighbor.y < 0 or neighbor.y >= source.get_height()
			or source.get_pixel(neighbor.x, neighbor.y).a == 0.0
		):
			return true
	return false


static func _edge_coverage(source: Image, x: int, y: int) -> float:
	# Godot's unchecked/disabled icons use translucent fills. Normalize only
	# the contour to white while retaining their antialiased outer corners.
	var nearby_alpha := 0.0
	for sample_y in range(maxi(0, y - 1), mini(source.get_height(), y + 2)):
		for sample_x in range(maxi(0, x - 1), mini(source.get_width(), x + 2)):
			nearby_alpha = maxf(nearby_alpha, source.get_pixel(sample_x, sample_y).a)
	return source.get_pixel(x, y).a / nearby_alpha
