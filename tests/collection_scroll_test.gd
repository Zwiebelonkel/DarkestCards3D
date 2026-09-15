extends Node3D

var failures := 0
var checks := 0
var screen: CollectionScreen


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func _settle(duration: float = 0.08) -> void:
	await get_tree().create_timer(duration).timeout
	await get_tree().process_frame
	await get_tree().process_frame


func _run() -> void:
	CollectionManager.collection = {"cards": {}, "instances": []}
	DeckManager.battle_deck.clear()
	# Use the database's long common row and the widest rarity caption, with
	# the real scene's spacing, camera and labels rather than a synthetic layout.
	for rarity: String in ["common", "legendary"]:
		for data: Dictionary in CardDatabase.get_cards_by_rarity(rarity):
			CollectionManager.create_card_instance(str(data["id"]))
	screen = (load("res://scenes/ui/CollectionScreen.tscn") as PackedScene).instantiate() as CollectionScreen
	screen.camera = screen.get_node("Camera3D") as Camera3D
	screen.spawn_duration = 0.01
	screen.spawn_stagger = 0.0
	screen.hover_duration = 0.03
	screen.detail_duration = 0.04
	screen.add_button_slide_duration = 0.03
	screen.row_scroll_duration = 0.04
	add_child(screen)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.035, 0.028, 0.025)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.65
	world.environment = environment
	add_child(world)
	await _settle(0.25)
	for card: Card3D in screen._base_positions.keys():
		# Signals are driven explicitly; the physical desktop pointer must not
		# alter hover during deterministic position checks or screenshots.
		card.area.collision_layer = 0
	await get_tree().physics_frame
	screen._reset_collection_hover()
	var initial_positions := screen._base_positions.duplicate()
	var initial_scales := screen._base_scales.duplicate()
	var common: Array = screen._row_cards["common"]
	check(common.size() >= 10, "real common cards provide a long scrollable row")
	var row_gap := screen.cards_root.to_global(Vector3(screen.row_start_x + screen.card_spacing_x * 0.5, 0.0, 0.0))
	check(screen._get_scroll_rarity_at(screen.camera.unproject_position(row_gap)) == "common", "wheel targeting recognizes the gap between cards without a stale hover signal")
	for card: Card3D in common:
		card.area.input_ray_pickable = false
	check(screen._get_scroll_rarity_at(screen.camera.unproject_position(row_gap)).is_empty(), "inactive collection rows do not intercept wheel input from another screen")
	for card: Card3D in common:
		card.area.input_ray_pickable = true
	check(screen._get_scroll_rarity_at(Vector2(-1000, -1000)).is_empty(), "wheel input outside the card rows targets no rarity")
	await _capture("collection-row-initial.png")
	_scroll_to_end("common", -1)
	await _settle()
	check(float(screen._row_scroll_offsets["common"]) < -screen.card_spacing_x * 5.0, "common row scrolls across multiple card widths")
	var stacked := _escaped_cards("common")
	check(stacked.size() >= 5, "several escaped cards form the left stack")
	_check_stack("common", stacked)
	var settled_positions := screen._base_positions.duplicate()
	_scroll_to_end("common", -1)
	await _settle()
	check(_same_positions(settled_positions), "scrolling repeatedly beyond the end leaves the stack bounded")
	check(_same_row_positions("legendary", initial_positions), "scrolling one rarity leaves the other row in place")
	await _capture("collection-row-stack.png")
	await _capture_stack_closeup()

	var top_card: Card3D = stacked.back()
	check(screen._get_scroll_rarity_at(screen.camera.unproject_position(top_card.global_position)) == "common", "wheel targeting remains on the compressed stack")
	top_card.area.mouse_entered.emit()
	await _settle()
	check(top_card.position.is_equal_approx(screen._base_positions[top_card] + screen.hover_lift), "a stacked card lifts from its own stack layer on hover")
	top_card.area.mouse_exited.emit()
	await _settle()
	check(top_card.position.is_equal_approx(screen._base_positions[top_card]), "leaving hover returns the card to its stack layer")
	await screen._open_detail_card(top_card)
	check(screen._get_scroll_rarity_at(screen.camera.unproject_position(row_gap)).is_empty(), "detail view prevents background rarity-row scrolling")
	await screen._close_detail_card()
	await _settle()
	check(top_card.position.is_equal_approx(screen._base_positions[top_card]), "closing a stacked card detail restores its stack position")
	check(top_card.scale.is_equal_approx(initial_scales[top_card]), "detail return preserves the stacked card's full scale")
	top_card.area.mouse_entered.emit()
	await _settle()
	check(top_card.position.is_equal_approx(screen._base_positions[top_card] + screen.hover_lift), "stack hover remains usable after detail closes")
	top_card.area.mouse_exited.emit()
	await _settle()

	# Overlap scroll and hover animations, then reverse before any scroll
	# tween completes. Old tweens must not pull cards back into stale layers.
	top_card.area.mouse_entered.emit()
	screen._scroll_row("common", 1)
	screen._scroll_row("common", 1)
	screen._scroll_row("common", -1)
	top_card.area.mouse_exited.emit()
	_scroll_to_end("common", 1)
	await _settle(0.2)
	check(is_zero_approx(float(screen._row_scroll_offsets["common"])), "reverse scrolling stops at the original row start")
	check(_same_row_positions("common", initial_positions), "rapid reverse scroll restores original card ordering and spacing")
	check(_all_scales_match(initial_scales), "scrolling and stacking never hide cards with zero scale")
	await _capture("collection-row-restored.png")

	_scroll_to_end("legendary", -1)
	await _settle()
	_check_stack("legendary", _escaped_cards("legendary"))
	_scroll_to_end("legendary", 1)
	await _settle()
	check(_same_positions(initial_positions), "all rarity rows recover their exact original positions")
	# Players can wheel before the staggered entrance of a long collection
	# finishes. Cancelling entrance must not strand a tiny, unpickable card.
	screen.spawn_duration = 0.1
	screen.spawn_stagger = 0.03
	screen.refresh_collection()
	for card: Card3D in screen._base_positions.keys():
		card.area.input_ray_pickable = false
		card.area.collision_layer = 0
	_scroll_to_end("common", -1)
	# Untouched rows still complete their normal stagger, which grows with
	# catalog size. Only the scrolled row has its entrance interrupted.
	await _settle(screen.spawn_duration + screen.spawn_stagger * screen._base_positions.size() + 0.1)
	check(_same_positions(screen._base_positions), "scroll during entrance prevents old spawn tweens from restoring stale positions")
	check(_all_scales_match(screen._base_scales), "scroll during entrance finishes every card at full scale")
	var all_connected := true
	for card: Card3D in screen._base_positions.keys():
		all_connected = all_connected and card.area.input_event.is_connected(screen._on_card_input.bind(card))
	check(all_connected, "cards whose entrance was interrupted still connect their collection input")
	screen.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("COLLECTION_SCROLL_TESTS: " + ("PASS" if failures == 0 else "FAIL") + " (%d checks)" % checks)
	get_tree().quit(0 if failures == 0 else 1)


func _scroll_to_end(rarity: String, direction: int) -> void:
	for step in range(100):
		screen._scroll_row(rarity, direction)


func _escaped_cards(rarity: String) -> Array[Card3D]:
	var result: Array[Card3D] = []
	var cards: Array = screen._row_cards[rarity]
	var offset := float(screen._row_scroll_offsets[rarity])
	for index in range(cards.size()):
		if float(index) * screen.card_spacing_x + offset < -0.001:
			result.append(cards[index])
	return result


func _check_stack(rarity: String, cards: Array[Card3D]) -> void:
	var label := screen.cards_root.get_node("RarityLabel_" + rarity) as Label3D
	var label_bounds := _x_bounds(label, label.get_aabb())
	var min_x := INF
	var max_x := -INF
	var label_clear := true
	var distinct_layers := true
	var positions: Array[Vector3] = []
	for card: Card3D in cards:
		var body := card.get_node("card/Cube") as MeshInstance3D
		var bounds := _x_bounds(body, body.get_aabb())
		label_clear = label_clear and bounds.x > label_bounds.y + 0.005
		min_x = minf(min_x, card.position.x)
		max_x = maxf(max_x, card.position.x)
		for previous: Vector3 in positions:
			distinct_layers = distinct_layers and card.position.distance_to(previous) > 0.001
		positions.append(card.position)
	check(label_clear, rarity + " stack stays beside the visible rarity text")
	check(max_x - min_x < screen.card_spacing_x * 0.5, rarity + " escaped cards share a compact overlapping stack")
	check(distinct_layers, rarity + " stack separates cards into distinct layers without coincident surfaces")


func _x_bounds(node: Node3D, box: AABB) -> Vector2:
	var bounds := Vector2(INF, -INF)
	for endpoint in range(8):
		var point := screen.cards_root.to_local(node.to_global(box.get_endpoint(endpoint)))
		bounds.x = minf(bounds.x, point.x)
		bounds.y = maxf(bounds.y, point.x)
	return bounds


func _same_positions(expected: Dictionary) -> bool:
	for card: Card3D in expected.keys():
		if not card.position.is_equal_approx(expected[card]):
			print("Unexpected position: ", card.card_data.get("id"), " ", card.position, " expected ", expected[card])
			return false
	return true


func _same_row_positions(rarity: String, expected: Dictionary) -> bool:
	for card: Card3D in screen._row_cards[rarity]:
		if not card.position.is_equal_approx(expected[card]):
			return false
	return true


func _all_scales_match(expected: Dictionary) -> bool:
	for card: Card3D in expected.keys():
		if not card.scale.is_equal_approx(expected[card]) or card.scale.x < 0.1:
			return false
	return true


func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await _settle(0.1)
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png("res://" + filename)


func _capture_stack_closeup() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# An additional view improves readability while leaving the actual card
	# and label geometry untouched. Main screenshots keep the scene camera.
	var original_transform := screen.camera.global_transform
	var original_projection := screen.camera.projection
	var original_size := screen.camera.size
	screen.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	screen.camera.size = 4.0
	screen.camera.global_position = Vector3(-1.2, 2.8, 4.2)
	screen.camera.look_at(Vector3(-1.2, 0.0, 0.0))
	await _capture("collection-row-stack-closeup.png")
	screen.camera.global_transform = original_transform
	screen.camera.projection = original_projection
	screen.camera.size = original_size
