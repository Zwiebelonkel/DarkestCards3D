extends Node3D

const CARD_SCENE := preload("res://scenes/table/Card3D.tscn")
var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, detail: String) -> void:
	print(("PASS " if condition else "FAIL ") + detail)
	if not condition:
		failures += 1


func _run() -> void:
	AudioServer.set_bus_mute(0, true)
	_check_probability_and_persistence()
	await _check_materials()
	await _check_pack_and_collection()
	await _capture_holo_cards()
	print("HOLO_CARDS_TESTS: " + ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)


func _check_probability_and_persistence() -> void:
	var successes := 0
	for roll in range(100):
		if CardData.roll_holo(roll):
			successes += 1
	check(successes == 1 and CardData.roll_holo(0) and not CardData.roll_holo(1) and not CardData.roll_holo(99), "exactly one of 100 independent roll outcomes is Holo")
	var base := CardDatabase.get_card("corpse")
	check(not CardData.is_holo(CardData.create_instance("corpse")) and not CardData.is_holo(CardData.merge_card_and_instance(base)), "plain construction and data lookup never roll a finish")
	CollectionManager.collection = {"corpse": 2}
	CollectionManager._migrate_legacy_collection()
	check(CollectionManager.get_card_instances().all(func(entry): return not CardData.is_holo(entry)), "legacy counts migrate as non-Holo without retroactive rolls")
	var original := CardData.create_instance("corpse", 1, [], true)
	var added := CollectionManager.add_card_instance(original)
	check(added.get("instance_id") == original.get("instance_id") and CardData.is_holo(added), "pre-rolled acquisition retains its exact identity and Holo flag")
	check(CollectionManager.add_card_instance(original).is_empty() and CollectionManager.get_amount("corpse") == 3, "repeated collection of the same instance cannot duplicate rewards")
	CollectionManager.save_collection()
	CollectionManager.collection = {"cards": {}, "instances": []}
	CollectionManager.load_collection()
	var first := CollectionManager.get_display_card("corpse")
	check(first.get("instance_id") == original.get("instance_id") and CardData.is_holo(first), "save/reload preserves Holo and grouped collection prefers the owned Holo copy")
	var copies := CollectionManager.get_deck_card_data(["corpse", "corpse", "corpse"])
	check(copies.size() == 3 and CardData.is_holo(copies[0]) and not CardData.is_holo(copies[1]) and not CardData.is_holo(copies[2]), "deck occurrences use distinct owned finishes without promoting every copy")
	check(copies[0]["instance_id"] != copies[1]["instance_id"] and copies[1]["instance_id"] != copies[2]["instance_id"], "repeated card types resolve to distinct saved identities")
	first["is_holo"] = false
	check(CardData.is_holo(CollectionManager.get_display_card("corpse")), "display dictionaries cannot mutate persistent ownership")
	var reconstructed := CardData.merge_card_and_instance(base, original)
	check(CardData.is_holo(reconstructed) and reconstructed["instance_id"] == original["instance_id"], "merging gameplay effects preserves finish metadata")


func _new_card(holo: bool, card_id: String = "corpse") -> Card3D:
	var card := CARD_SCENE.instantiate() as Card3D
	add_child(card)
	card.setup(CardData.with_instance_metadata(CardDatabase.get_card(card_id), CardData.create_instance(card_id, 1, [], holo)))
	return card


func _check_materials() -> void:
	var plain := _new_card(false)
	var holo := _new_card(true)
	var other := _new_card(true, "jd")
	var body := holo.card_model.get_node("Cube") as MeshInstance3D
	var plain_body := plain.card_model.get_node("Cube") as MeshInstance3D
	check(plain._card_material.next_pass == null and plain._holo_image_pass == null, "ordinary cards retain their original artwork material")
	check(holo._holo_image_pass != null and holo._holo_image_pass.shader == Card3D.HOLO_SHADER and holo._card_material.next_pass == holo._holo_image_pass, "Holo adds the existing holo.gdshader as an extra artwork pass")
	check(body.get_active_material(0) == plain_body.get_active_material(0), "card back materials stay identical and do not reveal hidden finishes")
	check(holo._holo_body_pass.next_pass != null and (holo._holo_body_pass.next_pass as ShaderMaterial).shader.code == (load("res://assets/shader/card_shine.gdshader") as Shader).code, "Holo retains the original rarity-independent shine pass")
	check(holo._rarity_glow_material.shader.code == plain._rarity_glow_material.shader.code and holo._rarity_glow_material.get_shader_parameter("rarity_color") == plain._rarity_glow_material.get_shader_parameter("rarity_color"), "rarity outline and its existing color remain unchanged")
	check(holo._holo_image_pass != other._holo_image_pass and holo._holo_body_material != other._holo_body_material, "different owned cards never share mutable foil materials")
	check(holo._holo_image_pass.get_shader_parameter("albedo_texture") == holo._card_material.albedo_texture, "the Holo pass samples the original card artwork")
	holo._frame_columns = 4
	holo._frame_rows = 2
	holo._current_frame = 5
	holo._update_card_frame()
	check(holo._holo_image_pass.get_shader_parameter("artwork_uv_scale") == Vector2(0.25, 0.5) and holo._holo_image_pass.get_shader_parameter("artwork_uv_offset") == Vector2(0.25, 0.5), "animated artwork and foil use the exact same spritesheet frame")
	holo.show_blood_hit(0.5)
	check(holo.card_image.material_overlay == holo._blood_materials[1] and holo._card_material.next_pass == holo._holo_image_pass, "blood overlays coexist with the extra Holo artwork pass")
	holo._clear_blood()
	check(holo.card_image.material_overlay == null and holo._card_material.next_pass == holo._holo_image_pass, "blood fading never removes the persistent Holo finish")
	var snapshot := holo.get_network_state()
	other.apply_network_state(snapshot)
	check(CardData.is_holo(other.card_data) and other._card_material.next_pass == other._holo_image_pass, "network reconstruction retains the same finish and shader")
	var old_holo_pass := holo._holo_image_pass
	holo.setup(snapshot["card_data"])
	check(holo._holo_image_pass == old_holo_pass and holo._holo_image_pass.next_pass == null, "repeated setup reuses one foil pass without growing a material chain")
	holo.setup(plain.card_data)
	check(holo._card_material.next_pass == null and body.get_active_material(1) == holo._holo_body_base_material, "reused Holo nodes return completely to ordinary materials")
	holo.setup(snapshot["card_data"])
	check(holo._card_material.next_pass == old_holo_pass and body.get_active_material(1) == holo._holo_body_material, "normal-to-Holo reuse restores the same additional passes")
	plain.queue_free()
	holo.queue_free()
	other.queue_free()
	await get_tree().process_frame


func _check_pack_and_collection() -> void:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	main.visible = false
	main.set_process(false)
	for layer in main.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	var screen := main.get_node("ScenePivot/PackShopMachine/PackOpeningScreen") as PackOpeningScreen
	screen.card_count = 3
	# This fixture verifies the normal collection; specials have their own wall.
	var original_cards: Array[Dictionary] = CardDatabase.cards.duplicate(true)
	CardDatabase.cards = CardDatabase.get_combat_cards()
	screen._spawn_cards_inside_pack()
	CardDatabase.cards = original_cards
	check(screen._card_stack.size() == 3 and screen._card_stack.all(func(card): return card.card_data.has("is_holo") and not str(card.card_data.get("instance_id", "")).is_empty()), "each pack card receives its finish and persistent identity before reveal")
	var card := screen._card_stack[0]
	var instance: Dictionary = card.get_meta("collection_instance")
	instance["is_holo"] = true
	card.setup(CardData.with_instance_metadata(card.card_data, instance))
	var identity := str(instance["instance_id"])
	var card_id := str(instance["card_id"])
	var amount_before := CollectionManager.get_amount(card_id)
	for stacked in screen._card_stack.duplicate():
		screen._reveal_top_card(stacked)
	screen._reveal_top_card(card)
	check(screen._pending_collection_instances.size() == 3 and CardData.is_holo(screen._pending_collection_instances[0]), "reveal queues the exact rolled instances once, including Holo")
	check(CollectionManager.get_amount(card_id) == amount_before, "revealing alone does not yet award duplicate collection entries")
	await get_tree().create_timer(0.85).timeout
	screen._collect_revealed_cards()
	screen._collect_revealed_cards()
	var matching := CollectionManager.get_instances_for_card(card_id).filter(func(entry): return str(entry.get("instance_id", "")) == identity)
	check(matching.size() == 1 and CardData.is_holo(matching[0]), "collecting stores the visible Holo instance exactly once without another roll")
	await get_tree().create_timer(2.0).timeout
	var collection := main.get_node("ScenePivot/Collection") as CollectionScreen
	collection.refresh_collection()
	var shown_holo := false
	for displayed: Card3D in collection._base_positions:
		if str(displayed.card_data.get("id", "")) == card_id and CardData.is_holo(displayed.card_data):
			shown_holo = true
	check(shown_holo, "the real collection screen renders the persisted Holo finish")
	collection._refresh_upgraded_card_everywhere(card_id)
	var still_holo := false
	for displayed: Card3D in collection._base_positions:
		if str(displayed.card_data.get("id", "")) == card_id and CardData.is_holo(displayed.card_data):
			still_holo = true
	check(still_holo, "refreshing shared card-type upgrades preserves Holo identity")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _capture_holo_cards() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 0.05, 4.4)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	camera.fov = 29.0
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30, -25, 0)
	light.light_energy = 1.3
	add_child(light)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.025, 0.035, 0.055)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.7
	add_child(world)
	var plain := _new_card(false)
	plain.position.x = -0.8
	var holo := _new_card(true)
	holo.position.x = 0.2
	holo.rotation_degrees.y = -12
	var special := _new_card(true, "jd")
	special.position.x = 1.2
	special.rotation_degrees.y = 14
	await get_tree().create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://holo-cards-preview.png")
