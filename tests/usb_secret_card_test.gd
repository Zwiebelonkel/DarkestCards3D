extends Node3D
## Actual Card3D rendering, artwork reuse and private-room lifecycle.
## Run in an isolated project with Forward+ to also write the PNG evidence.

const CARD_SCENE := preload("res://scenes/table/Card3D.tscn")
const PROP_SECRETS := [
	{"id": "usb_stick", "room": "res://scenes/cards/UsbSecretRoom.tscn", "model": "res://assets/environments/props/usb/scene.gltf", "capture": "usb-secret"},
	{"id": "cigarettes", "room": "res://scenes/cards/CigarettesSecretRoom.tscn", "model": "res://assets/environments/props/cigarettes/cigs.glb", "capture": "cigarettes-secret"},
	{"id": "moewenmilch", "room": "res://scenes/cards/SeagullMilkSecretRoom.tscn", "model": "res://assets/environments/props/beer/energy.glb", "capture": "moewenmilch-secret"},
]

var checks := 0
var failures := 0
var viewport: SubViewport
var camera: Camera3D
var card: Card3D


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + description)
	if not condition:
		failures += 1
		push_error(description)


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/") or not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Use the isolated runner to protect player saves.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	var save_before := _save_bytes()
	var collection_before := CollectionManager.collection.duplicate(true)
	var secret_ids: Array[String] = []
	for secret: Dictionary in CardDatabase.get_all_cards():
		if secret.get("rarity") == "secret":
			secret_ids.append(str(secret.get("id")))
	secret_ids.sort()
	check(secret_ids == ["cigarettes", "moewenmilch", "usb_stick"], "only the three live 3D prop cards use the Secret rarity")
	check(CardDatabase.get_card("developer").get("rarity") == "exotic" and CardDatabase.get_card("missing_texture").get("rarity") == "exotic", "Developer and Missing Texture return to Exotic")
	_make_stage()
	for config: Dictionary in PROP_SECRETS:
		await _check_card(config)
	check(_save_bytes() == save_before and CollectionManager.collection == collection_before, "presentation and perspective changes preserve the collection and every profile save")
	viewport.queue_free()
	await _settle()
	_finish()


func _check_card(config: Dictionary) -> void:
	var card_id := str(config.id)
	var data := CardDatabase.get_card(card_id).duplicate(true)
	check(not data.is_empty(), card_id + " exists in the real card catalog")
	if data.is_empty():
		return
	check(data.get("rarity") == "secret" and data.get("artwork_scene") == config.room and str(data.get("image", "")).is_empty(), card_id + ": the Secret uses its 3D room instead of an ordinary artwork image")
	check(int(data.get("attack", 0)) == 32 and int(data.get("defense", 0)) == 32, card_id + ": the diorama Secret has its intended combat values")
	data["instance_id"] = card_id + "-secret-visual"
	card = _new_card(data)
	await _settle()
	var art: Node = card.get("_diorama_art")
	check(is_instance_valid(art), "Card3D instantiates its live diorama artwork")
	if not is_instance_valid(art):
		card.queue_free()
		await _settle()
		return
	var room_view := _room_viewport(art)
	check(room_view != null, "the room renders into a dedicated SubViewport")
	if room_view == null:
		card.queue_free()
		await _settle()
		return
	check(room_view.find_world_3d() != viewport.find_world_3d(), "room geometry and lights are isolated from the parent game world")
	check(_contains_scene(art, str(config.model)), card_id + ": the room contains the correct existing imported 3D model")
	check(card._card_material.albedo_texture == room_view.get_texture(), "only the normal artwork material displays the live room texture")
	check(card.card_image.mesh is QuadMesh and (card.card_image.mesh as QuadMesh).size.is_equal_approx(Vector2(0.56, 0.34)), "the room remains clipped to the original artwork rectangle")
	check(card.rarity_label.text.to_lower().contains("secret") and card._rarity_glow_material.get_shader_parameter("rainbow_mode") == true, "the normal printed Secret label and rainbow rim remain intact")
	check(card.attack_label.text == "32" and card.defense_label.text == "32" and card.name_label.visible, "the live room preserves printed name, attack and defense")
	var room_camera := room_view.get_camera_3d()
	check(room_camera != null, "the isolated artwork has its own current 3D camera")
	if room_camera == null:
		card.queue_free()
		await _settle()
		return
	var front_camera := room_camera.global_transform
	var front_projection := room_camera.get_camera_projection()
	if DisplayServer.get_name() != "headless":
		await _check_render(room_view, room_camera, str(config.capture))
	else:
		print(card_id + ": render evidence skipped in headless; run the same scene with Forward+ for PNG and pixel assertions.")
		card.rotation_degrees.y = 25.0
		await _settle()
	check(not room_camera.global_transform.is_equal_approx(front_camera) or room_camera.get_camera_projection() != front_projection, "rotating the physical card changes the room's actual camera perspective")
	card.rotation = Vector3.ZERO
	await _settle()
	await _check_suspension(room_view)
	await _check_materials_and_reuse(data, art, room_view)
	var final_art: Node = card.get("_diorama_art")
	var final_room := _room_viewport(final_art)
	card.queue_free()
	await _settle()
	check(not is_instance_valid(final_art) and not is_instance_valid(final_room), "removing the card also releases its room and rendering viewport")


func _make_stage() -> void:
	viewport = SubViewport.new()
	viewport.name = "CardTestViewport"
	viewport.size = Vector2i(1200, 900)
	viewport.world_3d = World3D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.012, 0.016, 0.024)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.85
	viewport.world_3d.environment = environment
	camera = Camera3D.new()
	camera.position = Vector3(0, 0, 2.4)
	camera.fov = 35.0
	viewport.add_child(camera)
	camera.make_current()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, -25, 0)
	light.light_energy = 1.0
	viewport.add_child(light)


func _new_card(data: Dictionary) -> Card3D:
	var result := CARD_SCENE.instantiate() as Card3D
	viewport.add_child(result)
	result.setup(data)
	result.description_label.skip()
	return result


func _check_render(room_view: SubViewport, room_camera: Camera3D, capture_prefix: String) -> void:
	card.rotation = Vector3.ZERO
	await _settle()
	await _capture(viewport, capture_prefix + "-front")
	var front := await _capture(room_view, capture_prefix + "-room-front")
	check(_image_variation(front) > 0.02, "the room texture contains visible geometry rather than an empty frame")
	card.rotation_degrees.y = -25.0
	await _settle()
	await _capture(viewport, capture_prefix + "-left")
	var left := await _capture(room_view, capture_prefix + "-room-left")
	var left_camera := room_camera.global_transform
	card.rotation_degrees.y = 25.0
	await _settle()
	await _capture(viewport, capture_prefix + "-right")
	var right := await _capture(room_view, capture_prefix + "-room-right")
	check(_image_difference(left, right) > 0.015, "left and right rotations produce visibly different perspectives inside the artwork")
	check(_image_difference(front, left) > 0.01 and _image_difference(front, right) > 0.01, "both tilted room renders differ from the straight-on view")
	check(not room_camera.global_transform.is_equal_approx(left_camera), "left and right perspectives are produced by moving the actual room camera")


func _check_suspension(room_view: SubViewport) -> void:
	check(room_view.render_target_update_mode != SubViewport.UPDATE_DISABLED, "visible front-facing artwork updates its room")
	card.hide()
	await _settle()
	check(room_view.render_target_update_mode == SubViewport.UPDATE_DISABLED, "hidden cards stop rendering their room")
	card.show()
	await _settle()
	check(room_view.render_target_update_mode != SubViewport.UPDATE_DISABLED, "showing the card resumes its room")
	card.rotation_degrees.y = 180.0
	await _settle()
	check(room_view.render_target_update_mode == SubViewport.UPDATE_DISABLED, "face-down cards do not spend frames rendering an invisible room")
	card.rotation = Vector3.ZERO
	await _settle()
	check(room_view.render_target_update_mode != SubViewport.UPDATE_DISABLED, "turning the card face-up resumes the same room")
	card.position.x = 20.0
	await _settle()
	check(room_view.render_target_update_mode == SubViewport.UPDATE_DISABLED, "artwork outside the viewer's screen stops rendering its room")
	card.position = Vector3.ZERO
	await _settle()
	check(room_view.render_target_update_mode != SubViewport.UPDATE_DISABLED, "bringing the card back onto the screen resumes its room")
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	await _settle()
	check(room_view.render_target_update_mode == SubViewport.UPDATE_DISABLED, "a disabled parent preview viewport also suspends its nested room")
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await _settle()
	check(room_view.render_target_update_mode != SubViewport.UPDATE_DISABLED, "reactivating the parent preview resumes its nested room")


func _check_materials_and_reuse(data: Dictionary, art: Node, room_view: SubViewport) -> void:
	var texture := room_view.get_texture()
	var child_count := card.get_child_count()
	card.show_blood_hit(0.5)
	card.setup(data)
	await _settle()
	check(card.get("_diorama_art") == art and card.get_child_count() == child_count and card._card_material.albedo_texture == texture, "repeated network-style setup reuses the existing room and viewport texture")
	check(card.get_blood_intensity() > 0.0 and card.card_image.material_overlay != null, "refreshing the same prop Secret preserves its active blood overlay")
	var holo_data := data.duplicate(true)
	holo_data["is_holo"] = true
	card.setup(holo_data)
	await _settle()
	check(card.get("_diorama_art") == art and card._card_material.next_pass == card._holo_image_pass, "Holo finishing reuses the same live room")
	check(card._holo_image_pass.get_shader_parameter("albedo_texture") == texture, "the Holo pass samples the actual live viewport artwork")
	var sibling := _new_card(data)
	await _settle()
	var sibling_art: Node = sibling.get("_diorama_art")
	var sibling_view := _room_viewport(sibling_art)
	check(sibling_art != art and sibling_view != room_view and sibling_view.find_world_3d() != room_view.find_world_3d(), "each visible prop Secret owns an independent room and camera")
	sibling.set_death_dissolve_progress(0.4)
	var dissolve := sibling.card_image.get_active_material(0) as ShaderMaterial
	check(dissolve != null and dissolve.get_shader_parameter("albedo_texture") == sibling_view.get_texture() and is_equal_approx(sibling.get_death_dissolve_progress(), 0.4), "death dissolution preserves the viewport texture while dissolving the artwork")
	check(card._card_material.albedo_texture == texture and card._holo_image_pass != null, "one card's death cannot alter another card's live artwork or Holo")
	sibling.queue_free()
	await _settle()
	var static_data := CardDatabase.get_card("corpse").duplicate(true)
	card.setup(static_data)
	await _settle()
	check(card.get("_diorama_art") == null and not is_instance_valid(art) and not is_instance_valid(room_view), "reusing the card for static art releases its private room")
	check(card._card_material.albedo_texture.resource_path == static_data.get("image") and card._card_material.next_pass == null and not card._animated_image, "static artwork and its normal material return after diorama reuse")
	var animated_data := CardDatabase.get_card("piss").duplicate(true)
	card.setup(animated_data)
	card._current_frame = 1
	card._update_card_frame()
	check(card._animated_image and card._card_material.albedo_texture.resource_path == animated_data.get("image") and card._card_material.uv1_offset != Vector3.ZERO, "ordinary animated artwork still advances its atlas frames after room cleanup")
	card.setup(data)
	await _settle()
	check(is_instance_valid(card.get("_diorama_art")) and card._card_material.albedo_texture is ViewportTexture and card._card_material.uv1_scale == Vector3.ONE and card._card_material.uv1_offset == Vector3.ZERO, "switching back from an animation restores a fresh full-frame room")


func _room_viewport(art: Node) -> SubViewport:
	if not is_instance_valid(art):
		return null
	for child in art.find_children("*", "SubViewport", true, false):
		return child as SubViewport
	return null


func _contains_scene(node: Node, path: String) -> bool:
	if node.scene_file_path == path:
		return true
	for child in node.get_children():
		if _contains_scene(child, path):
			return true
	return false


func _settle() -> void:
	for frame in range(4):
		await get_tree().process_frame


func _capture(target: SubViewport, file_name: String) -> Image:
	await _settle()
	RenderingServer.force_draw(false)
	var result := target.get_texture().get_image()
	check(result != null and not result.is_empty() and result.save_png("res://" + file_name + ".png") == OK, "save rendered evidence: " + file_name)
	return result


func _image_variation(source: Image) -> float:
	if source == null or source.is_empty():
		return 0.0
	var minimum := 1.0
	var maximum := 0.0
	for y in range(0, source.get_height(), 7):
		for x in range(0, source.get_width(), 7):
			var value := source.get_pixel(x, y).v
			minimum = minf(minimum, value)
			maximum = maxf(maximum, value)
	return maximum - minimum


func _image_difference(first: Image, second: Image) -> float:
	if first == null or second == null or first.is_empty() or first.get_size() != second.get_size():
		return 0.0
	var difference := 0.0
	var samples := 0
	for y in range(0, first.get_height(), 7):
		for x in range(0, first.get_width(), 7):
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			difference += Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
			samples += 1
	return difference / float(maxi(samples, 1))


func _save_bytes() -> Dictionary:
	var result := {}
	for slot in range(1, 4):
		for file_name: String in SaveSlots.PROFILE_FILES:
			var path := SaveSlots.get_slot_directory(slot).path_join(file_name)
			result[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	return result


func _finish() -> void:
	print("USB_SECRET_CARD_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
