extends Node3D

var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	print(("PASS " if condition else "FAIL ") + message)
	if not condition:
		failures += 1


func _sample(capture: AudioEffectCapture) -> Vector2:
	capture.clear_buffer()
	await get_tree().create_timer(0.35).timeout
	var samples := capture.get_buffer(capture.get_frames_available())
	var peak := 0.0
	var energy := 0.0
	for sample: Vector2 in samples:
		peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
		energy += (sample.x * sample.x + sample.y * sample.y) * 0.5
	return Vector2(linear_to_db(peak), linear_to_db(sqrt(energy / maxf(samples.size(), 1))))


func _run() -> void:
	if not CollectionManager.SAVE_PATH.begins_with("res://test-user/"):
		get_tree().quit(1)
		return
	GameCurrency.set_process(false)
	var camera := Camera3D.new()
	add_child(camera)
	# Match the normal roughly four-metre view of the real machine's emitter.
	camera.position = Vector3(0, 1.6, 4)
	camera.current = true
	var machine := (load("res://scenes/props/SlotMachine.tscn") as PackedScene).instantiate() as SoulSlotMachine
	add_child(machine)
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 2.0
	var bus := AudioServer.get_bus_index("SFX")
	var original_volume := AudioServer.get_bus_volume_db(bus)
	AudioServer.set_bus_volume_db(bus, 0.0)
	AudioServer.add_bus_effect(bus, capture)
	await get_tree().create_timer(0.1).timeout
	machine._start_rolling_audio()
	var audible: Vector2 = await _sample(capture)
	print("ROLLING_SFX_LEVELS: peak %.1f dB, RMS %.1f dB at %.1f metres" % [audible.x, audible.y, camera.global_position.distance_to(machine._rolling_audio.global_position)])
	check(machine._rolling_audio.bus == &"SFX" and audible.x > -25.0 and audible.y > -35.0, "the actual rolling recording reaches SFX at an audible level at normal distance")
	machine.reel_stop_delay = 0.5
	machine._fade_rolling_audio()
	await get_tree().create_timer(0.8).timeout
	check(machine._rolling_audio.playing and machine._rolling_audio.pitch_scale < 0.6 and machine._rolling_audio.volume_db < -35.0, "the audible loop still slows down and fades toward the final symbol")
	machine._stop_rolling_audio()
	await get_tree().create_timer(0.1).timeout
	var silent: Vector2 = await _sample(capture)
	check(silent.x < -70.0, "stopping the spin leaves no rolling sound on SFX")
	AudioServer.remove_bus_effect(bus, AudioServer.get_bus_effect_count(bus) - 1)
	AudioServer.set_bus_volume_db(bus, original_volume)
	machine.queue_free()
	await get_tree().process_frame
	print("ROLLING_AUDIO_AUDIBILITY_TESTS: " + ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)
