extends Node3D

const PROP_SECRETS := [
	{"id": "usb_stick", "model": "res://assets/environments/props/usb/scene.gltf", "fake_name": "usb"},
	{"id": "cigarettes", "model": "res://assets/environments/props/cigarettes/cigs.glb", "fake_name": "cigs"},
	{"id": "moewenmilch", "model": "res://assets/environments/props/beer/energy.glb", "fake_name": "energy"},
]
const PROP_SCRIPT := preload("res://scripts/table/LocalTableProp.gd")

var checks := 0
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	print(("PASS: " if condition else "FAIL: ") + description)
	if not condition:
		failures += 1

func _prop(path: String) -> LocalTableProp:
	var model := (load(path) as PackedScene).instantiate()
	model.set_script(PROP_SCRIPT)
	model.name = "RenamedNativeProp"
	add_child(model)
	return model as LocalTableProp

func _reveals(card_id: String) -> Array[Card3D]:
	var result: Array[Card3D] = []
	for node in get_children():
		if node is Card3D and str(node.card_data.get("id")) == card_id:
			result.append(node)
	return result

func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Use the isolated match-feature runner to protect player saves.")
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	CollectionManager.clear_profile_state()
	CollectionManager.save_collection()
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 0.5, 4)
	camera.make_current()
	var wrong_camera := Camera3D.new()
	add_child(wrong_camera)
	for config: Dictionary in PROP_SECRETS:
		await _check_prop(config, camera, wrong_camera)
	check(CollectionManager.get_amount(CollectionManager.SLOT_ROOM_KEY_ID) == 0, "none of the three native collectible props awards the knife's key")
	for config: Dictionary in PROP_SECRETS:
		check(CollectionManager.get_amount(str(config.id)) == 1, "the three distinct discoveries coexist: " + str(config.id))
	camera.free()
	wrong_camera.free()
	print("USB_SECRET_DISCOVERY_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _check_prop(config: Dictionary, camera: Camera3D, wrong_camera: Camera3D) -> void:
	var card_id := str(config.id)
	var model_path := str(config.model)
	var label := card_id + ": "
	var prop := _prop(model_path)
	check(prop.scene_file_path == model_path and prop._pick_area.get_child_count() > 0, label + "the imported prop retains its native model identity and mesh picking after a rename")
	check(CollectionManager.get_amount(card_id) == 0 and _reveals(card_id).is_empty(), label + "spawning the prop does not grant or reveal its Secret")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	prop._on_input_event(camera, click, Vector3.ZERO, Vector3.ZERO, 0)
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = false
	prop._on_input_event(camera, click, Vector3.ZERO, Vector3.ZERO, 0)
	prop._on_input_event(camera, InputEventMouseMotion.new(), Vector3.ZERO, Vector3.ZERO, 0)
	click.pressed = true
	prop.hide()
	prop._on_input_event(camera, click, Vector3.ZERO, Vector3.ZERO, 0)
	prop.show()
	get_tree().paused = true
	prop._on_input_event(camera, click, Vector3.ZERO, Vector3.ZERO, 0)
	get_tree().paused = false
	prop._on_input_event(wrong_camera, click, Vector3.ZERO, Vector3.ZERO, 0)
	prop._pick_area.input_ray_pickable = false
	prop._on_input_event(camera, click, Vector3.ZERO, Vector3.ZERO, 0)
	prop._pick_area.input_ray_pickable = true
	check(not prop._launched and CollectionManager.get_amount(card_id) == 0 and _reveals(card_id).is_empty(), label + "hover, right click, release, hidden, paused, wrong-camera and disabled-picking inputs cannot award a Secret")
	var impostor := LocalTableProp.new()
	impostor.name = str(config.fake_name)
	add_child(impostor)
	impostor._launch(camera)
	check(CollectionManager.get_amount(card_id) == 0, label + "a differently sourced prop with the right name cannot grant the model-specific Secret")
	impostor.free()
	var changes: Array = []
	var listener := func(ids: Array[String]): changes.append(ids.duplicate())
	CollectionManager.collection_changed.connect(listener)
	prop._on_input_event(camera, click, Vector3.ZERO, Vector3.ZERO, 0)
	prop._on_input_event(camera, click, Vector3.ZERO, Vector3.ZERO, 0)
	prop._launch(camera)
	check(CollectionManager.get_prop_secret_throw_count(card_id) == 1 and CollectionManager.get_amount(card_id) == 0 and changes.is_empty() and _reveals(card_id).is_empty(), label + "one physical throw counts once and does not grant the Secret early")
	prop.free()
	var random := RandomNumberGenerator.new()
	for count in range(1, int(CollectionManager.PROP_SECRET_THROW_REQUIREMENTS[card_id]) - 1):
		CollectionManager.discover_prop_secret(card_id, random)
	CollectionManager.load_collection()
	prop = _prop(model_path)
	check(CollectionManager.get_amount(card_id) == 0 and CollectionManager.get_prop_secret_throw_count(card_id) == int(CollectionManager.PROP_SECRET_THROW_REQUIREMENTS[card_id]) - 1, label + "the next physical throw is the exact saved unlock boundary")
	seed(700313)
	var next_shared_random := randi()
	seed(700313)
	prop._on_input_event(camera, click, Vector3.ZERO, Vector3.ZERO, 0)
	check(randi() == next_shared_random, label + "accepted input and throw preserve shared combat randomness")
	check(prop._launched and not prop._pick_area.input_ray_pickable and CollectionManager.get_amount(card_id) == 1 and changes == [[card_id]], label + "the threshold click throws the prop and grants exactly one Secret")
	check(_reveals(card_id).is_empty(), label + "discovery defers creating scene nodes until after the physics input callback")
	await get_tree().process_frame
	await get_tree().process_frame
	var cards := _reveals(card_id)
	check(cards.size() == 1, label + "the successful throw presents exactly one physical Secret card")
	if cards.size() == 1:
		var card := cards[0]
		check(str(card.card_data.get("instance_id")) == str(CollectionManager.get_instances_for_card(card_id)[0].get("instance_id")) and card.get("_diorama_art") != null, label + "the reveal displays the exact saved instance with its live 3D room")
		var no_picking := true
		for area: Node in card.find_children("*", "Area3D", true, false):
			no_picking = no_picking and not area.input_ray_pickable and area.collision_layer == 0
		check(no_picking, label + "the reveal cannot intercept gameplay or prop input")
	prop._on_input_event(camera, click, Vector3.ZERO, Vector3.ZERO, 0)
	prop._launch(camera)
	prop.free()
	CollectionManager.load_collection()
	prop = _prop(model_path)
	prop._on_input_event(camera, click, Vector3.ZERO, Vector3.ZERO, 0)
	await get_tree().process_frame
	check(CollectionManager.get_amount(card_id) == 1 and changes.size() == 1 and _reveals(card_id).size() == 1, label + "repeated callbacks and another scene's prop after reload neither duplicate nor replay discovery")
	CollectionManager.collection_changed.disconnect(listener)
	await get_tree().create_timer(4.0).timeout
	check(_reveals(card_id).is_empty(), label + "the temporary discovery presentation removes itself after the rise and perspective reveal")
	prop.free()
