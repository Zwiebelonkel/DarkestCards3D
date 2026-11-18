extends Node

var failures := 0
var checks := 0


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not GameCurrency.save_path.begins_with("res://test-user/"):
		push_error("Use the isolated test runner to protect real player saves.")
		get_tree().quit(1)
		return
	var voice := SatanVoiceChat.new()
	var monitor := MicrophoneTestController.new()
	var payload := PackedByteArray([12, 34, 56])
	for percent: int in [0, 100, 200, 205, 255, 300, 400, 500, 1000, 1500, 2000]:
		var packed := voice._pack_voice_payload(payload, percent)
		var decoded := voice._unpack_voice_payload(packed)
		check(bool(decoded.get("valid", false)), "Gain packet accepted: %d" % percent)
		check(is_equal_approx(float(decoded.get("microphone_gain", -1.0)), percent / 100.0), "Gain survives network round trip: %d" % percent)
		check(decoded.get("payload") == payload, "Steam bytes preserved: %d" % percent)
		SettingsManager.set_microphone_gain(percent / 100.0)
		var source := PackedVector2Array([Vector2(0.01, -0.01), Vector2(0.8, -0.8)])
		var remote := voice._apply_pcm_gain(source.duplicate(), float(decoded.get("microphone_gain", 0.0)))
		var local := monitor._apply_microphone_gain(source.duplicate())
		check(remote == local, "Microphone test matches transmitted gain: %d" % percent)
		check(is_equal_approx(remote[0].x, 0.01 * percent / 100.0), "Quiet samples amplified correctly: %d" % percent)
		check(absf(remote[1].x) <= 1.0 and absf(remote[1].y) <= 1.0, "Samples stay in valid range")
	var malformed := voice._pack_voice_payload(payload, 2000)
	malformed.encode_u16(5, 2001)
	check(not bool(voice._unpack_voice_payload(malformed).get("valid", false)), "Excessive gain rejected")
	for length in range(4, 8):
		check(not bool(voice._unpack_voice_payload(malformed.slice(0, length)).get("valid", false)), "Truncated envelope rejected")
	check(voice._unpack_voice_payload(payload).get("payload") == payload, "Raw legacy Steam payload accepted")
	SettingsManager.set_microphone_gain(20.0)
	SettingsManager.microphone_gain = 1.0
	SettingsManager.load_settings()
	check(is_equal_approx(SettingsManager.microphone_gain, 20.0), "2000 percent survives settings reload")
	var menu := preload("res://scenes/ui/SettingsMenu.tscn").instantiate() as SettingsMenu
	add_child(menu)
	menu.open()
	check(is_equal_approx(menu.microphone_gain_slider.max_value, 20.0), "Slider supports 2000 percent")
	check(menu.microphone_gain_value.text == "2000%", "Saved gain shown correctly")
	menu.microphone_gain_slider.value = 3.5
	check(is_equal_approx(SettingsManager.microphone_gain, 3.5), "Slider changes actual microphone gain")
	check(menu.microphone_gain_value.text == "350%", "Slider updates percentage")
	voice._ensure_voice_bus_and_pitch_effect()
	var voice_bus := AudioServer.get_bus_index(SatanVoiceChat.VOICE_BUS_NAME)
	check(is_equal_approx(menu.satan_voice_volume_slider.max_value, 20.0), "Received voice slider supports 2000 percent")
	for volume: float in [0.0, 0.3, 1.0, 5.0, 20.0]:
		menu.satan_voice_volume_slider.value = volume
		check(is_equal_approx(SettingsManager.satan_voice_volume, volume), "Received volume slider updates setting")
		check(menu.satan_voice_volume_value.text == "%d%%" % roundi(volume * 100.0), "Received volume percentage displayed")
		voice._apply_voice_volume()
		check(AudioServer.is_bus_mute(voice_bus) == (volume == 0.0), "Received voice mutes only at zero")
		if volume > 0.0:
			check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(voice_bus)), volume), "Received voice bus applies full amplification")
	SettingsManager.satan_voice_volume = 0.3
	SettingsManager.load_settings()
	check(is_equal_approx(SettingsManager.satan_voice_volume, 20.0), "Received voice amplification survives reload")
	SettingsManager.apply_settings()
	check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(voice_bus)), 20.0), "Applying settings preserves received amplification")
	SettingsManager.set_satan_voice_volume(50.0)
	check(is_equal_approx(SettingsManager.satan_voice_volume, 20.0), "Received volume is bounded at 2000 percent")
	check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(voice_bus)), 20.0), "Settings setter applies full received amplification")
	menu.queue_free()
	voice.free()
	monitor.free()
	print("MICROPHONE_GAIN_TESTS: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
