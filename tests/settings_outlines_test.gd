extends Node

var checks := 0
var failures := 0
var viewport: SubViewport
var settings: SettingsMenu


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + description)
	if not condition:
		failures += 1


func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _run() -> void:
	if not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Use the isolated test runner to protect real player saves.")
		get_tree().quit(1)
		return
	SettingsManager.set_fullscreen(false)
	SettingsManager.set_damage_numbers_enabled(true)
	SettingsManager.set_turn_arrows_enabled(true)
	SettingsManager.set_satan_voice_enabled(false)
	SettingsManager.set_satan_voice_pitch(0.62)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	settings = preload("res://scenes/ui/SettingsMenu.tscn").instantiate() as SettingsMenu
	viewport.add_child(settings)
	settings.open()
	await settle()
	await capture("presentation-options")
	var sliders := settings.find_children("*", "Slider", true, false)
	var checkboxes := settings.find_children("*", "CheckBox", true, false)
	check(sliders.size() == 7 and checkboxes.size() == 4, "All seven settings sliders and all four checkboxes are covered")
	for slider: Slider in sliders:
		var outlined := true
		for style_name in ["slider", "grabber_area", "grabber_area_highlight"]:
			var style := slider.get_theme_stylebox(style_name) as StyleBoxFlat
			outlined = outlined and style != null and style.border_color == Color.WHITE
			if style != null:
				for side in range(4):
					outlined = outlined and style.get_border_width(side) == 1
		for icon_name in ["grabber", "grabber_highlight", "grabber_disabled"]:
			outlined = outlined and slider.has_theme_icon_override(icon_name)
		check(outlined, "%s has one-pixel white track borders and all three outlined knob states" % slider.name)
		check(slider.size.x - slider.get_theme_icon("grabber").get_width() >= 120.0, "%s has at least 120 pixels of usable track at 1280-pixel viewport width" % slider.name)
	var reference := CheckBox.new()
	viewport.add_child(reference)
	reference.hide()
	for checkbox: CheckBox in checkboxes:
		var same_dimensions := true
		var preserved_interior := true
		for icon_name in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
			var original := reference.get_theme_icon(icon_name)
			var outlined := checkbox.get_theme_icon(icon_name)
			same_dimensions = same_dimensions and outlined.get_size() == original.get_size()
			var original_image := original.get_image()
			var outlined_image := outlined.get_image()
			var point := Vector2i(original.get_size() * 0.5)
			preserved_interior = preserved_interior and original_image.get_pixelv(point).is_equal_approx(outlined_image.get_pixelv(point))
		check(same_dimensions and preserved_interior, "%s retains icon dimensions and checkmark/fill pixels in checked, unchecked and disabled states" % checkbox.name)
		check(not checkbox.has_theme_stylebox_override("normal") and not checkbox.has_theme_stylebox_override("hover"), "%s has no added border around its text row" % checkbox.name)
	await click(settings.fullscreen_check_box)
	check(settings.fullscreen_check_box.button_pressed and SettingsManager.fullscreen, "Actual fullscreen checkbox click still enables fullscreen")
	await capture("top-checked")
	await click(settings.fullscreen_check_box)
	check(not SettingsManager.fullscreen, "Second actual fullscreen checkbox click still disables fullscreen")
	await move_slider(settings.master_slider, 0.65)
	check(absf(SettingsManager.master_volume - 0.65) < 0.035, "Dragging the master knob still changes and saves volume")
	await capture("top-unchecked")
	settings.master_slider.editable = false
	settings.fullscreen_check_box.disabled = true
	var disabled_value := settings.master_slider.value
	await move_slider(settings.master_slider, 0.15)
	await click(settings.fullscreen_check_box)
	check(settings.master_slider.value == disabled_value and not SettingsManager.fullscreen, "Disabled outlined controls ignore mouse input")
	await capture("top-disabled")
	settings.master_slider.editable = true
	settings.fullscreen_check_box.disabled = false
	await click(settings.satan_voice_enabled_check_box)
	check(SettingsManager.satan_voice_enabled, "Actual voice checkbox click still updates the setting")
	check(is_equal_approx(settings.satan_voice_pitch_slider.min_value, 0.35) and is_equal_approx(settings.satan_voice_pitch_slider.max_value, 0.9) and is_equal_approx(settings.satan_voice_pitch_slider.value, 0.62), "Pitch layout retains the original range and loaded setting")
	await move_slider(settings.satan_voice_pitch_slider, 0.75)
	check(absf(SettingsManager.satan_voice_pitch - 0.76) < 0.015 and settings.satan_voice_pitch_value.text == "%d%%" % roundi(SettingsManager.satan_voice_pitch * 100.0), "Dragging the visible pitch track updates both the setting and percentage")
	await move_slider(settings.satan_voice_volume_slider, 0.4)
	check(absf(SettingsManager.satan_voice_volume - 0.4) < 0.05, "Nested voice volume slider remains draggable after scrolling")
	await capture("voice")
	settings.close()
	settings.queue_free()
	reference.queue_free()
	await settle()
	print("SETTINGS_OUTLINES_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func make_visible(control: Control) -> void:
	var scroll := settings.get_node("CenterContainer/PanelContainer/ScrollContainer") as ScrollContainer
	scroll.ensure_control_visible(control)
	await settle()


func click(button: Button) -> void:
	await make_visible(button)
	var point := button.get_global_rect().get_center()
	await mouse_motion(point)
	await mouse_button(point, true)
	await mouse_button(point, false)


func move_slider(slider: HSlider, ratio: float) -> void:
	await make_visible(slider)
	var rect := slider.get_global_rect()
	var knob_width := slider.get_theme_icon("grabber").get_width()
	var current_ratio := (slider.value - slider.min_value) / (slider.max_value - slider.min_value)
	var start := Vector2(rect.position.x + knob_width * 0.5 + (rect.size.x - knob_width) * current_ratio, rect.get_center().y)
	var end := Vector2(rect.position.x + knob_width * 0.5 + (rect.size.x - knob_width) * ratio, start.y)
	await mouse_motion(start)
	await mouse_button(start, true)
	await mouse_motion(end, end - start, true)
	await mouse_button(end, false)


func mouse_motion(point: Vector2, relative := Vector2.ZERO, dragging := false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if dragging else 0
	viewport.push_input(event, true)
	await settle()


func mouse_button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	viewport.push_input(event, true)
	await settle()


func capture(stage: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://settings-outlines-%s.png" % stage)
