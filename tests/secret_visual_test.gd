extends Node3D

const CARD_SCENE := preload("res://scenes/table/Card3D.tscn")
const OUTLINE := preload("res://assets/shader/rarity_outline.gdshader")
var checks := 0
var failures := 0
var viewport: SubViewport
var camera: Camera3D


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + message)
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/") or not CardUpgradeManager.SAVE_PATH.begins_with("res://test-user/") or not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Run with the isolated match-feature runner, never the player profile.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	var files_before := _save_bytes()
	var collection_before := CollectionManager.collection.duplicate(true)
	var upgrades_before := CardUpgradeManager.upgrades.duplicate(true)
	var time_scale_before := Engine.time_scale
	check(RarityEffectsData.rarity_rank("secret") == RarityEffectsData.rarity_rank("exotic") + 1 and RarityEffectsData.RARITY_ORDER.back() == "secret", "Secret ranks directly above Exotic")
	check(RarityEffectsData.get_data("secret") != RarityEffectsData.get_data("common") and Card3D._rarity_presets.has("secret"), "Secret has its own reveal and card presets")
	var defaults := ShaderMaterial.new()
	defaults.shader = OUTLINE
	check(defaults.get_shader_parameter("rainbow_mode") != true, "the shared outline shader defaults to an ordinary fixed-color rim")
	for id in ["developer", "missing_texture"]:
		check(str(CardDatabase.get_card(id).get("rarity", "")) == "secret", "actual catalog card uses Secret: " + id)
	await _check_materials()
	check(Engine.time_scale == time_scale_before, "Secret setup and per-card animation never alter global time scale")
	if DisplayServer.get_name() != "headless":
		await _check_render()
	else:
		print("SECRET_VISUAL_RENDER: skipped in headless; run the same scene with Forward+ for image assertions.")
	check(_save_bytes() == files_before and CollectionManager.collection == collection_before and CardUpgradeManager.upgrades == upgrades_before, "card presentation preserves player state and all save bytes")
	print("SECRET_VISUAL_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _data(id: String, rarity: String, holo: bool = false) -> Dictionary:
	var data := CardDatabase.get_card(id).duplicate(true)
	data["rarity"] = rarity
	data["is_holo"] = holo
	data["instance_id"] = "secret-visual-" + id
	return data


func _card(data: Dictionary, parent: Node = null) -> Card3D:
	var card := CARD_SCENE.instantiate() as Card3D
	if parent == null:
		parent = self
	parent.add_child(card)
	card.setup(data)
	card.description_label.skip()
	return card


func _check_materials() -> void:
	var normal := _card(_data("corpse", "common"))
	var secret_data := _data("developer", "secret", true)
	var secret := _card(secret_data)
	var sibling := _card(_data("missing_texture", "secret"))
	var material := secret._rarity_glow_material
	var normal_parameters := _parameters(normal._rarity_glow_material)
	check(material != normal._rarity_glow_material and material != sibling._rarity_glow_material and material.get_shader_parameter("rainbow_mode") == true, "every card owns its mutable rarity material and only Secret enables rainbow")
	material.set_shader_parameter("rainbow_clock_offset", 2.5)
	check(_parameters(normal._rarity_glow_material) == normal_parameters and is_zero_approx(float(sibling._rarity_glow_material.get_shader_parameter("rainbow_clock_offset"))), "changing one Secret's phase cannot recolor another card")
	var body := secret.card_model.get_node("Cube") as MeshInstance3D
	var plain_body := normal.card_model.get_node("Cube") as MeshInstance3D
	check(secret._card_material.next_pass == secret._holo_image_pass and secret._holo_body_pass != null and body.get_active_material(0) == plain_body.get_active_material(0), "Secret rainbow coexists with Holo while keeping the shared anonymous card back")
	var texture := secret._card_material.albedo_texture
	var printed_name := secret.name_label.text
	var scale_before := Engine.time_scale
	secret._process(0.3)
	check(secret._card_material.albedo_texture == texture and secret.name_label.text == printed_name and secret.name_label.visible and secret.attack_label.visible and secret.defense_label.visible and Engine.time_scale == scale_before, "Secret motion preserves printed content, combat values, artwork and global timing")
	secret.setup(normal.card_data)
	check(secret._rarity_glow_material == material and material.get_shader_parameter("rainbow_mode") == false and is_zero_approx(float(material.get_shader_parameter("rainbow_clock_offset"))) and secret._card_material.next_pass == null, "Secret-to-normal setup restores ordinary rim and artwork on the same instance")
	check(material.get_shader_parameter("rarity_color") == normal._rarity_glow_material.get_shader_parameter("rarity_color"), "reused normal card receives its correct ordinary rarity color")
	secret.setup(secret_data)
	check(secret._rarity_glow_material == material and material.get_shader_parameter("rainbow_mode") == true and secret._card_material.next_pass == secret._holo_image_pass, "reusing the card as Secret restores one rainbow and one Holo pass")
	var animated := _card(_data("piss", "secret", true))
	animated._current_frame = 2
	animated._update_card_frame()
	check(animated._animated_image and animated._rarity_glow_material.get_shader_parameter("rainbow_mode") == true and animated._holo_image_pass.get_shader_parameter("artwork_uv_offset") == Vector2(animated._card_material.uv1_offset.x, animated._card_material.uv1_offset.y), "animated Secret artwork and its Holo pass keep matching atlas frames")
	var special_data := _data("clicker", "secret", true)
	var special := _card(special_data)
	var aura := special._special_aura
	check(is_instance_valid(aura) and aura.visible and special._rarity_glow_material.get_shader_parameter("rainbow_mode") == true, "the independent special-card aura can coexist with a Secret rainbow")
	await get_tree().process_frame
	var node_count := special.get_child_count()
	for iteration in range(3):
		special.setup(normal.card_data)
		check(not aura.visible and special._rarity_glow_material.get_shader_parameter("rainbow_mode") == false, "normal reuse hides both Secret and special decoration")
		special.setup(special_data)
		await get_tree().process_frame
	check(special._special_aura == aura and special.get_child_count() == node_count, "repeated special/normal reuse neither duplicates aura nodes nor grows the card")
	var stack := CARD_SCENE.instantiate() as Card3D
	stack.is_stack_decoration = true
	add_child(stack)
	stack.setup(secret_data)
	check(not stack.rarity_mesh.visible and stack._rarity_glow_material.get_shader_parameter("rainbow_mode") != true and stack._holo_image_pass == null, "decorative face-down stacks expose no Secret or Holo finish")
	secret.show_blood_hit(0.4)
	check(secret.card_image.material_overlay != null and material.get_shader_parameter("rainbow_mode") == true, "blood overlays remain independent from the Secret rim")
	special.set_death_dissolve_progress(0.45)
	check(is_equal_approx(special.get_death_dissolve_progress(), 0.45) and not special.rarity_mesh.visible and not special.card_outline.visible and not aura.visible, "death dissolution removes all rim and aura decoration from dissolved holes")
	for card in [normal, secret, sibling, animated, special, stack]:
		card.queue_free()
	await get_tree().process_frame


func _parameters(material: ShaderMaterial) -> Dictionary:
	var result := {}
	for uniform: Dictionary in material.shader.get_shader_uniform_list():
		result[uniform["name"]] = material.get_shader_parameter(uniform["name"])
	return result


func _save_bytes() -> Dictionary:
	var result := {}
	for slot in range(1, 4):
		for file_name: String in SaveSlots.PROFILE_FILES:
			var path := SaveSlots.get_slot_directory(slot).path_join(file_name)
			result[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	return result


func _check_render() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1200, 800)
	viewport.world_3d = World3D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.012, 0.016, 0.024)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.75
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	viewport.world_3d.environment = environment
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.15
	camera.position = Vector3(0, 0, 5)
	viewport.add_child(camera)
	camera.make_current()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, -25, 0)
	light.light_energy = 1.0
	viewport.add_child(light)
	var cards: Array[Card3D] = [
		_card(_data("developer", "secret"), viewport),
		_card(_data("missing_texture", "secret", true), viewport),
		_card(_data("corpse", "common"), viewport),
	]
	for index in range(cards.size()):
		cards[index].position.x = float(index - 1) * 1.02
		cards[index].set_process(false)
	await _capture("secret-cards-phase-0")
	for index in [0, 1]:
		cards[index]._rarity_glow_material.set_shader_parameter("rainbow_clock_offset", 2.5)
	await _capture("secret-cards-phase-1")
	for card in cards:
		card.queue_free()
	await get_tree().process_frame
	# The same production shader on its normalized geometry makes interior,
	# hue diversity and movement measurable independently of painted artwork.
	viewport.size = Vector2i(512, 640)
	camera.size = 1.5
	environment.background_color = Color.BLACK
	var proxy := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	proxy.mesh = quad
	proxy.scale = Vector3(0.396, 0.60, 1)
	var material := ShaderMaterial.new()
	material.shader = OUTLINE
	material.set_shader_parameter("rainbow_mode", true)
	material.set_shader_parameter("rarity_color", Color.WHITE)
	proxy.material_override = material
	viewport.add_child(proxy)
	var first := await _capture("secret-rim-phase-0")
	material.set_shader_parameter("rainbow_clock_offset", 2.5)
	var second := await _capture("secret-rim-phase-1")
	var hues := {}
	var moved := 0
	for position in _rim_samples():
		var pixel := camera.unproject_position(position)
		var a := first.get_pixelv(Vector2i(pixel))
		var b := second.get_pixelv(Vector2i(pixel))
		if a.s > 0.25 and a.v > 0.08:
			hues[int(floor(a.h * 6.0)) % 6] = true
		if Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length() > 0.15:
			moved += 1
	check(hues.size() >= 4, "rendered Secret rim contains several simultaneous HSV hues")
	check(moved >= 8, "a quarter-cycle clock offset visibly moves colors around the rim")
	var clear_interior := true
	for x in [-0.30, -0.15, 0.0, 0.15, 0.30]:
		for y in [-0.50, -0.25, 0.0, 0.25, 0.50]:
			var pixel := Vector2i(camera.unproject_position(Vector3(x, y, 0)))
			clear_interior = clear_interior and first.get_pixelv(pixel).v < 0.02 and second.get_pixelv(pixel).v < 0.02
	check(clear_interior, "rainbow pixels never cover the card's interior text and artwork region")
	proxy.rotation.y = PI
	var back := await _capture("secret-rim-back")
	var hidden_back := true
	for position in _rim_samples():
		hidden_back = hidden_back and back.get_pixelv(Vector2i(camera.unproject_position(position))).v < 0.02
	check(hidden_back, "the shader's rear face reveals no colored rim")
	viewport.queue_free()
	await get_tree().process_frame


func _rim_samples() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for x in [-0.28, -0.10, 0.10, 0.28]:
		result.append(Vector3(x, 0.594, 0))
		result.append(Vector3(x, -0.594, 0))
	for y in [-0.42, -0.14, 0.14, 0.42]:
		result.append(Vector3(0.390, y, 0))
		result.append(Vector3(-0.390, y, 0))
	return result


func _capture(name: String) -> Image:
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	var image := viewport.get_texture().get_image()
	check(image != null and not image.is_empty() and image.save_png("res://" + name + ".png") == OK, "save rendered evidence: " + name)
	return image
