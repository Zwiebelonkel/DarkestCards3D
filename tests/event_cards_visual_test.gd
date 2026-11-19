extends Node

## Run through run_match_feature_tests.ps1 -Visual so saves and captures stay
## in its isolated project. Also works headlessly for layout assertions.
const EVENT_RULES := preload("res://scripts/events/EventDeck.gd")
var failures := 0
var _pointer_position := Vector2(30, 420)
var _hand_ui: Variant
@onready var root: Window = get_tree().root


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func _run() -> void:
	AudioServer.set_bus_mute(0, true)
	root.size = Vector2i(1280, 720)
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await get_tree().process_frame
	main.set_process(false)
	main.mouse_tilt_strength = 0.0
	# Compatibility-renderer bloom otherwise overexposes the existing table.
	# Keep the real camera/materials, but make geometry and status readable in QA.
	(main.get_node("WorldEnvironment") as WorldEnvironment).environment.glow_enabled = false
	var table := main.get_node("ScenePivot/GameTable") as GameTable
	table._clear_match()
	table._online_mode = false
	table._online_is_spectator = false
	table._table_state = GameTable.TableState.PLAYING
	table._current_turn = "player"
	table.menu_root.hide()
	table.matchmaking_screen.hide()
	table.match_hud.show_for_match(false)
	var visor := main.get_node("CameraPivot/CameraTilt/Camera3D/LevelProgress")
	visor.set_process(false)
	visor.set_expanded(false)
	for index in range(14):
		table._player_deck.append(_combat_card(index, "player"))
		table._enemy_deck.append(_combat_card(index + 7, "enemy"))
	for slot in range(5):
		table._draw_to_slot("player", slot, false)
		table._draw_to_slot("enemy", slot, false)
	table._rebuild_stack_visual("player")
	table._rebuild_stack_visual("enemy")
	table._rng.seed = 19
	table._initialize_event_deck()
	for event_id in ["switch", "block", "strength_150"]:
		for event in table._event_deck:
			if str(event.get("id", "")) == event_id:
				table._player_event_hand.append(event)
				table._event_deck.erase(event)
				break
	table._enemy_slots[2].apply_event_block(2)
	table._refresh_event_hand()
	table._move_camera_to_match_view()
	await get_tree().create_timer(0.85).timeout
	var hand_ui: Variant = table._event_hand_ui
	_hand_ui = hand_ui
	# Exercise the real hover geometry and animation without moving the user's
	# desktop mouse, which a visible Window queries independently of fake input.
	hand_ui.set_process(false)
	_push_pointer(Vector2(30, 420))
	await get_tree().create_timer(0.3).timeout
	check(hand_ui._cards.size() == 3, "actual match presents the three private event cards")
	check(hand_ui.mouse_filter == Control.MOUSE_FILTER_IGNORE, "empty hand surface leaves the table clickable")
	check(table._event_deck.size() == EventDeck.DECK_SIZE - 3, "the hidden logical event deck retains all undealt events")
	check(table.get_node_or_null("EventDeck") == null, "the table has no visible event-pile marker")
	check(table.find_child("EventDeckCount", true, false) == null, "the table has no rendered event-deck counter")
	check(table._enemy_slots[2]._event_block_badge.is_visible_in_tree(), "blocked table card shows its pinning knife")
	await _screenshot("event-cards-peek")
	await _capture_block_detail(table, "event-block-1280")
	_check_original_camera(table, "1280x720")
	var block_card: Control = hand_ui._cards[1]
	_push_pointer(Vector2(block_card.position.x + block_card.size.x * block_card.scale.x * 0.5, root.size.y - 20))
	await get_tree().create_timer(0.35).timeout
	check(hand_ui._hovered_uid == str(table._player_event_hand[1]["uid"]), "hovering the bottom edge raises the intended event")
	check(block_card.position.y < root.size.y - 220, "the hovered card exposes its full rules")
	await _screenshot("event-cards-hover")
	_push_pointer(Vector2(30, 420))
	table._on_event_selected(str(table._player_event_hand[1]["uid"]))
	await get_tree().create_timer(0.3).timeout
	_check_target_access(table, hand_ui)
	await _screenshot("event-cards-target-selection")
	table._cancel_event_selection()
	for definition in EVENT_RULES.definitions():
		if str(definition["id"]) == "steel":
			hand_ui.play_event(definition, true)
			break
	await get_tree().create_timer(0.33).timeout
	await _screenshot("event-cards-reveal")
	await get_tree().create_timer(0.6).timeout
	for definition: Dictionary in EVENT_RULES.definitions():
		if definition["id"] == "heal_event":
			hand_ui.play_event(definition, false)
			break
	await get_tree().create_timer(0.33).timeout
	await _screenshot("event-cards-heal")
	await get_tree().create_timer(0.6).timeout
	var rearrange: Dictionary = {}
	for definition: Dictionary in EVENT_RULES.definitions():
		if definition["id"] == "rearrange_event":
			rearrange = definition.duplicate(true)
			rearrange["uid"] = "rearrange-visual"
			break
	table._player_event_hand.append(rearrange)
	table._refresh_event_hand()
	table._on_event_selected(rearrange["uid"])
	table._on_event_target_clicked("player", 0)
	await get_tree().create_timer(0.2).timeout
	await _screenshot("event-cards-rearrange-first")
	var first := table._player_slots[0]
	var second := table._player_slots[3]
	table._on_event_target_clicked("player", 3)
	await get_tree().create_timer(0.33).timeout
	await _screenshot("event-cards-rearrange")
	await get_tree().create_timer(0.6).timeout
	check(table._player_slots[3] == first and table._player_slots[0] == second, "the actual match swaps the two chosen allied cards")
	# Keep the subsequent hand-layout fixtures independent of the played event.
	table._event_played_this_turn = false
	hand_ui.configure(table._player_event_hand, false, "", "", false)
	hand_ui.play_event(EVENT_RULES.definitions()[0], true)
	check(not hand_ui.visible and hand_ui._played_events_root.is_visible_in_tree(), "a spectator sees the public event reveal while the private hand stays hidden")
	check(hand_ui._played_events_root.get_child_count() > 0, "the public reveal creates a visible card for a spectator")
	hand_ui.clear_played_events()
	await get_tree().process_frame
	check(hand_ui._played_events_root.get_child_count() == 0, "match reset clears pending public reveals")
	root.size = Vector2i(800, 600)
	await get_tree().process_frame
	table._selected_event_uid = str(table._player_event_hand[2]["uid"])
	table._refresh_event_hand()
	await get_tree().create_timer(0.35).timeout
	await _screenshot("event-cards-narrow")
	await _capture_block_detail(table, "event-block-800")
	_check_original_camera(table, "800x600")
	_check_target_access(table, hand_ui)
	for card in hand_ui._cards:
		if card.visible:
			check(card.position.x >= 0 and card.position.x + card.size.x * card.scale.x <= root.size.x, "narrow hand keeps every shown card horizontally on screen")
	table.set_process(false)
	await _check_stacks(hand_ui)
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("EVENT_CARDS_VISUAL_TESTS: " + ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)


func _check_stacks(hand_ui: Variant) -> void:
	var hand: Array[Dictionary] = []
	hand_ui.configure(hand, false)
	var definitions := EVENT_RULES.definitions()
	# Interleave copies to exercise grouping independently of draw order.
	for index in [0, 3, 0, 1, 3, 4, 0, 5, 2]:
		var event := definitions[index].duplicate(true)
		event.erase("copies")
		event["uid"] = "stack-visual-%d" % hand.size()
		hand.append(event)
	root.size = Vector2i(1280, 720)
	await get_tree().process_frame
	hand_ui.configure(hand, true)
	_push_pointer(Vector2(30, 420))
	await get_tree().create_timer(0.3).timeout
	check(hand_ui._cards.size() == 6 and hand_ui._cards[0].instances.size() == 3 and hand_ui._cards[1].instances.size() == 2, "nine interleaved physical events appear as six distinct stacks with correct counts")
	check(hand_ui._status_label.text.contains("9"), "the hand status counts physical cards instead of visual stacks")
	await _screenshot("event-cards-stacked-peek")
	var stack: Control = hand_ui._cards[0]
	var edge := Vector2(stack.position.x + stack.size.x * stack.scale.x * 0.5, stack.position.y - 3.0)
	_push_pointer(edge)
	await get_tree().create_timer(0.35).timeout
	check(hand_ui._hovered_uid == stack.uid and stack.position.y < root.size.y - 220, "hovering an exposed stack edge raises its event card")
	await _screenshot("event-cards-stacked-hover")
	_push_pointer(Vector2(30, 420))
	root.size = Vector2i(800, 600)
	await get_tree().process_frame
	hand_ui.configure(hand, true, str(hand[7]["uid"]))
	await get_tree().create_timer(0.35).timeout
	check(hand_ui._page == 1 and hand_ui._cards[4].visible and hand_ui._cards[5].visible, "resizing keeps the selected stack visible using stack-based pagination")
	check(hand_ui._previous_button.visible and hand_ui._next_button.disabled, "narrow paging stops at the last stack page")
	await _screenshot("event-cards-stacked-narrow")
	hand_ui.configure(hand, true)
	hand_ui._change_page(-1)
	check(hand_ui._page == 0 and hand_ui._cards[0].visible and hand_ui._cards[0].instances.size() == 3, "paging back restores the complete three-copy stack as one slot")
	hand.clear()
	hand_ui.configure(hand, true)
	check(hand_ui._cards.is_empty() and not hand_ui._status_label.visible, "clearing a match removes every stack and its count")


func _combat_card(index: int, side: String) -> Dictionary:
	var definitions: Array = CardDatabase.get_all_cards()
	var card: Dictionary = definitions[index % definitions.size()].duplicate(true)
	card["instance_id"] = "event-visual-%s-%d" % [side, index]
	card["attack"] = 6
	card["defense"] = 20
	card["animated"] = false
	card["effects"] = []
	card["active_effects"] = []
	return card


func _check_original_camera(table: GameTable, resolution: String) -> void:
	var expected := table.match_camera_marker.global_transform
	if table.match_camera_use_export_rotation:
		expected.basis = Basis.from_euler(table.match_camera_rotation * (PI / 180.0))
	check(table.table_camera.global_transform.is_equal_approx(expected), resolution + " preserves the original match-marker camera transform")


func _check_target_access(table: GameTable, hand_ui: Variant) -> void:
	var targets_accessible := true
	for target in table._player_slots + table._enemy_slots:
		var point := table.table_camera.unproject_position(target.global_position)
		for hand_card in hand_ui._cards:
			if hand_card.visible and Rect2(hand_card.position, hand_card.size * hand_card.scale).has_point(point):
				targets_accessible = false
	check(targets_accessible, "selecting an event leaves all ten board target centers clickable")


func _capture_block_detail(table: GameTable, filename: String) -> void:
	var badge := table._enemy_slots[2]._event_block_badge
	var model := badge.get_node("PinMotion/Orientation/Model") as Node3D
	var upper := table.table_camera.unproject_position(model.to_global(badge.SOURCE_TIP + Vector3(0, 0, 5.3)))
	var lower := table.table_camera.unproject_position(model.to_global(badge.SOURCE_TIP))
	check(upper.distance_to(lower) >= 22.0, "the embedded knife has a readable silhouette from the match camera")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var crop := Rect2i(Vector2i(upper.min(lower)) - Vector2i(24, 24), Vector2i((upper - lower).abs()) + Vector2i(48, 48))
		crop = crop.intersection(Rect2i(Vector2i.ZERO, root.size))
		root.get_texture().get_image().get_region(crop).save_png("res://" + filename + ".png")


func _push_pointer(position: Vector2) -> void:
	_pointer_position = position
	_inject_pointer()


func _process(delta: float) -> void:
	if is_instance_valid(_hand_ui) and _hand_ui.is_visible_in_tree():
		_hand_ui._update_hover(_pointer_position)
		_hand_ui._animate_hand(delta)


func _inject_pointer() -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = _pointer_position
	motion.global_position = _pointer_position
	Input.parse_input_event(motion)


func _screenshot(filename: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://" + filename + ".png")
