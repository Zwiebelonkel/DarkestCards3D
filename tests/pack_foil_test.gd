extends Node3D

const PACK_SCENE := preload("res://scenes/ui/PackOpeningScreen.tscn")
const PACK_TYPES := preload("res://scripts/ui/PackShopMachine.gd").PACK_TYPES

var failures := 0
var checks := 0
var purchase_signals := 0
var reset_signals := 0
var screen: PackOpeningScreen
var _mouse_position := Vector2(310, 340)
var _previous_mesh_id := 0
var _previous_material_id := 0


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func _wait_until(predicate: Callable, timeout_msec: int = 4000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())


func _run() -> void:
	if not str(DeckManager.SAVE_PATH).begins_with("res://test-user/") or not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Run pack_foil_test.tscn through run_match_feature_tests.ps1 to isolate all player saves.")
		get_tree().quit(1)
		return
	get_tree().root.size = Vector2i(1280, 900)
	# This fixture exercises all paid foil models, including the God Pack.
	GameCurrency.level = PackDefinition.get_minimum_level("god")
	GameCurrency.xp = 0
	CollectionManager.collection = {"cards": {}, "instances": []}
	# Real rewards and collection code, with one ordinary combat card so this
	# interaction test does not depend on rarity effects, rerolls or slow motion.
	var original_database := CardDatabase.cards.duplicate(true)
	var fixture_card: Dictionary = CardDatabase.get_card("corpse").duplicate(true)
	CardDatabase.cards.assign([fixture_card])
	screen = PACK_SCENE.instantiate() as PackOpeningScreen
	add_child(screen)
	screen.pack_opening_started.connect(func(): purchase_signals += 1)
	screen.pack_ready_for_next_purchase.connect(func(): reset_signals += 1)
	screen.base_shake_strength = 0.0
	screen.base_shake_rotation_strength = 0.0
	screen.rarity_camera_shake_multiplier = 0.0
	screen.rarity_pack_shake_multiplier = 0.0
	_setup_visual_environment()
	await get_tree().process_frame
	GameCurrency.coins = 0
	var basic := _pack_data("basic")
	check(not screen.buy_pack("basic", basic) and not screen._pack_bought and purchase_signals == 0, "insufficient funds cannot create a bought pack or opening signal")
	GameCurrency.coins = 1000
	_begin_drag(Vector2(310, 340))
	check(not screen._dragging_pack_top and not screen._opened, "an unbought pack cannot be grabbed or opened")
	for pack_id in ["basic", "ultra", "god"]:
		await _check_model_cycle(pack_id)
	check(purchase_signals == 3 and reset_signals == 3, "three paid packs emit exactly three purchase and completion signals")
	check(CollectionManager.get_amount("corpse") == 22, "all three real pack sizes award exactly 5 + 7 + 10 cards")
	CardDatabase.cards = original_database
	CardDatabase.set_pack_rarity_weights({})
	screen.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("PACK_FOIL_TESTS: " + ("PASS" if failures == 0 else "FAIL") + " (%d checks)" % checks)
	get_tree().quit(0 if failures == 0 else 1)


func _pack_data(pack_id: String) -> Dictionary:
	var data: Dictionary = PACK_TYPES[pack_id].duplicate(true)
	data["rarity_weights"] = {"common": 1.0}
	return data


func _setup_visual_environment() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.032, 0.041, 0.057)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.88, 0.91, 1.0)
	environment.ambient_light_energy = 0.75
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	add_child(environment_node)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -34, 0)
	key.light_energy = 1.8
	add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(2.5, 2.8, 4.0)
	fill.omni_range = 12.0
	fill.light_energy = 1.3
	fill.light_color = Color(0.65, 0.76, 1.0)
	add_child(fill)
	var camera := screen.get_node("Camera3D") as Camera3D
	camera.position = Vector3(2.65, 2.6, 5.8)
	camera.look_at(Vector3(0.0, 0.65, 0.0))
	camera.fov = 34.0
	camera.current = true
	screen.screen_flash_camera = camera
	screen.get_node("MenuNavigation/MenuButton").hide()


func _begin_drag(position: Vector2) -> void:
	_mouse_position = position
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = position
	screen._on_pack_top_input(screen.screen_flash_camera, press, Vector3.ZERO, Vector3.UP, 0)


func _move_drag(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.relative = position - _mouse_position
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	_mouse_position = position
	screen._input(motion)


func _release_drag() -> void:
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = _mouse_position
	screen._input(release)


func _move_to_progress(progress: float) -> void:
	# Convert an intended fixture tear stage to a pointer position using the
	# public tuning knobs; input still travels through the production handler.
	var remaining := maxf(1.0 - screen._drag_start_progress, 0.001)
	var normalized := clampf((progress - screen._drag_start_progress) / remaining, 0.0, 1.0)
	var distance := screen._drag_screen_distance * remaining * pow(normalized, 1.0 / screen.rip_resistance_curve)
	distance += screen.rip_grab_slack_pixels + (12.0 if progress >= 1.0 else 0.0)
	_move_drag(screen._drag_start_mouse_pos + screen._drag_screen_axis * distance)


func _snapshot(pack_id: String, stage: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var path := "res://pack-foil-%s-%s.png" % [pack_id, stage]
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "rendered snapshot saved: " + pack_id + " " + stage)


func _check_model_cycle(pack_id: String) -> void:
	var data := _pack_data(pack_id)
	var coins_before := GameCurrency.coins
	var collection_before := CollectionManager.get_amount("corpse")
	check(screen.buy_pack(pack_id, data), pack_id + " can be purchased after the previous pack is collected")
	check(is_equal_approx(GameCurrency.coins, coins_before - int(data["cost"])), pack_id + " charges the displayed price once")
	var purchased_pack_id := screen.pack.get_instance_id()
	check(not screen.buy_pack("god", _pack_data("god")) and screen.pack.get_instance_id() == purchased_pack_id and is_equal_approx(GameCurrency.coins, coins_before - int(data["cost"])), "an already bought " + pack_id + " rejects a second purchase without replacing its model")
	await get_tree().create_timer(0.55).timeout
	check(screen._pack_bought and not screen._opened and is_zero_approx(screen._drag_progress), pack_id + " starts sealed with no tear from the previous model")
	_check_model_resources(pack_id, data)
	await _snapshot(pack_id, "00-sealed")
	var drag_origin := Vector2(310, 340)
	_begin_drag(drag_origin)
	check(screen._dragging_pack_top and screen._drag_screen_distance > 0.0, pack_id + " starts a camera-projected drag on the bought foil")
	_move_to_progress(0.35)
	var reached_first := await _wait_until(func(): return screen._drag_progress >= 0.34, 1800)
	check(reached_first and screen._drag_progress < 0.4 and not screen._opened, pack_id + " follows a partial pull without opening early")
	await _snapshot(pack_id, "35-pulled")
	var first_progress := screen._drag_progress
	_move_to_progress(0.12)
	await get_tree().create_timer(0.12).timeout
	check(screen._drag_progress >= first_progress - 0.001, pack_id + " never repairs its tear when the pointer moves backward")
	_move_to_progress(0.70)
	var reached_second := await _wait_until(func(): return screen._drag_progress >= 0.69, 1800)
	check(reached_second and screen._drag_progress < 0.76 and not screen._opened, pack_id + " progressively tears to a second partial distance")
	await _snapshot(pack_id, "70-pulled")
	var torn_before_release := screen._drag_progress
	_release_drag()
	await get_tree().create_timer(0.65).timeout
	check(not screen._dragging_pack_top and not screen._opened and screen._pack_bought, pack_id + " stays bought and unopened after an incomplete release")
	check(screen._drag_progress >= torn_before_release - 0.001 and screen._drag_progress < 0.8, pack_id + " retains the existing tear while released foil settles")
	check(screen._foil_lift < 0.04, pack_id + " released foil relaxes its pull instead of staying stretched")
	var collider := screen.pack_top_area.get_node("CollisionShape3D") as CollisionShape3D
	var box := collider.shape as BoxShape3D
	var grip_in_collider := collider.to_local(screen.pack_top.to_global(screen._foil.get_grip_local_position()))
	check(AABB(-box.size * 0.5, box.size).has_point(grip_in_collider), pack_id + " visible curled grip remains inside its real ray-picking hitbox after release")
	check(not screen.buy_pack("basic", _pack_data("basic")) and screen.pack.get_instance_id() == purchased_pack_id, pack_id + " cannot be replaced by another purchase after a partial peel")
	await _snapshot(pack_id, "70-released")
	var retained_progress := screen._drag_progress
	var grip_before: Vector3 = screen._foil.get_grip_local_position()
	drag_origin = Vector2(460, 420)
	_begin_drag(drag_origin)
	check(is_equal_approx(screen._drag_progress, retained_progress) and screen._foil.get_grip_local_position().distance_to(grip_before) < 0.001, pack_id + " can be regrabbed without jumping or resetting the torn edge")
	_move_to_progress(retained_progress + 0.15)
	var continued := await _wait_until(func(): return screen._drag_progress >= retained_progress + 0.13, 1800)
	check(continued and screen._drag_progress < 0.94, pack_id + " continues the remaining tear from its new grab point")
	var focus_progress := screen._drag_progress
	screen._on_pack_focus_lost()
	await get_tree().create_timer(0.35).timeout
	check(not screen._dragging_pack_top and screen._drag_progress >= focus_progress - 0.001 and not screen._opened, pack_id + " focus loss safely releases the foil without undoing its tear")
	drag_origin = Vector2(590, 440)
	_begin_drag(drag_origin)
	var progress_before_navigation := screen._drag_progress
	_move_to_progress(1.0)
	screen.pack_top_area.input_ray_pickable = false
	await get_tree().process_frame
	await get_tree().process_frame
	check(not screen._dragging_pack_top and not screen._opened and is_equal_approx(screen._drag_progress, progress_before_navigation), pack_id + " navigating away cancels a pending full pull before it can open the pack")
	screen.pack_top_area.input_ray_pickable = true
	drag_origin = Vector2(620, 450)
	_begin_drag(drag_origin)
	_move_to_progress(1.0)
	var automatically_opened := await _wait_until(func(): return screen._opened, 1800)
	check(automatically_opened and not screen._dragging_pack_top, pack_id + " automatically opens once the final tear completes without requiring button release")
	await _snapshot(pack_id, "100-finished")
	_release_drag()
	screen._open_pack_from_drag()
	check(not screen.buy_pack("basic", _pack_data("basic")), pack_id + " rejects purchasing while its cards are being opened")
	var cards_spawned := await _wait_until(func(): return screen._card_stack.size() == int(data["card_count"]), 2400)
	check(cards_spawned, pack_id + " spawns exactly its paid number of cards")
	await get_tree().create_timer(0.8).timeout
	var spawn_ids: Array[int] = []
	for card in screen._card_stack:
		spawn_ids.append(card.get_instance_id())
	_release_drag()
	screen._open_pack_from_drag()
	await get_tree().create_timer(0.55).timeout
	var same_cards := screen._card_stack.size() == spawn_ids.size()
	for index in range(mini(screen._card_stack.size(), spawn_ids.size())):
		same_cards = same_cards and screen._card_stack[index].get_instance_id() == spawn_ids[index]
	check(same_cards and screen._pending_collection_card_ids.is_empty(), pack_id + " repeated open or release callbacks neither reroll nor duplicate rewards")
	check(CollectionManager.get_amount("corpse") == collection_before, pack_id + " rewards enter the collection only when explicitly collected")
	for card in screen._card_stack.duplicate():
		screen._reveal_top_card(card)
	await get_tree().create_timer(0.85).timeout
	check(screen._pending_collection_card_ids.size() == int(data["card_count"]) and screen._waiting_for_collect_click, pack_id + " reveal queues each paid card exactly once")
	screen._collect_revealed_cards()
	screen._collect_revealed_cards()
	check(CollectionManager.get_amount("corpse") == collection_before + int(data["card_count"]), pack_id + " duplicate collect submission awards the cards only once")
	var reset_complete := await _wait_until(func(): return not screen._pack_bought and not screen._opened and not screen._collecting_cards, 4000)
	check(reset_complete and screen._card_stack.is_empty() and screen._revealed_cards.is_empty() and screen._pending_collection_card_ids.is_empty(), pack_id + " collection clears the reveal and returns to the purchase state")
	check(is_zero_approx(screen._drag_progress) and not screen._dragging_pack_top and not screen.pack.visible and not screen.pack_top_area.input_ray_pickable, pack_id + " reset removes foil progress and disables the hidden wrapper's input")
	check(is_equal_approx(GameCurrency.coins, coins_before - int(data["cost"])), pack_id + " complete peel/reveal/reset never charges another purchase")


func _material_textures(material: Material) -> Array[Texture2D]:
	var textures: Array[Texture2D] = []
	if material is StandardMaterial3D:
		if material.albedo_texture != null:
			textures.append(material.albedo_texture)
	elif material is ShaderMaterial and material.shader != null:
		for uniform: Dictionary in material.shader.get_shader_uniform_list():
			var value: Variant = material.get_shader_parameter(str(uniform.get("name", "")))
			if value is Texture2D:
				textures.append(value)
	return textures


func _check_model_resources(pack_id: String, data: Dictionary) -> void:
	var original_model := (data["scene"] as PackedScene).instantiate() as Node3D
	var original_top := original_model.get_node("top") as MeshInstance3D
	var foil_mesh := screen.pack_top.mesh
	check(foil_mesh != null and foil_mesh != original_top.mesh, pack_id + " deforms its own mesh without mutating the imported pack resource")
	check(foil_mesh.get_instance_id() != _previous_mesh_id, pack_id + " receives a fresh foil mesh after model switching")
	_previous_mesh_id = foil_mesh.get_instance_id()
	var material := screen.pack_top.get_active_material(0)
	check(material != null and material.get_instance_id() != _previous_material_id, pack_id + " has independent foil material state")
	_previous_material_id = material.get_instance_id() if material != null else 0
	var complete_surfaces := foil_mesh.get_surface_count() == original_top.mesh.get_surface_count()
	var textures_preserved := true
	var valid_uvs := true
	for index in range(mini(foil_mesh.get_surface_count(), original_top.mesh.get_surface_count())):
		var arrays := foil_mesh.surface_get_arrays(index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		valid_uvs = valid_uvs and not vertices.is_empty() and vertices.size() == uvs.size()
		var source_textures := _material_textures(original_top.get_active_material(index))
		var foil_textures := _material_textures(screen.pack_top.get_active_material(index))
		for texture: Texture2D in source_textures:
			textures_preserved = textures_preserved and foil_textures.any(func(candidate: Texture2D) -> bool: return candidate.resource_path == texture.resource_path)
	check(complete_surfaces and valid_uvs, pack_id + " retains every original foil surface with complete texture coordinates")
	check(textures_preserved, pack_id + " foil keeps its own model's print textures")
	original_model.free()
