extends Node3D

const SCREAM_SCRIPT := preload("res://scripts/main/AmbientScreams.gd")
var failures := 0


func check(condition: bool, message: String) -> void:
	print(("PASS " if condition else "FAIL ") + message)
	if not condition:
		failures += 1


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var ambience := SCREAM_SCRIPT.new()
	add_child(ambience)
	check(not ambience._player.playing and ambience._timer.time_left >= 300.0 and ambience._timer.time_left <= 600.0, "first scream waits five to ten minutes")
	ambience._on_timeout()
	check(not ambience._player.playing and not ambience._timer.is_stopped(), "missing camera skips playback and reschedules")
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	var streams := {}
	var valid := true
	var min_pitch := 2.0
	var max_pitch := 0.0
	for index in range(100):
		camera.global_position = Vector3(index * 3.0, 1.6, -index * 2.0)
		ambience._on_timeout()
		var offset: Vector3 = ambience._player.global_position - camera.global_position
		var distance := Vector2(offset.x, offset.z).length()
		valid = valid and distance >= 4.999 and distance <= 12.001 and offset.y >= -1.001 and offset.y <= 2.001
		valid = valid and ambience._player.playing and ambience._timer.time_left >= 300.0 and ambience._timer.time_left <= 600.0
		streams[ambience._player.stream] = true
		min_pitch = minf(min_pitch, ambience._player.pitch_scale)
		max_pitch = maxf(max_pitch, ambience._player.pitch_scale)
	check(valid, "screams play around the current camera in every room and reschedule within five to ten minutes")
	check(streams.size() == 3 and min_pitch >= 0.8 and max_pitch <= 1.2 and max_pitch - min_pitch > 0.2, "all three recordings and varied pitches are used")
	check(ambience._player.bus == &"SFX", "screams respect the effects volume")
	var source_position: Vector3 = ambience._player.global_position
	camera.position += Vector3(20, 0, 20)
	check(ambience._player.global_position == source_position, "an active scream stays at its world position when the player moves")
	get_tree().paused = true
	var remaining: float = ambience._timer.time_left
	await get_tree().create_timer(0.05, true).timeout
	check(is_equal_approx(remaining, ambience._timer.time_left), "pause freezes the scream timer")
	get_tree().paused = false
	var player_ref: WeakRef = weakref(ambience._player)
	ambience.queue_free()
	await get_tree().process_frame
	check(player_ref.get_ref() == null, "leaving gameplay removes the timer and audio source")
	print("AMBIENT_SCREAMS_TESTS: " + ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)
