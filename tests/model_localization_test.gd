extends Node3D

var checks := 0
var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Run model_localization_test through the isolated match feature runner.")
		get_tree().quit(1)
		return
	var slot := (load("res://scenes/props/SlotMachine.tscn") as PackedScene).instantiate() as SoulSlotMachine
	add_child(slot)
	var model := slot.get_node("Model/slots") as Node3D
	var helper := LocalizedModelText.attach_slot_model(model)
	check(helper._mesh_texts.size() == 2, "both baked BET and SPIN meshes receive physical text replacements")
	check(helper._atlas_labels.size() == 2, "both mapped atlas signs receive localized labels")
	check(LocalizedModelText.attach_slot_model(model) == helper, "repeated attachment cannot duplicate text or atlas overlays")
	var button_areas := slot.button_areas.duplicate()
	var button_transforms: Dictionary = {}
	for action: String in slot._button_meshes:
		button_transforms[action] = slot._button_meshes[action].transform
	for entry: Dictionary in helper._mesh_texts:
		var replacement := entry["mesh"] as MeshInstance3D
		var expected_button: Node3D = slot._button_meshes["bet" if entry["source"] == "BET" else "spin"]
		check(replacement.get_parent().get_parent() == expected_button, "translated letters remain attached to the animated button")
	var signs: Array[LocalizedModelText] = []
	var table_button := (load("res://scenes/Table3DButton.tscn") as PackedScene).instantiate() as Table3DButton
	add_child(table_button)
	table_button.label_text = Localization.format_text("ADD TO DECK %d/%d", [15, 30])
	var table_collision := table_button.area.get_node("CollisionShape3D") as CollisionShape3D
	var table_shape: Shape3D = table_collision.shape
	for entry in [["collection", "2", "COLLECTION"], ["shop", "4", "SHOP"], ["upgrade", "3", "UPGRADE"]]:
		var sign := (load("res://assets/environments/props/Neon/%s/%s.glb" % [entry[1], entry[0]]) as PackedScene).instantiate() as Node3D
		add_child(sign)
		var original := sign.find_child("cards", true, false) as MeshInstance3D
		var original_material := original.get_active_material(0)
		var neon := LocalizedModelText.attach_neon(sign, entry[2])
		signs.append(neon)
		check(not original.visible and neon._mesh_texts.size() == 1, "baked neon glyphs are hidden once")
		check(neon._mesh_texts[0]["mesh"].material_override != original_material, "localized neon owns its material without modifying the imported resource")
		check(LocalizedModelText.attach_neon(sign, entry[2]) == neon, "neon setup is idempotent")
	for locale in ["en", "de", "es", "fr", "pl"]:
		Localization.set_locale(locale)
		check(Localization.text("GOOD LUCK") == {"en": "GOOD LUCK", "de": "VIEL GLÜCK", "es": "BUENA SUERTE", "fr": "BONNE CHANCE", "pl": "POWODZENIA"}[locale], "model catalog is registered for " + locale)
		check(table_button.label.text == Localization.format_text("ADD TO DECK %d/%d", [15, 30]), "formatted 3D button updates on locale change")
		var caption_width := table_button.label.font.get_string_size(table_button.label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, table_button.label.font_size).x * table_button.label.pixel_size
		check(caption_width <= table_button._label_available_size.x + 0.001 and table_collision.shape == table_shape, "long translated button caption fits without changing its hit target")
		for active_helper: LocalizedModelText in [helper] + signs:
			for entry: Dictionary in active_helper._mesh_texts:
				var replacement := entry["mesh"] as MeshInstance3D
				var letters := replacement.mesh as TextMesh
				var expected: AABB = entry["bounds"]
				var bounds: AABB = replacement.transform * replacement.get_aabb()
				check(letters.text == Localization.text(entry["source"]), "3D mesh text refreshes to " + locale)
				check(bounds.size.x <= expected.size.x + 0.001 and bounds.size.z <= expected.size.z + 0.001 and bounds.get_center().distance_to(expected.get_center()) < 0.001, "translated mesh remains centered within the original sign footprint")
		for entry: Dictionary in helper._atlas_labels:
			check(entry["label"].text == Localization.text(entry["source"]) and entry["label"].pixel_size > 0.0, "atlas sign refreshes with a positive fitted font size")
		for action: String in button_transforms:
			check(slot._button_meshes[action].transform == button_transforms[action] and slot.button_areas[action] == button_areas[action], "locale switch preserves button geometry and collision")
		check(not slot.is_spinning and slot.reel_pivots.size() == 3, "locale switch never starts a spin or rebuilds reels")
	Localization.set_locale("de")
	slot.queue_free()
	await get_tree().process_frame
	if failures == 0:
		print("MODEL_LOCALIZATION_TESTS: PASS (%d checks)" % checks)
	else:
		print("MODEL_LOCALIZATION_TESTS: FAIL (%d / %d checks)" % [failures, checks])
	get_tree().quit(1 if failures else 0)
