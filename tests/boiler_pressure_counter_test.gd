extends Node3D

const GAUGE := preload("res://scenes/props/BoilerGauge.tscn")
var checks := 0
var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
	print(("PASS " if value else "FAIL ") + description)


func _settled(counter: Node) -> void:
	var deadline := Time.get_ticks_msec() + 2000
	while counter.is_rolling() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(not counter.is_rolling(), "counter settles within two seconds")


func _run() -> void:
	var first := GAUGE.instantiate()
	var second := GAUGE.instantiate()
	add_child(first)
	add_child(second)
	var counter = first.get_node("PressureDigits")
	var other = second.get_node("PressureDigits")
	check(counter.text == "2.8" and counter.get_roll_positions().is_equal_approx(Vector2(2, 8)), "initial pressure is seated without a startup spin")
	check(not counter.is_processing(), "a seated counter consumes no per-frame updates")
	# Let the cold scene-load frame pass before measuring a short live animation.
	await get_tree().create_timer(0.08).timeout
	counter.set_pressure(2.9, true)
	counter.set_pressure(3.0)
	check(counter.text == "3.0" and counter.is_rolling(), "exact puzzle text updates while the mechanical roll begins")
	await get_tree().process_frame
	await get_tree().process_frame
	var carry: Vector2 = counter.get_roll_positions()
	check(carry.x > 2.0 and carry.x < 3.0 and carry.y > 9.0 and carry.y < 10.0, "2.9 to 3.0 visibly engages both drums during the carry")
	check(is_equal_approx(counter.units.get_instance_shader_parameter("roll_steps"), carry.x) and is_equal_approx(counter.tenths.get_instance_shader_parameter("roll_steps"), carry.y), "visible drum positions follow the animated intermediate values")
	check(other.get_roll_positions().is_equal_approx(Vector2(2, 8)), "shared materials keep the second instrument independent")
	var before_reverse: float = counter._roll_steps
	counter.set_pressure(2.8)
	check(is_equal_approx(counter._roll_steps, before_reverse), "reversing during carry preserves the current drum position")
	await get_tree().process_frame
	await get_tree().process_frame
	check(counter._roll_steps < before_reverse, "a direction reversal rolls backward immediately")
	await _settled(counter)
	check(counter.text == "2.8" and counter.get_roll_positions().is_equal_approx(Vector2(2, 8)), "reverse carry returns to the exact seated 2.8")
	counter.set_pressure(3.0, true)
	counter.set_pressure(2.9)
	await get_tree().process_frame
	await get_tree().process_frame
	carry = counter.get_roll_positions()
	check(carry.x > 2 and carry.x < 3 and carry.y > 9 and carry.y < 10, "3.0 to 2.9 uses the same mechanical carry in reverse")
	await _settled(counter)
	counter.set_pressure(0, true)
	counter.set_pressure(6)
	await get_tree().process_frame
	await get_tree().process_frame
	check(counter._roll_steps > 0 and counter._roll_steps < 60, "a large change travels through intermediate digits")
	await _settled(counter)
	check(counter.text == "6.0" and counter.get_roll_positions().is_equal_approx(Vector2(6, 0)), "upper stop seats at 6.0 without wrapping past six")
	counter.set_pressure(2.84, true)
	counter.set_pressure(2.8)
	get_tree().paused = true
	await _settled(counter)
	check(counter.text == "2.8" and counter.get_roll_positions().is_equal_approx(Vector2(2, 8)), "release rounding finishes seating even when pause has just opened")
	get_tree().paused = false
	counter.set_pressure(0)
	first.hide()
	check(not counter.is_rolling() and not counter.is_processing() and counter.get_roll_positions().is_equal_approx(Vector2(0, 0)), "hiding a room seats the counter and stops background work")
	first.show()
	counter.set_pressure(9, true)
	check(counter.text == "6.0", "out-of-range high values remain at six")
	counter.set_pressure(-1, true)
	check(counter.text == "0.0", "out-of-range low values remain at zero")
	first.queue_free()
	second.queue_free()
	await get_tree().process_frame
	print("BOILER_PRESSURE_COUNTER_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
