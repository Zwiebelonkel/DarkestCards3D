extends Node3D

const NUMBER := preload("res://scripts/ui/DamageNumber3D.gd")
var failures := 0
var checks := 0


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	if not str(CollectionManager.SAVE_PATH).begins_with("res://test-user/"):
		push_error("Run with the isolated match feature runner.")
		get_tree().quit(1)
		return
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("171219")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.9
	get_world_3d().environment = environment
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0.0, 2.6, 2.9)
	camera.look_at(Vector3(0, 0.12, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.1
	camera.make_current()
	var table := MeshInstance3D.new()
	var surface := BoxMesh.new()
	surface.size = Vector3(4.0, 0.08, 2.2)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("3e2726")
	surface.material = material
	table.mesh = surface
	table.position.y = -0.08
	add_child(table)
	var card := (load("res://scenes/table/Card3D.tscn") as PackedScene).instantiate() as Card3D
	add_child(card)
	card.rotation_degrees.x = -90.0
	card.position.x = -0.65
	card.setup(CardDatabase.get_card("corpse").duplicate(true))
	card.description_label.skip()
	var before := card.get_network_state().duplicate(true)
	var number := NUMBER.new()
	add_child(number)
	number.show_damage(7, card.global_position, camera)
	number.set_process(false)
	check(number.damage_amount == 7 and number.label.text == "-7", "complete numeric damage")
	check(number.top_level and number.get_parent() == self, "independent 3D lifetime")
	check(number.label.billboard == BaseMaterial3D.BILLBOARD_ENABLED and number.label.no_depth_test, "readable from fighter and spectator cameras")
	check(number.get_children().size() == 1 and number.get_child(0) is Label3D, "number stays in 3D without a CanvasLayer")
	var start := number.global_position
	var small_scale := number.global_basis.get_scale().x
	number._animate(NUMBER.POP_PEAK_TIME)
	check(number.global_basis.get_scale().x > 1.0 and small_scale < 1.0, "number immediately pops larger")
	var bright_color := number.label.modulate
	await _capture("damage-number-flash")
	number._animate(NUMBER.BLINK_INTERVAL + 0.02)
	check(number.label.modulate != bright_color and number.label.modulate.a >= 0.7, "blink changes color and brightness without hiding the value")
	await _capture("damage-number-blink")
	var healing := NUMBER.new()
	add_child(healing)
	seed(917531)
	var expected_random := randi()
	seed(917531)
	healing.show_healing(3, Vector3(0.8, 0.0, 0), camera, 1)
	healing.set_process(false)
	check(randi() == expected_random, "healing presentation leaves global gameplay RNG untouched")
	check(healing.is_healing and healing.amount == 3 and healing.damage_amount == 0 and healing.label.text == "+3", "actual positive healing is rendered as +3 independently of damage")
	var healing_start := healing.global_position
	healing._animate(NUMBER.POP_PEAK_TIME)
	check(healing.label.modulate.is_equal_approx(Color.WHITE) and healing.global_basis.get_scale().x > 1.0, "healing initially pops in white with the existing number animation")
	await _capture("healing-number-white")
	healing._animate(NUMBER.BLINK_INTERVAL + 0.02)
	var green := healing.label.modulate
	check(is_equal_approx(green.r, NUMBER.HEALING_COLOR.r) and is_equal_approx(green.g, NUMBER.HEALING_COLOR.g) and is_equal_approx(green.b, NUMBER.HEALING_COLOR.b) and green.a >= 0.7, "healing blinks vivid green while its positive value remains legible")
	await _capture("healing-number-green")
	healing._animate(0.3)
	check(camera.global_basis.y.dot(healing.global_position - healing_start) > 0.0 and is_equal_approx(healing.global_basis.get_scale().x, 1.0), "healing rises and settles with the existing damage-number timing")
	number._animate(0.3)
	check(is_equal_approx(number.global_basis.get_scale().x, 1.0), "pop settles back to readable size")
	check(camera.global_basis.y.dot(number.global_position - start) > 0.0, "number rises upward on screen")
	check(card.get_network_state() == before, "visual does not mutate card state")
	var companion := NUMBER.new()
	add_child(companion)
	companion.show_damage(12, card.global_position, camera, 1)
	companion.set_process(false)
	companion._animate(0.3)
	check(absf(camera.global_basis.x.dot(number.global_position - companion.global_position)) > 0.3, "simultaneous impacts use distinct lanes")
	var blocked := NUMBER.new()
	add_child(blocked)
	blocked.show_damage(0, Vector3(0.8, 0.0, 0), camera, 0)
	blocked.set_process(false)
	blocked._animate(0.3)
	check(blocked.label.text == "0", "blocked hit is visibly zero")
	check(absf(camera.global_basis.x.dot(healing.global_position - blocked.global_position)) > 0.3, "simultaneous healing and blocked damage use distinct readable lanes")
	await _capture("damage-numbers-simultaneous")
	var impact_position := number.global_position
	card.position += Vector3(0, 3, 0)
	card.queue_free()
	await get_tree().process_frame
	check(is_instance_valid(number) and number.global_position.is_equal_approx(impact_position), "card death cannot move or erase an active number")
	number._animate(0.9)
	check(number.label.modulate.a > 0.0 and number.label.modulate.a < 0.6, "number fades at end")
	healing._animate(0.9)
	check(healing.label.modulate.a > 0.0 and healing.label.modulate.a < 0.6, "healing fades at the same end of its lifetime")
	var huge := NUMBER.new()
	add_child(huge)
	huge.show_damage(1234567, Vector3.ZERO, camera)
	huge.set_process(false)
	check(huge.label.text == "-1234567" and huge.label.pixel_size < NUMBER.PIXEL_SIZE, "large upgraded damage fits without rounding or truncation")
	number._process(NUMBER.LIFETIME + 0.01)
	healing._process(NUMBER.LIFETIME + 0.01)
	await get_tree().process_frame
	check(not is_instance_valid(number), "finished visual cleans itself up")
	check(not is_instance_valid(healing), "finished healing visual cleans itself up independently")
	for popup in [companion, blocked, huge]:
		popup.queue_free()
	await get_tree().process_frame
	print("DAMAGE_NUMBER_VISUAL_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png("res://" + filename + ".png") == OK, "rendered " + filename)
