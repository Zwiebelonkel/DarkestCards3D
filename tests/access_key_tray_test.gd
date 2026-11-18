extends Node3D
## Access-key persistence and real lower-edge tray input in Main's shared camera.

class FailingCollection extends "res://scripts/autoload/CollectionManager.gd":
	func _save_collection_snapshot(_snapshot: Dictionary, _suffix: String = ".tmp") -> bool:
		return false

const KEYS: Array[String] = ["slot_room_key", "black_market_access", "graveyard_key", "basement_key"]
const AREAS: Array[String] = ["slot_room", "black_market", "graveyard", "basement"]

var checks := 0
var failures := 0
var viewport: SubViewport
var main: MainScene
var tray: AccessKeyTray
var requests: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func _settle(seconds: float = 0.08) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().physics_frame
	await get_tree().process_frame


func _wait_until(predicate: Callable, timeout_ms: int = 8000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not bool(predicate.call()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/") or not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Use the isolated runner to protect player saves.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	_check_backend()
	CollectionManager.clear_profile_state()
	DeckManager.clear_profile_state()
	CardUpgradeManager.clear_profile_state()
	CollectionManager.add_card("corpse")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.mouse_tilt_strength = 0.0
	main.wakeup_blur_duration = 0.01
	main.rotation_duration = 0.08
	main.settle_duration = 0.04
	main.door_key_look_duration = 0.25
	viewport.add_child(main)
	tray = main.access_key_tray
	tray.key_requested.connect(func(card_id: String): requests.append(card_id))
	_move_pointer(Vector2(640, 360))
	await _settle(0.45)
	check(tray.get_parent() == main.main_camera and not tray.is_expanded(), "the real 3D key tray starts folded beneath the exploration camera")
	check(tray._key_tiles.is_empty() and tray.empty_label.visible, "combat ownership alone leaves the key tray empty")
	CollectionManager.add_card(KEYS[0])
	await _settle()
	check(tray._key_tiles.keys() == [KEYS[0]], "acquiring a key immediately adds only that owned unused key")
	for card_id in KEYS.slice(1):
		CollectionManager.add_card(card_id)
	await _settle()
	check(_tile_ids() == _sorted(KEYS), "all four owned unused access keys appear together")
	await _check_hover_and_gates()
	await _check_world_focus()
	var retained_instances := CollectionManager.get_card_instances().duplicate(true)
	var coins_before := GameCurrency.get_coin_cents()
	for card_id in KEYS:
		await _use_key_in_main(card_id)
	check(CollectionManager.get_card_instances() == retained_instances and GameCurrency.get_coin_cents() == coins_before and DeckManager.battle_deck.is_empty(), "using all four tray actions keeps exact card instances, balance and combat deck unchanged")
	check(tray._key_tiles.is_empty() and not tray.visible and not tray._can_display(), "after all four activations the entire tray and its hinges disappear and cannot receive input")
	CollectionManager.reload_profile()
	await _settle()
	check(CollectionManager.get_unused_access_key_ids().is_empty() and tray._key_tiles.is_empty() and not tray.visible, "reload keeps the completed key tray hidden")
	var wall_preserved := true
	for card_id in KEYS:
		wall_preserved = wall_preserved and main.upgrade_collection._cards.has(card_id) and CollectionManager.get_amount(card_id) == 1
	check(wall_preserved, "all four used keys remain owned and displayed in the special wall collection")
	await _open_tray()
	check(not tray.is_expanded() and not tray.is_visible_in_tree(), "bottom-edge hover cannot reopen the tray after every key was used")
	await _capture("all-used")
	CollectionManager.add_card_instance(CardData.create_instance("toilet_paper"))
	await _settle()
	await _open_tray()
	check(tray.is_visible_in_tree() and _tile_ids() == ["toilet_paper"], "the collected Klopapier key appears without reviving used door keys")
	var requests_before := requests.size()
	await _click_at(main.main_camera.unproject_position(tray._key_tiles["toilet_paper"].global_position))
	check(requests.size() == requests_before and not main._room_transition_active, "clicking the collectible Klopapier key cannot request or open a door")
	check(tray.hint_label.text == Localization.text("Klopapier beim Gefangenen verwenden."), "the tray explains where to use Klopapier")
	_move_pointer(Vector2(640, 360))
	await _settle(0.4)
	var basement_door := _door_for("basement_key")
	await _click_at(main.main_camera.unproject_position(basement_door.doorway_area.global_position))
	check(main._room_transition_active, "an explicitly used basement key permits a normal physical doorway click")
	check(await _wait_until(func(): return main._active_room == 3 and not main._room_transition_active), "normal doorway travel reaches the basement after tray activation")
	_finish()


func _check_backend() -> void:
	CollectionManager.clear_profile_state()
	CollectionManager.add_card("corpse")
	check(CollectionManager.get_unused_access_key_ids().is_empty() and not CollectionManager.use_access_key("slot_room_key") and not CollectionManager.use_access_key("corpse"), "unowned keys and ordinary cards cannot be activated")
	for index in range(KEYS.size()):
		var card_id := KEYS[index]
		check(CardData.is_access_key(CardDatabase.get_card(card_id)) and CollectionManager.get_access_key_area_id(card_id) == AREAS[index], card_id + " maps to its intended room")
		CollectionManager.add_card(card_id)
	check(_sorted(CollectionManager.get_unused_access_key_ids()) == _sorted(KEYS), "all four owned keys start unused")
	var unchanged := CollectionManager.collection.duplicate(true)
	var saved := FileAccess.get_file_as_string(CollectionManager.SAVE_PATH)
	var failing := FailingCollection.new()
	failing.collection = unchanged.duplicate(true)
	var changed: Array = []
	failing.collection_changed.connect(func(ids: Array[String]): changed.append(ids))
	for card_id in KEYS:
		check(not failing.use_access_key(card_id) and not failing.is_access_key_used(card_id) and not failing.has_area_access(failing.get_access_key_area_id(card_id)), card_id + " save failure cannot mark the key used or permit room access")
	check(failing.collection == unchanged and changed.is_empty() and FileAccess.get_file_as_string(CollectionManager.SAVE_PATH) == saved, "failed activations preserve inventory, metadata, notifications and committed save bytes")
	failing.free()
	for card_id in KEYS:
		check(not CollectionManager.has_area_access(CollectionManager.get_access_key_area_id(card_id)) and not CollectionManager.is_access_key_used(card_id), card_id + " ownership alone cannot permit room access")
	# JSON persistence normalizes integer levels to floats on reload.
	var instances: Array = JSON.parse_string(JSON.stringify(CollectionManager.get_card_instances()))
	for card_id in KEYS:
		check(CollectionManager.use_access_key(card_id) and CollectionManager.is_access_key_used(card_id) and CollectionManager.has_area_access(CollectionManager.get_access_key_area_id(card_id)) and not CollectionManager.get_unused_access_key_ids().has(card_id), card_id + " successful activation grants access and removes only its unused action")
		var used_snapshot := CollectionManager.collection.duplicate(true)
		check(not CollectionManager.use_access_key(card_id) and CollectionManager.collection == used_snapshot, card_id + " repeated activation is a no-op")
	CollectionManager.reload_profile()
	check(CollectionManager.get_unused_access_key_ids().is_empty() and CollectionManager.get_card_instances() == instances, "all used flags and exact owned key instances survive reload")
	CollectionManager.collection = {"cards": {}, "instances": [], "metadata": {"slot_room_unlocked": true, "area_access": {"black_market": true, "graveyard": true, "basement": true}}}
	CollectionManager.save_collection()
	CollectionManager.reload_profile()
	check(AREAS.all(func(area_id: String): return CollectionManager.has_area_access(area_id)) and KEYS.all(func(card_id: String): return CollectionManager.is_access_key_used(card_id)), "legacy persisted activation flags retain access without requiring another key use")


func _check_hover_and_gates() -> void:
	_move_pointer(Vector2(640, 690))
	await _settle()
	check(not tray.is_expanded(), "ordinary lower-screen movement does not prematurely open the tray")
	await _open_tray()
	check(tray.is_expanded() and absf(tray.hinge.rotation_degrees.x) < 1.0, "hovering the bottom edge fully unfolds the physical tray")
	var art_correct := true
	for card_id in KEYS:
		var art := (tray._key_tiles[card_id] as Node3D).get_node("Art") as Sprite3D
		art_correct = art_correct and art.texture.resource_path == str(CardDatabase.get_card(card_id).get("image", ""))
	check(art_correct, "all tray entries render their actual access-card artwork")
	await _capture("four-keys")
	_move_pointer(Vector2(640, 360))
	await _settle(0.4)
	check(not tray.is_expanded() and is_equal_approx(tray.hinge.rotation_degrees.x, AccessKeyTray.STOWED_ANGLE), "moving above the panel folds it completely away")
	tray.set_enabled(false)
	tray.set_pointer_position(Vector2(640, 719))
	check(not tray.is_expanded(), "disabled tray ignores bottom-edge hover")
	await _settle()
	await _open_tray()
	tray.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(not tray.is_expanded(), "losing window focus immediately stows the tray")
	tray.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	await _open_tray()
	main.pause_menu.open()
	await _settle()
	check(get_tree().paused and not tray.is_expanded(), "Pause stows the tray before any key can be used")
	main._on_access_key_requested(KEYS[0])
	check(not CollectionManager.is_access_key_used(KEYS[0]) and not main._room_transition_active, "queued activation cannot use a key through Pause")
	main.pause_menu.close()
	_move_pointer(Vector2(640, 360))
	await _settle()
	main._toggle_journal()
	await _settle()
	_move_pointer(Vector2(640, 719))
	await _settle()
	check(main._is_journal_active() and not tray.is_expanded(), "the journal modal blocks lower-edge tray activation")
	main.journal.close_journal(true)
	_move_pointer(Vector2(640, 360))
	await _settle()
	await _open_tray()
	main._request_turn(-1)
	check(not tray.is_expanded(), "starting a camera turn stows the expanded tray immediately")
	_move_pointer(Vector2(640, 360))
	await _settle(0.3)


func _check_world_focus() -> void:
	await _turn_to(1)
	var screen := main.scene_pivot.get_node("PackShopMachine/ScreenArea") as Area3D
	_move_pointer(main.main_camera.unproject_position(screen.global_position))
	await _settle(0.5)
	check(main.screen_camera_focus.is_focused(), "real shop hover still focuses its station before opening the key tray")
	await _open_tray()
	check(not main.screen_camera_focus.is_focused() and main.main_camera.position.is_equal_approx(main.screen_camera_focus._base_position), "opening the tray releases the shop focus and settles its own screen-space layout")
	_move_pointer(Vector2(640, 360))
	await _settle(0.4)


func _use_key_in_main(card_id: String) -> void:
	var door := _door_for(card_id)
	check(door.locked and not CollectionManager.has_area_access(CollectionManager.get_access_key_area_id(card_id)), card_id + " room stays locked until its explicit tray action")
	await _open_tray()
	if not tray._key_tiles.has(card_id):
		check(false, card_id + " remains available before its first activation")
		return
	var tile := tray._key_tiles[card_id] as Node3D
	var point := main.main_camera.unproject_position(tile.global_position)
	var request_count := requests.size()
	await _click_at(point, MOUSE_BUTTON_RIGHT)
	check(requests.size() == request_count and not CollectionManager.is_access_key_used(card_id), card_id + " right click cannot activate its tray entry")
	await _click_at(point)
	check(requests.size() == request_count + 1 and requests.back() == card_id and main._room_transition_active, card_id + " real left click requests exactly its own door reveal")
	check(not tray.is_expanded() and not CollectionManager.is_access_key_used(card_id), card_id + " remains unused until the camera finishes looking at its door")
	check(await _wait_until(func(): return not main._room_transition_active), card_id + " door reveal finishes within bounded time")
	await _settle()
	var target := door.doorway_area.global_position
	var projected := main.main_camera.unproject_position(target)
	check(CollectionManager.is_access_key_used(card_id) and not tray._key_tiles.has(card_id) and not door.locked, card_id + " successful reveal opens access and removes its tray tile")
	check(not main.main_camera.is_position_behind(target) and viewport.get_visible_rect().has_point(projected) and absf(projected.x - 640.0) < 55.0, card_id + " opens the intended physical doorway in the center of the camera")
	check(is_equal_approx(door.hinge.rotation.y, deg_to_rad(door.travel_open_degrees)) and main._active_room == 0, card_id + " door visibly swings open without teleporting the player")
	await _capture("opened-" + card_id)
	main._on_access_key_requested(card_id)
	check(not main._room_transition_active, card_id + " duplicate activation cannot replay the camera sequence")


func _door_for(card_id: String) -> HospitalDoor:
	if card_id == "slot_room_key":
		return main.hub_door
	var area_id := CollectionManager.get_access_key_area_id(card_id)
	for area in main.progression_areas:
		if area.area_id == area_id:
			return area.door
	return null


func _turn_to(side: int) -> void:
	_move_pointer(Vector2(640, 360))
	for attempt in range(4):
		if main._active_side == side:
			return
		main._request_turn(-1)
		await _settle(0.3)
	check(false, "normal camera turns reach the requested hub side")


func _open_tray() -> void:
	_move_pointer(Vector2(640, 719))
	await _settle(0.6)


func _move_pointer(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	viewport.push_input(event, true)


func _click_at(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	_move_pointer(point)
	await _settle(0.03)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = button
		event.pressed = pressed
		viewport.push_input(event, true)
		await get_tree().physics_frame
		await get_tree().process_frame


func _tile_ids() -> Array[String]:
	var ids: Array[String] = []
	for card_id: String in tray._key_tiles:
		ids.append(card_id)
	return _sorted(ids)


func _sorted(ids: Array[String]) -> Array[String]:
	var result := ids.duplicate()
	result.sort()
	return result


func _capture(stage: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png("res://access-key-tray-%s.png" % stage) == OK, "rendered evidence: " + stage)


func _finish() -> void:
	if get_tree().paused:
		get_tree().paused = false
	if is_instance_valid(main):
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	print("ACCESS_KEY_TRAY_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
