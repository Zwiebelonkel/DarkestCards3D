extends Node3D

var checks := 0
var failures := 0
var viewport: SubViewport
var main: MainScene
var jester: GraveyardJester
var focus: ScreenCameraFocus

const DIALOGUE_SENTENCES_SOURCE := "Ich wurde hier draußen zurückgelassen.\nMein Auge wurde mir genommen.\nAlles wurde mir genommen.\nWürdest du bitte ein Opfer hierlassen?"
const OFFERING_LABELS := {
	"de": ["Opfern", "Nicht opfern"],
	"en": ["Sacrifice", "Do not sacrifice"],
	"es": ["Sacrificar", "No sacrificar"],
	"fr": ["Sacrifier", "Ne pas sacrifier"],
	"pl": ["Poświęć", "Nie poświęcaj"],
}


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func settle(seconds: float = 0.1) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().physics_frame
	await get_tree().process_frame


func wait_until(predicate: Callable, timeout_ms: int = 6000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/") or not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Run only in an isolated project copy with redirected saves.")
		get_tree().quit(1)
		return
	CollectionManager.clear_profile_state()
	DeckManager.clear_profile_state()
	CardUpgradeManager.clear_profile_state()
	GameCurrency.set_process(false)
	GameCurrency._rescued_npcs["jester"] = true
	for id in ["chick", "harald", "graveyard_key"]:
		CollectionManager.add_card(id)
	check(CollectionManager.use_access_key("graveyard_key"), "Jester fixture explicitly activates graveyard access")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.world_3d = World3D.new()
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.wakeup_blur_duration = 0.05
	main.mouse_tilt_strength = 0.0
	main.rotation_duration = 0.03
	main.settle_duration = 0.03
	main.room_travel_duration = 0.25
	viewport.add_child(main)
	jester = main.graveyard_jester
	focus = main.screen_camera_focus
	_move_pointer(Vector2(-50, -50))
	await settle(0.5)
	var base_position := main.main_camera.position
	var base_fov := main.main_camera.fov
	check(not jester.focus_area.input_ray_pickable and not jester.open_dialog(), "Jester is unavailable from the hub")
	var door: HospitalDoor
	for area in main.progression_areas:
		if area.area_id == "graveyard":
			door = area.door
	main._on_room_door_activated(door)
	check(await wait_until(func(): return main._active_room == 2 and not main._room_transition_active), "actual door flight enters the graveyard")
	await _turn_to(jester.view_side)
	check(jester.focus_area.input_ray_pickable and focus._screens.get(jester.focus_area) == jester.view_side, "west view registers and enables the Jester station")
	await _capture("before")
	var old_distance := main.main_camera.global_position.distance_to(jester.npc_area.global_position)
	var actor := jester.get_node("jester") as Sprite3D
	var idle_texture := actor.texture
	actor.frame = 7
	actor.set("_frame_timer", 0.04)
	_move_pointer(main.main_camera.unproject_position(jester.npc_area.global_position))
	jester._update_pointer_hover()
	check(actor.texture.resource_path == "res://assets/characters/jester/jesterHover.png" and actor.frame == 7 and is_equal_approx(actor.get("_frame_timer"), 0.04), "Jester hover preserves the current frame and its elapsed time")
	_move_pointer(Vector2(-50, -50))
	jester._update_pointer_hover()
	check(actor.texture == idle_texture and actor.frame == 7 and is_equal_approx(actor.get("_frame_timer"), 0.04), "leaving the Jester restores idle at the same animation phase")
	_move_pointer(main.main_camera.unproject_position(jester.npc_area.global_position))
	await settle(0.55)
	check(actor.texture.resource_path.ends_with("jesterHover.png") and actor.frame != 7, "Jester hover animation continues during camera focus")
	check(focus.is_focused() and focus._hovered_screen == jester.focus_area, "real NPC hover starts the shared station focus")
	var foreign_screen := main.scene_pivot.get_node("PackShopMachine/ScreenArea") as Area3D
	foreign_screen.input_ray_pickable = true
	check(not focus._is_screen_available_for_active_side(foreign_screen), "same-side shop in another room remains excluded even if erroneously pickable")
	focus._on_screen_mouse_entered(foreign_screen)
	check(focus._hovered_screen == jester.focus_area, "foreign-room mouse enter cannot replace the Jester focus")
	foreign_screen.input_ray_pickable = false
	check(main.main_camera.global_position.distance_to(jester.npc_area.global_position) < old_distance - 0.5, "hover swings the camera closer to the NPC")
	var focused_position := main.main_camera.position
	await settle(0.5)
	check(main.main_camera.position.distance_to(focused_position) < 0.01, "station focus remains stable without pointer movement")
	await _capture("focused")
	_click(main.main_camera.unproject_position(jester.npc_area.global_position))
	check(await wait_until(func(): return jester.is_dialog_open()), "actual NPC click opens its dialog")
	check(actor.texture == idle_texture, "Jester dialog clears the hover hint")
	check(not jester._choice_buttons.visible, "the real NPC conversation keeps the offering buttons hidden")
	var dialogue_sentences := _dialogue_sentences()
	var first_sentence := dialogue_sentences[0] if not dialogue_sentences.is_empty() else ""
	check(dialogue_sentences.size() == 4 and jester._body_label.text == first_sentence and jester._body_label.visible_characters >= 0 and jester._body_label.visible_characters < jester._body_label.get_total_character_count(), "the real dialog begins by typewriting only its first localized sentence")
	check(not main._can_turn() and not main._can_travel_between_rooms() and not main._can_open_journal(), "dialog locks turning, doors and the book")
	_move_pointer(Vector2(-50, -50))
	await settle(0.45)
	check(focus.is_focused() and main.main_camera.position.distance_to(focused_position) < 0.01, "dialog keeps the station framing while reading")
	for locale: String in Localization.SUPPORTED_LOCALES:
		Localization.set_locale(locale)
		check(jester.get_node("Burials/Grave_27/Inscription").text == Localization.text("Chick") and jester.get_node("Burials/Grave_28/Inscription").text == Localization.text("Harald"), "gravestones use their localized card names in " + locale)
		dialogue_sentences = _dialogue_sentences()
		first_sentence = dialogue_sentences[0] if not dialogue_sentences.is_empty() else ""
		check(dialogue_sentences.size() == 4 and jester._body_label.text == first_sentence and not jester._body_label.text.contains("\n"), "dialog keeps only its first localized sentence visible in " + locale)
		jester._body_label.visible_characters = -1
		await _capture("dialog-" + locale)
	Localization.set_locale("de")
	dialogue_sentences = _dialogue_sentences()
	jester._body_label.visible_characters = -1
	_click(jester._panel.get_global_rect().get_center())
	await get_tree().process_frame
	var second_sentence := dialogue_sentences[1] if dialogue_sentences.size() > 1 else ""
	check(jester.is_busy() and jester._body_label.text == second_sentence and jester._body_label.visible_characters >= 0 and jester._body_label.visible_characters < jester._body_label.get_total_character_count(), "a completed first sentence clears before the real scene starts the second on click")
	_escape()
	await wait_until(func(): return not jester.is_busy())
	check(not jester.is_busy() and not main.pause_menu.visible, "Escape closes dialog without also opening pause")
	# Both physical headstones remain independently clickable after camera focus.
	await _click_area(jester.grave_areas["chick"] as Area3D)
	check(await wait_until(func(): return jester._mode == GraveyardJester.Mode.CANDIDATE and jester._candidate.get("ok", false)), "first gravestone offers its requested owned copy")
	check(jester._preview_card != null and str(jester._preview_card.card_data.get("id")) == "chick", "offering preview shows the exact requested card")
	check(jester._preview_entry_progress < 1.0 and jester._sacrifice_button.disabled, "actual offering card enters with the dialog before confirmation becomes available")
	await _capture("offering-entry")
	var before_cancel := CollectionManager.collection.duplicate(true)
	var cancel_bytes := FileAccess.get_file_as_string(CollectionManager.SAVE_PATH)
	_click(Vector2(8, 8))
	check(jester._mode == GraveyardJester.Mode.CANDIDATE and CollectionManager.collection == before_cancel, "outside click leaves the candidate and its copy untouched")
	await _click_choice(jester._decline_button)
	await wait_until(func(): return not jester.is_busy())
	check(not jester.is_busy() and CollectionManager.collection == before_cancel and FileAccess.get_file_as_string(CollectionManager.SAVE_PATH) == cancel_bytes, "Do not sacrifice closes without saving, consuming, or awarding any card")
	await _click_area(jester.grave_areas["chick"] as Area3D)
	check(await wait_until(func(): return jester._mode == GraveyardJester.Mode.CANDIDATE and jester._candidate.get("ok", false)), "the canceled exact copy can be reviewed again")
	for locale: String in Localization.SUPPORTED_LOCALES:
		Localization.set_locale(locale)
		await settle(0.3)
		check(jester._sacrifice_button.text == OFFERING_LABELS[locale][0] and jester._decline_button.text == OFFERING_LABELS[locale][1], "offering button labels update in " + locale)
		check(jester._panel.get_global_rect().encloses(jester._sacrifice_button.get_global_rect()) and jester._panel.get_global_rect().encloses(jester._decline_button.get_global_rect()), "both offering buttons remain inside the dialog in " + locale)
		await _capture("offering-" + locale)
	Localization.set_locale("de")
	await _capture("offering")
	await _click_choice(jester._sacrifice_button)
	check(await wait_until(func(): return CollectionManager.get_jester_offering_state()["offered"].has("chick")), "the Sacrifice button consumes the first reviewed offering")
	check(CollectionManager.get_amount("chick") == 0 and not CollectionManager.get_jester_offering_state()["completed"], "first offering persists without granting a premature Secret")
	await settle(1.1)
	_click(jester._panel.get_global_rect().get_center())
	await wait_until(func(): return not jester.is_busy())
	check(not jester.is_busy(), "a click inside the acknowledgement closes it")
	CollectionManager.reload_profile()
	check(CollectionManager.get_jester_offering_state()["offered"].has("chick"), "partial progress survives collection reload in the real scene")
	await settle(0.5)
	await _click_area(jester.grave_areas["harald"] as Area3D)
	check(await wait_until(func(): return jester._mode == GraveyardJester.Mode.CANDIDATE and jester._candidate.get("ok", false)), "second gravestone accepts Harald independently")
	await _click_choice(jester._sacrifice_button)
	check(await wait_until(func(): return CollectionManager.get_jester_offering_state()["completed"]), "second offering commits the one-time reward")
	await settle(1.8)
	check(jester._preview_card != null and str(jester._preview_card.card_data.get("rarity")) == "secret", "Jester presents the awarded Secret with its real card material")
	await _capture("reward")
	var saved := CollectionManager.collection.duplicate(true)
	_click(Vector2(8, 8))
	await wait_until(func(): return not jester.is_busy())
	check(not jester.is_busy() and CollectionManager.collection == saved, "closing the receipt by outside click cannot grant a second Secret")
	check(jester.open_dialog(), "the completed NPC can speak again before the pause regression")
	main.pause_menu.open()
	await get_tree().create_timer(0.35).timeout
	check(not jester.is_busy() and not jester.focus_area.input_ray_pickable, "pausing immediately closes the text dialogue and disables the station")
	check(main.main_camera.position.distance_to(base_position) < 0.01 and is_equal_approx(main.main_camera.fov, base_fov), "pause restores the camera before the tree stops")
	main.pause_menu.close()
	await settle(0.2)
	_move_pointer(Vector2(-50, -50))
	await _turn_to(2)
	main._on_room_door_activated(jester.get_node("ReturnDoor") as HospitalDoor)
	check(await wait_until(func(): return main._active_room == 0 and not main._room_transition_active), "the player can turn and leave through the real door after the offering")
	check(not jester.focus_area.input_ray_pickable and main.main_camera.position.distance_to(base_position) < 0.01, "leaving clears Jester focus and restores the hub camera")
	main.queue_free()
	await settle()
	viewport.queue_free()
	await get_tree().process_frame
	print("JESTER_FOCUS_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _turn_to(side: int) -> void:
	for attempt in range(8):
		if main._active_side == side:
			break
		main._request_turn(-1)
		await settle(0.18)
	check(main._active_side == side, "room turning reaches the requested view")
	await settle(0.35)


func _click_area(area: Area3D) -> void:
	_move_pointer(main.main_camera.unproject_position(area.global_position))
	await settle(0.5)
	_click(main.main_camera.unproject_position(area.global_position))


func _click_choice(button: Button) -> void:
	await settle(GraveyardJester.PANEL_SWIPE_DURATION + 0.05)
	_click(button.get_global_rect().get_center())


func _move_pointer(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)


func _click(point: Vector2) -> void:
	_move_pointer(point)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = point
		click.global_position = point
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		viewport.push_input(click, true)


func _escape() -> void:
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_ESCAPE
		key.physical_keycode = KEY_ESCAPE
		key.pressed = pressed
		viewport.push_input(key, true)


func _dialogue_sentences() -> PackedStringArray:
	return Localization.text(DIALOGUE_SENTENCES_SOURCE).split("\n")


func _capture(stage: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await settle(0.05)
	RenderingServer.force_draw(false)
	check(viewport.get_texture().get_image().save_png("res://jester-%s.png" % stage) == OK, "rendered evidence: " + stage)
