extends Node

const BLOOD := preload("res://scenes/ui/BloodOverlay.tscn")
var failures := 0
var checks := 0
var viewport: SubViewport
var overlay
var lens: ShaderMaterial
var pixel: ShaderMaterial


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	failures += 0 if condition else 1
	print(("PASS " if condition else "FAIL ") + message)


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	viewport = SubViewport.new()
	viewport.size = Vector2i(400, 240)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var background := CanvasLayer.new()
	background.layer = -1
	viewport.add_child(background)
	var fill := ColorRect.new()
	fill.color = Color(0.26, 0.28, 0.3)
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_child(fill)
	overlay = BLOOD.instantiate()
	viewport.add_child(overlay)
	var other = BLOOD.instantiate()
	viewport.add_child(other)
	check(not overlay.active and not overlay.blood_rect.visible, "idle overlay is invisible and costs no full-screen draw")
	check(overlay._material != other._material, "each overlay has independent animation and shader settings")
	check(overlay.duration == 9.0 and overlay.hold_seconds == 0.9, "blood stays for nine seconds with an initial hold")
	check(overlay.blood_rect.mouse_filter == Control.MOUSE_FILTER_IGNORE, "blood never captures mouse input")
	overlay.play(0.5)
	await get_tree().create_timer(0.27).timeout
	var progress := float(overlay._material.get_shader_parameter("fade_progress"))
	check(progress > 0.0 and progress < 1.0 and overlay.active and not other.active, "blood retreats and fades gradually without affecting another overlay")
	get_tree().paused = true
	await get_tree().create_timer(0.1, true).timeout
	check(is_equal_approx(progress, float(overlay._material.get_shader_parameter("fade_progress"))), "offline pause freezes the blood animation")
	get_tree().paused = false
	await overlay.finished
	check(not overlay.active and not overlay.blood_rect.visible, "natural completion fully hides the blood")
	overlay.play()
	var old_tween: Tween = overlay._tween
	overlay.play()
	check(not old_tween.is_running() and old_tween != overlay._tween and overlay.active, "another hit replaces the previous animation")
	overlay.clear()
	check(not overlay.active and float(overlay._material.get_shader_parameter("fade_progress")) == 1.0,
		"cancellation removes the blood completely")
	other.queue_free()
	if DisplayServer.get_name() != "headless":
		await _check_render()
	viewport.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("BLOOD_OVERLAY_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _check_render() -> void:
	# Reuse the exact authored passes and screen copies from the real hub.
	var source := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	var camera := source.get_node("CameraPivot/CameraTilt/Camera3D")
	var lens_layer := camera.get_node("CanvasLayer").duplicate() as CanvasLayer
	var pixel_layer := camera.get_node("CanvasLayer2").duplicate() as CanvasLayer
	source.free()
	viewport.add_child(lens_layer)
	viewport.add_child(pixel_layer)
	lens = lens_layer.get_node("DirtyLensRect").material.duplicate() as ShaderMaterial
	lens_layer.get_node("DirtyLensRect").material = lens
	pixel = pixel_layer.get_node("ColorRect").material.duplicate() as ShaderMaterial
	pixel_layer.get_node("ColorRect").material = pixel
	for key in ["scratch_strength", "dirt_strength", "flicker_strength", "vignette_strength", "distortion_strength", "blur_strength"]:
		lens.set_shader_parameter(key, 0.0)
	for key in ["chrom_aberration", "vignette_strength", "grain_strength", "tint_strength"]:
		pixel.set_shader_parameter(key, 0.0)
	for key in ["exposure", "contrast", "saturation"]:
		pixel.set_shader_parameter(key, 1.0)
	pixel.set_shader_parameter("enable_posterize", false)
	pixel.set_shader_parameter("pixel_factor", 6.0)
	check(overlay.layer < lens_layer.layer and lens_layer.layer < pixel_layer.layer
		and lens_layer.get_node("BloodScreenCopy").copy_mode == BackBufferCopy.COPY_MODE_VIEWPORT
		and pixel_layer.get_node("LensScreenCopy").copy_mode == BackBufferCopy.COPY_MODE_VIEWPORT,
		"render order copies blood into scratches and then copies both into pixelation")
	var baseline := await _image_at(1.0)
	var early := await _image_at(0.0)
	var late := await _image_at(0.55)
	var gone := await _image_at(1.0)
	early.save_png("res://blood-border-early.png")
	late.save_png("res://blood-border-late.png")
	var early_stats := _blood_stats(early, baseline)
	var late_stats := _blood_stats(late, baseline)
	check(early_stats.x > 0.025 and early_stats.y > 400, "the rendered blood visibly colors the edges through both post-processing passes")
	check(_rim_is_covered(early, baseline), "the blood continuously covers all four edges without gaps")
	var edge_color := early.get_pixel(early.get_width() / 2, 0)
	check(edge_color.g > baseline.get_pixel(baseline.get_width() / 2, 0).g * 0.45,
		"the blood rim remains translucent and subtle")
	check(_difference(early, baseline, true) < 0.003, "the middle of the screen stays clear")
	check(late_stats.x < early_stats.x * 0.7 and late_stats.y < early_stats.y * 0.7,
		"later blood is both fainter and covers a smaller region near the edges")
	check(_difference(gone, baseline) < 0.001, "fully faded blood restores the exact original image")
	var pixelated := await _image_at(0.0)
	pixel.set_shader_parameter("enable_pixelate", false)
	var smooth := await _image_at(0.0)
	check(_difference(pixelated, smooth) > 0.0002, "pixelation changes the blood itself over a uniform background")
	lens.set_shader_parameter("scratch_strength", 0.8)
	var scratched := await _image_at(0.0)
	check(_difference(scratched, smooth) > 0.003, "the scratch pass remains visible above the blood")
	overlay.clear()


func _image_at(progress: float) -> Image:
	overlay.play()
	overlay._tween.pause()
	overlay._material.set_shader_parameter("pattern_seed", 0.0)
	overlay._material.set_shader_parameter("fade_progress", progress)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _blood_stats(picture: Image, baseline: Image) -> Vector2:
	var redness := 0.0
	var covered := 0.0
	var samples := 0
	for y in range(0, picture.get_height(), 2):
		for x in range(0, picture.get_width(), 2):
			var color := picture.get_pixel(x, y)
			var before := baseline.get_pixel(x, y)
			var gain := (color.r - maxf(color.g, color.b)) - (before.r - maxf(before.g, before.b))
			redness += maxf(0.0, gain)
			covered += 1.0 if gain > 0.025 else 0.0
			samples += 1
	return Vector2(redness / samples, covered)


func _rim_is_covered(picture: Image, baseline: Image) -> bool:
	var points: Array[Vector2i] = []
	for x in range(0, picture.get_width(), 4):
		points.append(Vector2i(x, 0))
		points.append(Vector2i(x, picture.get_height() - 1))
	for y in range(0, picture.get_height(), 4):
		points.append(Vector2i(0, y))
		points.append(Vector2i(picture.get_width() - 1, y))
	for point in points:
		var color := picture.get_pixelv(point)
		var before := baseline.get_pixelv(point)
		var gain := (color.r - maxf(color.g, color.b)) - (before.r - maxf(before.g, before.b))
		if gain < 0.04:
			return false
	return true


func _difference(a: Image, b: Image, center_only: bool = false) -> float:
	var result := 0.0
	var samples := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			if center_only and (x < 150 or x >= 250 or y < 85 or y >= 155):
				continue
			var delta := a.get_pixel(x, y) - b.get_pixel(x, y)
			result += absf(delta.r) + absf(delta.g) + absf(delta.b)
			samples += 1
	return result / maxf(samples, 1)
