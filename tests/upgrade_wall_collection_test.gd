extends Node3D

const BASE_UPGRADE_IDS := ["clicker", "clicker_upgrade", "starting_hand_1", "starting_hand_2", "starting_hand_3", "starting_hand_4", "starting_hand_5"]

var checks := 0
var failures := 0
var wall: UpgradeWallCollection
var camera: Camera3D


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + message)
	if not condition:
		failures += 1


func settle(seconds: float = 0.08) -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().create_timer(seconds).timeout


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		push_error("Use the isolated test runner.")
		get_tree().quit(1)
		return
	SettingsManager.set_fullscreen(false)
	CollectionManager.collection = {"cards": {}, "instances": []}
	var room := (load("res://scenes/rooms/EmptyHospitalRoom.tscn") as PackedScene).instantiate() as Node3D
	add_child(room)
	_measure_room(room.get_node("Shell"))
	camera = Camera3D.new()
	camera.fov = 60
	add_child(camera)
	camera.make_current()
	wall = (load("res://scenes/props/UpgradeWallCollection.tscn") as PackedScene).instantiate() as UpgradeWallCollection
	wall.camera = camera
	room.add_child(wall)
	camera.look_at(wall.global_position)
	await settle()
	check(wall._cards.is_empty() and wall._empty_label.visible, "empty profile has a wall empty state")
	CollectionManager.add_card_instance(CardData.create_instance("slot_room_key"))
	CollectionManager.add_card_instance(CardData.create_instance("wanderer"))
	CollectionManager.add_card_instance(CardData.create_instance("clicker"))
	CollectionManager.add_card_instance(CardData.create_instance("clicker_upgrade", 1, [], true))
	CollectionManager.add_card_instance(CardData.create_instance("clicker_upgrade"))
	for index in range(1, 6):
		CollectionManager.add_card_instance(CardData.create_instance("starting_hand_%d" % index))
	await settle()
	check(wall._cards.size() == 8 and not wall._empty_label.visible, "seven upgrade types and the owned access key appear after acquiring cards")
	check(wall._cards.has("slot_room_key") and not wall._cards.has("wanderer"), "access key remains in the special collection while combat cards are excluded")
	check(wall._rows[int(wall._card_rows["slot_room_key"])]["group"] == "upgrade_group_access", "slot-room key is grouped with the other access keys")
	check(wall._amount_labels["clicker_upgrade"].text == "× 2", "duplicate upgrade copies share a card with correct amount")
	check(CardData.is_holo(wall._cards["clicker_upgrade"].card_data), "owned Holo copy is used for the wall display")
	check(not wall._cards["clicker"].area.input_ray_pickable and wall._cards["clicker"].area.collision_layer == 0, "wall cards do not intercept other scenes' physics input")
	var target := camera.unproject_position(wall._cards["clicker_upgrade"].global_position)
	check(wall._card_at(target) == "", "disabled wall ignores card targeting")
	wall.open_detail("clicker_upgrade")
	check(not wall.is_detail_open(), "disabled wall rejects direct detail opening")
	wall.set_interaction_enabled(true)
	check(wall._card_at(target) == "clicker_upgrade", "screen ray targets the actual card face")
	var original: Card3D = wall._cards["clicker_upgrade"]
	var origin := original.global_transform
	wall.open_detail("clicker_upgrade")
	check(wall.is_detail_open() and CardData.is_holo(wall._detail_card.card_data), "detail preserves the actual owned Holo instance")
	check(wall._detail_card == original and original.global_transform.is_equal_approx(origin), "detail starts with the existing wall card at its exact wall transform")
	check(wall._detail_caption.text.contains("2") and wall._detail_controls.visible, "detail displays total owned count and background input surface")
	check(wall._detail_controls.find_children("*", "Button", true, false).is_empty(), "detail contains no visible Back or Escape button")
	wall.set_interaction_enabled(false)
	check(wall.is_detail_open(), "gating new clicks keeps an existing detail visible")
	await settle(0.6)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://test-user/upgrade-wall-detail.png")
	wall.close_detail()
	check(wall.is_detail_open() and wall._detail_controls.visible, "return flight retains overlay input until the card reaches the wall")
	await settle(0.6)
	check(not wall.is_detail_open() and not wall._detail_controls.visible, "completed return releases overlay input")
	check(wall._cards["clicker_upgrade"] == original and original.position.is_equal_approx(wall._base_positions["clicker_upgrade"]), "return keeps the original card in its original slot")
	wall.set_interaction_enabled(true)
	wall._set_scroll_row(int(wall._card_rows["starting_hand_5"]))
	wall.open_detail("starting_hand_5")
	check(wall.is_detail_open(), "scrolling reaches the last starting-hand upgrade before reset")
	await settle(0.12)
	CollectionManager.collection = {"cards": {}, "instances": []}
	CollectionManager.collection_changed.emit(Array([], TYPE_STRING, &"", null))
	await settle(0.6)
	check(wall._cards.is_empty() and wall._empty_label.visible and not wall.is_detail_open(), "reset during entry clears the wall and cancels the flying obsolete detail")
	for id: String in BASE_UPGRADE_IDS:
		CollectionManager.add_card_instance(CardData.create_instance(id))
	await settle()
	wall.open_detail("clicker")
	await settle(0.6)
	wall.close_detail()
	await settle(0.1)
	CollectionManager.collection = {"cards": {}, "instances": []}
	CollectionManager.collection_changed.emit(Array([], TYPE_STRING, &"", null))
	await settle(0.6)
	check(wall._cards.is_empty() and wall._empty_label.visible and not wall.is_detail_open(), "reset during return cancels its tween without resurrecting removed cards")
	for id: String in BASE_UPGRADE_IDS:
		CollectionManager.add_card_instance(CardData.create_instance(id))
	await settle()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://test-user/upgrade-wall.png")
	print("UPGRADE_WALL_COLLECTION_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(1 if failures else 0)


func _measure_room(shell: Node3D) -> void:
	var directions := [Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.FORWARD]
	var hits := [INF, INF, INF, INF]
	for mesh_node: Node in shell.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var faces := mesh_instance.mesh.get_faces()
		for index in range(0, faces.size(), 3):
			var first := mesh_instance.global_transform * faces[index]
			var second := mesh_instance.global_transform * faces[index + 1]
			var third := mesh_instance.global_transform * faces[index + 2]
			for direction_index in range(directions.size()):
				var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3.ZERO, directions[direction_index], first, second, third)
				if hit != null:
					hits[direction_index] = minf(hits[direction_index], (hit as Vector3).length())
	print("ROOM WALL DISTANCES +X,+Z,-X,-Z: ", hits)
