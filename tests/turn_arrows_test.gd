extends Node3D

class WorldClickProbe extends Node:
	var clicks := 0
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			clicks += 1

var checks := 0
var failures := 0
var viewport: SubViewport
var main: MainScene
var arrows: TurnArrows
var probe: WorldClickProbe


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + message)
	if not condition:
		failures += 1


func _run() -> void:
	if not SettingsManager.CONFIG_PATH.begins_with("res://test-user/") or not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		push_error("Run turn_arrows_test through the isolated match feature runner.")
		get_tree().quit(1)
		return
	var saved_setting := SettingsManager.turn_arrows_enabled
	SettingsManager.set_turn_arrows_enabled(true)
	CollectionManager.add_card(CollectionManager.SLOT_ROOM_KEY_ID)
	CollectionManager.unlock_slot_room()
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.physics_object_picking = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.notify_mouse_entered()
	if DisplayServer.get_name() != "headless":
		var preview := TextureRect.new()
		preview.size = Vector2(viewport.size)
		preview.texture = viewport.get_texture()
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(preview)
	main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as MainScene
	main.mouse_tilt_strength = 0.0
	main.wakeup_blur_duration = 0.01
	main.rotation_duration = 0.04
	main.settle_duration = 0.04
	main.room_travel_duration = 0.25
	main.debug_interaction_clicks = false
	viewport.add_child(main)
	arrows = main.turn_arrows
	probe = WorldClickProbe.new()
	main.add_child(probe)
	_move(Vector2(640, 400))
	await _settle(0.2)
	check(main._can_turn() and _hidden(), "hub starts turnable with no arrow away from edges")
	check(arrows.layer < (main.dirty_lens.get_parent() as CanvasLayer).layer and arrows.layer < (main.main_camera.get_node("CanvasLayer2") as CanvasLayer).layer, "arrows draw below both original camera filters")
	var lens := main.dirty_lens.material
	var grading: Material = main.main_camera.get_node("CanvasLayer2/ColorRect").material
	_move(Vector2(36, 400))
	await _settle()
	check(arrows.left_button.visible and not arrows.right_button.visible, "only the nearby left edge arrow appears")
	var side := main._active_side
	await _settle(0.15)
	check(main._active_side == side, "hover alone never rotates")
	await _capture("left")
	var before_clicks := probe.clicks
	var point := arrows.left_button.get_global_rect().get_center()
	_mouse(point, true)
	check(main._phase == MainScene.Phase.IDLE, "mouse down alone does not turn")
	var pressed_position := arrows.left_button.position
	_move(point + Vector2(0, 150))
	await _settle()
	check(arrows.left_button.position == pressed_position, "held arrow does not chase a dragged pointer")
	_mouse(point + Vector2(0, 150), false)
	await _settle()
	check(main._active_side == side, "releasing outside the original button cancels rotation")
	check(probe.clicks == before_clicks, "arrow mouse press cannot reach underlying world input")
	await _click_arrow(-1)
	check(main._active_side == posmod(side + 1, 4), "left arrow uses the A direction")
	check(_hidden(), "rotation hides both arrows until the camera settles")
	await _rest()
	await _click_arrow(1)
	check(main._active_side == side, "right arrow uses the D direction")
	await _rest()
	_move(Vector2(1244, 400))
	await _settle()
	await _capture("right")
	check(arrows.right_button.visible and not arrows.left_button.visible, "only the nearby right edge arrow appears")
	check(main.dirty_lens.material == lens and main.main_camera.get_node("CanvasLayer2/ColorRect").material == grading, "navigation preserves filter material identities")
	SettingsManager.set_turn_arrows_enabled(false)
	check(_hidden() and main._can_turn(), "live setting hides arrows without disabling keyboard turning")
	SettingsManager.set_turn_arrows_enabled(true)
	check(arrows.right_button.visible, "live setting restores arrow without reopening Main")
	# A/D may still redirect an active camera animation as before.
	_key_action(main.input_action_right)
	await _settle(0.01)
	var keyboard_side := main._active_side
	_key_action(main.input_action_right)
	await _settle(0.01)
	check(main._active_side == posmod(keyboard_side - 1, 4), "A/D preserves mid-animation turn interruption")
	await _rest()
	await _check_blockers()
	for room in range(2):
		if room == 1:
			main._on_room_door_activated(main.hub_door)
			check(main._room_transition_active and not main._can_turn(false), "real room flight blocks turning")
			check(await _wait_until(func(): return not main._room_transition_active), "room flight finishes")
			check(main._active_room == 1, "arrow fixture reaches the actual slot room")
		for direction in [-1, 1]:
			for step in range(4):
				var old_side := main._active_side
				await _click_arrow(direction)
				check(main._active_side == posmod(old_side - direction, 4), "arrow reaches next cardinal side in room %d, direction %d, step %d" % [room, direction, step])
				await _rest()
	_move(Vector2(36, 2))
	await _settle()
	check(arrows.left_button.get_global_rect().position.y >= 0, "arrow remains inside top edge")
	viewport.size = Vector2i(800, 900)
	_move(Vector2(764, 899))
	await _settle()
	check(Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(arrows.right_button.get_global_rect()), "arrow adapts to narrow viewport and stays inside bottom/right edges")
	_move(Vector2(-1, 899))
	viewport.notify_mouse_exited()
	await _settle()
	check(_hidden(), "leaving the viewport hides both arrows")
	SettingsManager.set_turn_arrows_enabled(saved_setting)
	main.queue_free()
	await _settle()
	print("TURN_ARROWS_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _check_blockers() -> void:
	var collection := main.scene_pivot.get_node("Collection") as CollectionScreen
	var table := main.scene_pivot.get_node("GameTable") as GameTable
	for entry in [
		[main, "_room_transition_active"], [main, "_loss_cinematic_active"],
		[main, "_pack_opening_blocks_screen_focus"], [collection, "_detail_tween_running"],
		[collection, "_deck_fan_open"], [collection, "_deck_fan_tween_running"],
		[collection, "_slot_room_key_request_pending"], [main.fusion_workbench, "_busy"]
	]:
		entry[0].set(entry[1], true)
		arrows.refresh()
		var old_side := main._active_side
		check(_hidden() and not main._request_turn(1) and main._active_side == old_side, "shared mouse/keyboard guard blocks " + str(entry[1]))
		entry[0].set(entry[1], false)
	main.table_lobby.show()
	arrows.refresh()
	check(_hidden() and not main._can_turn(), "visible lobby blocks both turn inputs")
	main.table_lobby.hide()
	for state in [GameTable.TableState.PLAYING, GameTable.TableState.GAME_OVER]:
		table._table_state = state
		arrows.refresh()
		check(_hidden() and not main._can_turn(), "battle/result blocks rotation even away from table side")
	table._table_state = GameTable.TableState.MENU
	main.pause_menu.open()
	await _settle()
	check(get_tree().paused and _hidden() and not main._request_turn(1), "offline pause hides arrows while their presentation still processes")
	SettingsManager.set_turn_arrows_enabled(false)
	SettingsManager.set_turn_arrows_enabled(true)
	check(_hidden(), "setting changes cannot reveal arrows over paused settings")
	main.pause_menu._open_settings()
	await _settle()
	check(_hidden() and not main._can_turn(), "actual settings screen blocks rotation")
	main.pause_menu.close()
	await _settle()
	main._toggle_journal()
	arrows.refresh()
	check(main.journal.is_active() and _hidden() and not main._request_turn(1), "journal opening immediately blocks arrows and keyboard")
	main.journal.close_journal(true)
	await _settle()
	main.upgrade_collection._detail_phase = UpgradeWallCollection.DetailPhase.OPENING
	arrows.refresh()
	check(_hidden() and not main._can_turn(), "upgrade detail transition blocks arrows")
	main.upgrade_collection._detail_phase = UpgradeWallCollection.DetailPhase.CLOSED
	_move(Vector2(1244, 400))
	await _settle()
	check(main._can_turn() and arrows.right_button.visible, "all temporary locks release without rebuilding arrows")


func _hidden() -> bool:
	return not arrows.left_button.visible and not arrows.right_button.visible


func _move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	viewport.push_input(event, true)


func _mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	viewport.push_input(event, true)


func _click_arrow(direction: int) -> void:
	_move(Vector2(36 if direction < 0 else viewport.size.x - 36, 400))
	await _settle()
	var button := arrows.left_button if direction < 0 else arrows.right_button
	check(button.visible, "requested edge arrow is visible before click")
	var count := probe.clicks
	var point := button.get_global_rect().get_center()
	_mouse(point, true)
	_mouse(point, false)
	check(probe.clicks == count, "complete arrow click is consumed before world interaction")


func _key_action(action: String) -> void:
	Input.action_release(action)
	Input.action_press(action)
	main._read_input()
	Input.action_release(action)


func _rest() -> void:
	check(await _wait_until(func(): return main._phase == MainScene.Phase.IDLE), "camera settles on its cardinal target")


func _settle(seconds: float = 0.04) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame


func _wait_until(predicate: Callable, timeout_msec: int = 4000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())


func _capture(stage: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://turn-arrows-" + stage + ".png")
