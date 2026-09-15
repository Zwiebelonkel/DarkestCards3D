extends Node
class_name MicrophoneTestController

enum TestState { IDLE, STARTING, LISTENING, MONITORING, STOPPING, ERROR }
enum InputVoiceActivity { SILENT, SPEAKING, LOUD }

const VOICE_BUS_NAME: StringName = &"SatanVoice"
const VOICE_SAMPLE_RATE := 24000
const INITIAL_DECOMPRESS_BUFFER_BYTES := 32768
const MAX_DECOMPRESS_BUFFER_BYTES := 96000
const MAX_COMPRESSED_DRAIN_BYTES := 64 * 1024
const MAX_COMPRESSED_RECOVERY_BYTES := 1024 * 1024
const STOP_DRAIN_BUFFER_BYTES := 8192
const TRANSITION_TIMEOUT_SECONDS := 1.0
const MONITOR_START_BUFFER_SECONDS := 0.04
const MONITOR_RECOVERY_BUFFER_SECONDS := 0.06
const MONITOR_MAX_QUEUE_SECONDS := 0.12
const MONITOR_GENERATOR_BUFFER_SECONDS := 0.12
const NO_INPUT_HINT_SECONDS := 5.0
const METER_FLOOR_DB := -60.0
const METER_ATTACK_DB_PER_SECOND := 150.0
const METER_RELEASE_DB_PER_SECOND := 32.0
const VOICE_VISUAL_WINDOW_FRAMES := 480
const VOICE_VISUAL_MIN_WINDOW_FRAMES := 120
const SPEECH_START_RMS_DB := -42.0
const SPEECH_START_PEAK_DB := -32.0
const SPEECH_KEEP_RMS_DB := -48.0
const SPEECH_KEEP_PEAK_DB := -38.0
const SPEECH_ATTACK_SECONDS := 0.04
const SPEECH_HOLD_SECONDS := 0.28
const LOUD_START_RMS_DB := -20.0
const LOUD_START_PEAK_DB := -8.0
const LOUD_KEEP_RMS_DB := -25.0
const LOUD_KEEP_PEAK_DB := -13.0
const LOUD_ATTACK_SECONDS := 0.055
const LOUD_HOLD_SECONDS := 0.17
const VOICE_ATTACK_MAX_GAP_SECONDS := 0.12
const VOICE_LEVEL_LOUD_SHARE := 0.75
const VOICE_LEVEL_ATTACK_TAU_SECONDS := 0.035
const VOICE_LEVEL_RELEASE_TAU_SECONDS := 0.18
const VOICE_LEVEL_ZERO_EPSILON := 0.001

const VOICE_RESULT_OK := 0
const VOICE_RESULT_NOT_INITIALIZED := 1
const VOICE_RESULT_NOT_RECORDING := 2
const VOICE_RESULT_NO_DATA := 3
const VOICE_RESULT_BUFFER_TOO_SMALL := 4

var test_state := TestState.IDLE
var input_level_db := METER_FLOOR_DB
var input_voice_activity := InputVoiceActivity.SILENT
var input_voice_level := 0.0
var _status_source := "Ready. Steam microphone starts only after you click Start Mic."
var _status_arguments: Array = []
var status_text: String:
	get:
		return Localization.format_text(_status_source, _status_arguments) if not _status_arguments.is_empty() else Localization.text(_status_source)
	set(value):
		_status_source = value
		_status_arguments.clear()

var _output_player: AudioStreamPlayer = null
var _output_playback: AudioStreamGeneratorPlayback = null
var _pitch_effect: AudioEffectPitchShift = null
var _capture_running := false
var _meter_target_db := METER_FLOOR_DB
var _transition_elapsed_seconds := 0.0
var _stop_target_state := TestState.IDLE
var _stop_target_status := ""
var _stop_target_arguments: Array = []
var _monitor_requested := false
var _monitor_pcm_queue := PackedVector2Array()
var _monitor_recovering := false
var _last_monitor_skip_count := 0
var _voice_data_age_seconds := 0.0
var _input_speech_attack_seconds := 0.0
var _input_loud_attack_seconds := 0.0
var _input_speech_hold_seconds := 0.0
var _input_loud_hold_seconds := 0.0
var _input_voice_attack_gap_seconds := 0.0
var _received_input_pcm_this_frame := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pitch_effect = _ensure_voice_bus_and_pitch_effect()
	_create_output_player()


func _process(delta: float) -> void:
	_received_input_pcm_this_frame = false
	if test_state in [TestState.LISTENING, TestState.MONITORING]:
		_input_speech_hold_seconds = maxf(
			_input_speech_hold_seconds - delta,
			0.0
		)
		_input_loud_hold_seconds = maxf(
			_input_loud_hold_seconds - delta,
			0.0
		)
	_update_meter(delta)
	match test_state:
		TestState.STARTING:
			_drain_before_start(delta)
		TestState.LISTENING, TestState.MONITORING:
			_voice_data_age_seconds += delta
			_poll_steam_microphone()
			_update_no_input_hint()
		TestState.STOPPING:
			_drain_after_stop(delta)
	_finalize_input_voice_visual(delta)


func start_listening() -> bool:
	if test_state in [TestState.STARTING, TestState.LISTENING, TestState.MONITORING]:
		return true
	if test_state == TestState.STOPPING:
		status_text = "Steam microphone is still stopping. Please wait a moment."
		return false
	if not Engine.has_singleton("Steam") or not NetworkManager.steam_ready:
		_set_error_immediately(
			"Steam is not ready. Start Steam and try the microphone test again."
		)
		return false

	_monitor_requested = false
	test_state = TestState.STARTING
	status_text = "Preparing the Steam microphone..."
	_transition_elapsed_seconds = 0.0
	_meter_target_db = METER_FLOOR_DB
	input_level_db = METER_FLOOR_DB
	_reset_input_voice_visual()
	SettingsManager.set_microphone_test_active(true)
	# This also stops a possible previous chat owner. Steam deliberately keeps a
	# short tail after stop; STARTING drains it before taking ownership.
	Steam.stopVoiceRecording()
	_drain_before_start(0.0)
	return test_state != TestState.ERROR


func start_monitoring() -> bool:
	if test_state == TestState.MONITORING:
		return true
	if not _is_monitor_output_audible():
		status_text = "Master or Voice Volume is muted. Raise it to hear the live test."
		return false

	_monitor_requested = true
	if test_state in [TestState.IDLE, TestState.ERROR]:
		if not start_listening():
			_monitor_requested = false
			return false
		_monitor_requested = true
	if test_state == TestState.STARTING:
		status_text = "Preparing the live Satan test..."
		return true
	if test_state != TestState.LISTENING:
		return false

	_begin_monitoring()
	return true


func stop_monitoring() -> void:
	_monitor_requested = false
	if test_state == TestState.STARTING:
		status_text = "Preparing the Steam microphone..."
		return
	if test_state != TestState.MONITORING:
		return
	_stop_output_player()
	_monitor_pcm_queue.clear()
	_monitor_recovering = false
	test_state = TestState.LISTENING
	status_text = "Listening through Steam. Live Satan test stopped."


func refresh_monitor_pitch() -> void:
	if test_state == TestState.MONITORING:
		_apply_local_test_pitch()


func stop_session() -> void:
	if test_state == TestState.IDLE:
		return
	if test_state == TestState.STOPPING:
		return
	if test_state == TestState.ERROR and not SettingsManager.microphone_test_active:
		test_state = TestState.IDLE
		status_text = "Ready. Steam microphone starts only after you click Start Mic."
		return
	_begin_stop(
		TestState.IDLE,
		"Ready. Steam microphone starts only after you click Start Mic."
	)


func shutdown() -> void:
	stop_session()


func is_session_active() -> bool:
	return test_state in [
		TestState.STARTING,
		TestState.LISTENING,
		TestState.MONITORING,
		TestState.STOPPING,
	]


func _drain_before_start(delta: float) -> void:
	_transition_elapsed_seconds += delta
	if not Engine.has_singleton("Steam") or not NetworkManager.steam_ready:
		_set_error_immediately("Steam became unavailable while preparing the microphone.")
		return
	var result := _drain_voice_tail_once()
	if result == VOICE_RESULT_NOT_RECORDING:
		_begin_capture()
		return
	if result == VOICE_RESULT_NOT_INITIALIZED:
		_set_error_immediately("Steam microphone is not initialized.")
		return
	if _transition_elapsed_seconds >= TRANSITION_TIMEOUT_SECONDS:
		_begin_capture()


func _begin_capture() -> void:
	if not Engine.has_singleton("Steam") or not NetworkManager.steam_ready:
		_set_error_immediately("Steam became unavailable before microphone start.")
		return
	Steam.startVoiceRecording()
	_capture_running = true
	_transition_elapsed_seconds = 0.0
	_voice_data_age_seconds = 0.0
	if _monitor_requested and _is_monitor_output_audible():
		_begin_monitoring()
	else:
		_monitor_requested = false
		test_state = TestState.LISTENING
		status_text = "Listening through Steam. Speak to check the input level."


func _begin_monitoring() -> void:
	_apply_local_test_pitch()
	_stop_output_player()
	_monitor_pcm_queue.clear()
	_monitor_recovering = false
	test_state = TestState.MONITORING
	status_text = "Live Satan test active. Use headphones to prevent feedback."


func _begin_stop(target_state: int, final_status: String, arguments: Array = []) -> void:
	_monitor_requested = false
	_stop_output_player()
	_monitor_pcm_queue.clear()
	_monitor_recovering = false
	_meter_target_db = METER_FLOOR_DB
	_reset_input_voice_visual()
	if Engine.has_singleton("Steam") and NetworkManager.steam_ready:
		Steam.stopVoiceRecording()
	_capture_running = false
	_transition_elapsed_seconds = 0.0
	_stop_target_state = target_state
	_stop_target_status = final_status
	_stop_target_arguments = arguments.duplicate()
	test_state = TestState.STOPPING
	status_text = "Stopping the Steam microphone..."


func _drain_after_stop(delta: float) -> void:
	_transition_elapsed_seconds += delta
	if not Engine.has_singleton("Steam") or not NetworkManager.steam_ready:
		_finish_stop()
		return
	var result := _drain_voice_tail_once()
	if result in [VOICE_RESULT_NOT_INITIALIZED, VOICE_RESULT_NOT_RECORDING]:
		_finish_stop()
		return
	if _transition_elapsed_seconds >= TRANSITION_TIMEOUT_SECONDS:
		_finish_stop()


func _finish_stop() -> void:
	_capture_running = false
	_transition_elapsed_seconds = 0.0
	input_level_db = METER_FLOOR_DB
	_meter_target_db = METER_FLOOR_DB
	_reset_input_voice_visual()
	test_state = _stop_target_state
	status_text = _stop_target_status
	_status_arguments = _stop_target_arguments.duplicate()
	SettingsManager.set_microphone_test_active(false)


func _drain_voice_tail_once() -> int:
	var voice_data: Dictionary = Steam.getVoice(STOP_DRAIN_BUFFER_BYTES)
	var result := int(voice_data.get("result", VOICE_RESULT_NOT_INITIALIZED))
	if result != VOICE_RESULT_BUFFER_TOO_SMALL:
		return result
	var available_voice: Dictionary = Steam.getAvailableVoice()
	var available_result := int(
		available_voice.get("result", VOICE_RESULT_NOT_INITIALIZED)
	)
	if available_result in [VOICE_RESULT_NOT_INITIALIZED, VOICE_RESULT_NOT_RECORDING]:
		return available_result
	var available_size := int(available_voice.get("size", 0))
	if available_size <= 0 or available_size > MAX_COMPRESSED_RECOVERY_BYTES:
		return result
	voice_data = Steam.getVoice(available_size)
	return int(voice_data.get("result", VOICE_RESULT_NOT_INITIALIZED))


func _poll_steam_microphone() -> void:
	if not _capture_running or not NetworkManager.steam_ready:
		_fail("Steam microphone capture stopped unexpectedly.")
		return
	var available_voice: Dictionary = Steam.getAvailableVoice()
	if available_voice.is_empty():
		_fail("Steam microphone is unavailable.")
		return
	var available_result := int(available_voice.get("result", VOICE_RESULT_NO_DATA))
	var available_size := int(available_voice.get("size", 0))
	if available_result == VOICE_RESULT_NO_DATA:
		_meter_target_db = METER_FLOOR_DB
		return
	if available_result != VOICE_RESULT_OK:
		_fail("Steam microphone error (VoiceResult %d).", [available_result])
		return
	if available_size <= 0:
		_meter_target_db = METER_FLOOR_DB
		return
	if available_size > MAX_COMPRESSED_DRAIN_BYTES:
		if available_size <= MAX_COMPRESSED_RECOVERY_BYTES:
			Steam.getVoice(available_size)
			_meter_target_db = METER_FLOOR_DB
			status_text = "A delayed Steam microphone backlog was discarded."
			return
		_fail("Steam microphone buffer overflowed. Stop and restart the test.")
		return

	var voice_data: Dictionary = Steam.getVoice(available_size)
	var voice_result := int(voice_data.get("result", VOICE_RESULT_NO_DATA))
	if voice_result == VOICE_RESULT_NO_DATA:
		_meter_target_db = METER_FLOOR_DB
		return
	if voice_result != VOICE_RESULT_OK:
		_fail("Steam microphone read failed (VoiceResult %d).", [voice_result])
		return
	var compressed: PackedByteArray = voice_data.get("buffer", PackedByteArray())
	var written_size := mini(int(voice_data.get("size", compressed.size())), compressed.size())
	if written_size <= 0:
		_meter_target_db = METER_FLOOR_DB
		return
	compressed = compressed.slice(0, written_size)
	_voice_data_age_seconds = 0.0
	var frames := _decompress_voice_packet(compressed)
	if frames.is_empty():
		_meter_target_db = METER_FLOOR_DB
		return
	frames = _apply_microphone_gain(frames)
	_register_input_voice_frames(frames)
	_meter_target_db = _measure_rms_db(frames)
	status_text = (
		"Live Satan test active. Use headphones to prevent feedback."
		if test_state == TestState.MONITORING
		else "Listening through Steam. Speak to check the input level."
	)
	if test_state == TestState.MONITORING:
		_push_monitor_frames(frames)


func _update_no_input_hint() -> void:
	if _voice_data_age_seconds < NO_INPUT_HINT_SECONDS:
		return
	status_text = "No voice signal. Check the voice microphone selected in Steam / Windows."


func _decompress_voice_packet(payload: PackedByteArray) -> PackedVector2Array:
	var decoded: Dictionary = Steam.decompressVoice(
		payload,
		VOICE_SAMPLE_RATE,
		INITIAL_DECOMPRESS_BUFFER_BYTES
	)
	var result := int(decoded.get("result", VOICE_RESULT_NO_DATA))
	if result == VOICE_RESULT_BUFFER_TOO_SMALL:
		var required_size := int(decoded.get("size", 0))
		if (
			required_size > INITIAL_DECOMPRESS_BUFFER_BYTES
			and required_size <= MAX_DECOMPRESS_BUFFER_BYTES
		):
			decoded = Steam.decompressVoice(payload, VOICE_SAMPLE_RATE, required_size)
			result = int(decoded.get("result", VOICE_RESULT_NO_DATA))
	if result != VOICE_RESULT_OK:
		return PackedVector2Array()

	var pcm_bytes: PackedByteArray = decoded.get("uncompressed", PackedByteArray())
	var valid_size := mini(int(decoded.get("size", 0)), pcm_bytes.size())
	valid_size -= valid_size % 2
	if valid_size <= 0:
		return PackedVector2Array()
	var frames := PackedVector2Array()
	frames.resize(valid_size >> 1)
	for frame_index in range(frames.size()):
		var sample := float(pcm_bytes.decode_s16(frame_index * 2)) / 32768.0
		frames[frame_index] = Vector2(sample, sample)
	return frames


func _measure_rms_db(frames: PackedVector2Array) -> float:
	if frames.is_empty():
		return METER_FLOOR_DB
	var sample_step := maxi(floori(float(frames.size()) / 2048.0), 1)
	var squared_sum := 0.0
	var sample_count := 0
	for frame_index in range(0, frames.size(), sample_step):
		var sample := frames[frame_index].x
		squared_sum += sample * sample
		sample_count += 1
	var rms := sqrt(squared_sum / maxf(float(sample_count), 1.0))
	return clampf(linear_to_db(maxf(rms, 0.001)), METER_FLOOR_DB, 0.0)


func _apply_microphone_gain(
	frames: PackedVector2Array
) -> PackedVector2Array:
	var microphone_gain := clampf(
		SettingsManager.microphone_gain,
		SettingsManager.MIN_MICROPHONE_GAIN,
		SettingsManager.MAX_MICROPHONE_GAIN
	)
	if is_equal_approx(microphone_gain, 1.0):
		return frames
	for frame_index in range(frames.size()):
		var frame := frames[frame_index]
		frames[frame_index] = Vector2(
			clampf(frame.x * microphone_gain, -1.0, 1.0),
			clampf(frame.y * microphone_gain, -1.0, 1.0)
		)
	return frames


func _register_input_voice_frames(frames: PackedVector2Array) -> void:
	_received_input_pcm_this_frame = true
	var window_start := 0
	while window_start < frames.size():
		var window_end := mini(
			window_start + VOICE_VISUAL_WINDOW_FRAMES,
			frames.size()
		)
		var window_count := window_end - window_start
		if (
			window_count < VOICE_VISUAL_MIN_WINDOW_FRAMES
			and frames.size() >= VOICE_VISUAL_MIN_WINDOW_FRAMES
		):
			break
		var levels := _measure_input_voice_window(
			frames,
			window_start,
			window_end
		)
		_register_input_voice_window(
			levels.x,
			levels.y,
			float(window_count) / float(VOICE_SAMPLE_RATE)
		)
		window_start = window_end


func _measure_input_voice_window(
	frames: PackedVector2Array,
	window_start: int,
	window_end: int
) -> Vector2:
	var squared_sum := 0.0
	var peak := 0.0
	for frame_index in range(window_start, window_end):
		var sample := absf(frames[frame_index].x)
		peak = maxf(peak, sample)
		squared_sum += sample * sample
	var sample_count := maxi(window_end - window_start, 1)
	var rms := sqrt(squared_sum / float(sample_count))
	return Vector2(
		clampf(linear_to_db(maxf(rms, 0.001)), METER_FLOOR_DB, 0.0),
		clampf(linear_to_db(maxf(peak, 0.001)), METER_FLOOR_DB, 0.0)
	)


func _register_input_voice_window(
	rms_db: float,
	peak_db: float,
	window_seconds: float
) -> void:
	_advance_input_voice_level(
		_map_input_voice_level(rms_db, peak_db),
		window_seconds
	)

	var speech_rms_threshold := (
		SPEECH_KEEP_RMS_DB
		if input_voice_activity != InputVoiceActivity.SILENT
		else SPEECH_START_RMS_DB
	)
	var speech_peak_threshold := (
		SPEECH_KEEP_PEAK_DB
		if input_voice_activity != InputVoiceActivity.SILENT
		else SPEECH_START_PEAK_DB
	)
	if rms_db >= speech_rms_threshold and peak_db >= speech_peak_threshold:
		if input_voice_activity != InputVoiceActivity.SILENT:
			_input_speech_hold_seconds = SPEECH_HOLD_SECONDS
			_input_speech_attack_seconds = 0.0
		else:
			_input_speech_attack_seconds += window_seconds
			if _input_speech_attack_seconds >= SPEECH_ATTACK_SECONDS:
				_input_speech_hold_seconds = SPEECH_HOLD_SECONDS
				_input_speech_attack_seconds = 0.0
	else:
		_input_speech_attack_seconds = 0.0

	var loud_rms_threshold := (
		LOUD_KEEP_RMS_DB
		if input_voice_activity == InputVoiceActivity.LOUD
		else LOUD_START_RMS_DB
	)
	var loud_peak_threshold := (
		LOUD_KEEP_PEAK_DB
		if input_voice_activity == InputVoiceActivity.LOUD
		else LOUD_START_PEAK_DB
	)
	var loud_hold_refreshed := false
	if rms_db >= loud_rms_threshold and peak_db >= loud_peak_threshold:
		if input_voice_activity == InputVoiceActivity.LOUD:
			_input_loud_hold_seconds = LOUD_HOLD_SECONDS
			_input_loud_attack_seconds = 0.0
			loud_hold_refreshed = true
		else:
			_input_loud_attack_seconds += window_seconds
			if _input_loud_attack_seconds >= LOUD_ATTACK_SECONDS:
				_input_loud_hold_seconds = LOUD_HOLD_SECONDS
				_input_loud_attack_seconds = 0.0
				loud_hold_refreshed = true
	else:
		_input_loud_attack_seconds = 0.0
	if loud_hold_refreshed:
		_input_speech_hold_seconds = maxf(
			_input_speech_hold_seconds,
			SPEECH_HOLD_SECONDS
		)


func _map_input_voice_level(rms_db: float, peak_db: float) -> float:
	var base_rms := clampf(
		inverse_lerp(SPEECH_KEEP_RMS_DB, LOUD_START_RMS_DB, rms_db),
		0.0,
		1.0
	)
	var base_peak := clampf(
		inverse_lerp(SPEECH_KEEP_PEAK_DB, LOUD_START_PEAK_DB, peak_db),
		0.0,
		1.0
	)
	var base_level := minf(base_rms, base_peak)
	if base_level < 1.0:
		return VOICE_LEVEL_LOUD_SHARE * base_level

	var hot_rms := clampf(
		inverse_lerp(LOUD_START_RMS_DB, 0.0, rms_db),
		0.0,
		1.0
	)
	var hot_peak := clampf(
		inverse_lerp(LOUD_START_PEAK_DB, 0.0, peak_db),
		0.0,
		1.0
	)
	return lerpf(
		VOICE_LEVEL_LOUD_SHARE,
		1.0,
		minf(hot_rms, hot_peak)
	)


func _advance_input_voice_level(target_level: float, duration: float) -> void:
	target_level = clampf(target_level, 0.0, 1.0)
	duration = maxf(duration, 0.0)
	if duration <= 0.0:
		return
	var tau := (
		VOICE_LEVEL_ATTACK_TAU_SECONDS
		if target_level > input_voice_level
		else VOICE_LEVEL_RELEASE_TAU_SECONDS
	)
	var blend := 1.0 - exp(-duration / maxf(tau, 0.001))
	input_voice_level = clampf(
		lerpf(input_voice_level, target_level, blend),
		0.0,
		1.0
	)
	if target_level <= 0.0 and input_voice_level < VOICE_LEVEL_ZERO_EPSILON:
		input_voice_level = 0.0


func _finalize_input_voice_visual(delta: float) -> void:
	if test_state not in [TestState.LISTENING, TestState.MONITORING]:
		_reset_input_voice_visual()
		return

	if _received_input_pcm_this_frame:
		_input_voice_attack_gap_seconds = 0.0
	else:
		_advance_input_voice_level(0.0, delta)
		_input_voice_attack_gap_seconds += delta
		if _input_voice_attack_gap_seconds >= VOICE_ATTACK_MAX_GAP_SECONDS:
			_reset_input_voice_attack()

	if _input_loud_hold_seconds > 0.0:
		input_voice_activity = InputVoiceActivity.LOUD
	elif _input_speech_hold_seconds > 0.0:
		input_voice_activity = InputVoiceActivity.SPEAKING
	else:
		input_voice_activity = InputVoiceActivity.SILENT


func _reset_input_voice_visual() -> void:
	_reset_input_voice_attack()
	_input_speech_hold_seconds = 0.0
	_input_loud_hold_seconds = 0.0
	_input_voice_attack_gap_seconds = 0.0
	_received_input_pcm_this_frame = false
	input_voice_activity = InputVoiceActivity.SILENT
	input_voice_level = 0.0


func _reset_input_voice_attack() -> void:
	_input_speech_attack_seconds = 0.0
	_input_loud_attack_seconds = 0.0


func _update_meter(delta: float) -> void:
	if test_state not in [TestState.LISTENING, TestState.MONITORING]:
		_meter_target_db = METER_FLOOR_DB
	var speed := (
		METER_ATTACK_DB_PER_SECOND
		if _meter_target_db > input_level_db
		else METER_RELEASE_DB_PER_SECOND
	)
	input_level_db = move_toward(input_level_db, _meter_target_db, speed * delta)


func _push_monitor_frames(frames: PackedVector2Array) -> void:
	_monitor_pcm_queue.append_array(frames)
	var max_queue_frames := roundi(MONITOR_MAX_QUEUE_SECONDS * VOICE_SAMPLE_RATE)
	if _monitor_pcm_queue.size() > max_queue_frames:
		var keep_frames := roundi(MONITOR_RECOVERY_BUFFER_SECONDS * VOICE_SAMPLE_RATE)
		_monitor_pcm_queue = _monitor_pcm_queue.slice(
			_monitor_pcm_queue.size() - keep_frames
		)

	if _output_playback != null:
		var skip_count := _output_playback.get_skips()
		if skip_count > _last_monitor_skip_count:
			_stop_output_player()
			_monitor_recovering = true
			return
		_last_monitor_skip_count = skip_count

	if _output_playback == null:
		var target_seconds := (
			MONITOR_RECOVERY_BUFFER_SECONDS
			if _monitor_recovering
			else MONITOR_START_BUFFER_SECONDS
		)
		if _monitor_pcm_queue.size() < roundi(target_seconds * VOICE_SAMPLE_RATE):
			return
		if not _start_output_player():
			return
		_monitor_recovering = false

	var available_frames := _output_playback.get_frames_available()
	if available_frames <= 0:
		return
	var push_count := mini(available_frames, _monitor_pcm_queue.size())
	var push_frames := _monitor_pcm_queue.slice(0, push_count)
	if _output_playback.push_buffer(push_frames):
		_monitor_pcm_queue = _monitor_pcm_queue.slice(push_count)


func _create_output_player() -> void:
	_output_player = AudioStreamPlayer.new()
	_output_player.name = "LiveSatanMicrophoneTest"
	_output_player.bus = VOICE_BUS_NAME
	_output_player.pitch_scale = 1.0
	add_child(_output_player)


func _start_output_player() -> bool:
	if _output_player == null or not is_instance_valid(_output_player):
		return false
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = float(VOICE_SAMPLE_RATE)
	stream.buffer_length = MONITOR_GENERATOR_BUFFER_SECONDS
	_output_player.stop()
	_output_player.stream = stream
	_output_player.pitch_scale = 1.0
	_output_player.play()
	_output_playback = _output_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if _output_playback == null:
		_output_player.stop()
		_output_player.stream = null
		return false
	_last_monitor_skip_count = _output_playback.get_skips()
	return true


func _stop_output_player() -> void:
	if _output_player != null and is_instance_valid(_output_player):
		_output_player.stop()
		_output_player.stream = null
	_output_playback = null
	_last_monitor_skip_count = 0


func _ensure_voice_bus_and_pitch_effect() -> AudioEffectPitchShift:
	var voice_bus := AudioServer.get_bus_index(VOICE_BUS_NAME)
	if voice_bus < 0:
		AudioServer.add_bus()
		voice_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(voice_bus, VOICE_BUS_NAME)
	AudioServer.set_bus_send(voice_bus, &"Master")

	for effect_index in range(AudioServer.get_bus_effect_count(voice_bus)):
		var effect := AudioServer.get_bus_effect(voice_bus, effect_index)
		if effect is AudioEffectPitchShift:
			var pitch_effect := effect as AudioEffectPitchShift
			pitch_effect.fft_size = AudioEffectPitchShift.FFT_SIZE_512
			pitch_effect.oversampling = 4
			AudioServer.set_bus_effect_enabled(voice_bus, effect_index, true)
			return pitch_effect

	var pitch_effect := AudioEffectPitchShift.new()
	pitch_effect.pitch_scale = SettingsManager.satan_voice_pitch
	pitch_effect.fft_size = AudioEffectPitchShift.FFT_SIZE_512
	pitch_effect.oversampling = 4
	AudioServer.add_bus_effect(voice_bus, pitch_effect)
	return pitch_effect


func _apply_local_test_pitch() -> void:
	if _pitch_effect != null:
		_pitch_effect.pitch_scale = SettingsManager.satan_voice_pitch


func _is_monitor_output_audible() -> bool:
	var master_bus := AudioServer.get_bus_index(&"Master")
	var voice_bus := AudioServer.get_bus_index(VOICE_BUS_NAME)
	return (
		master_bus >= 0
		and voice_bus >= 0
		and not AudioServer.is_bus_mute(master_bus)
		and not AudioServer.is_bus_mute(voice_bus)
		and AudioServer.get_bus_volume_db(master_bus) > -79.0
		and AudioServer.get_bus_volume_db(voice_bus) > -79.0
	)


func _fail(message: String, arguments: Array = []) -> void:
	_begin_stop(TestState.ERROR, message, arguments)


func _set_error_immediately(message: String) -> void:
	_capture_running = false
	_stop_output_player()
	_monitor_pcm_queue.clear()
	SettingsManager.set_microphone_test_active(false)
	input_level_db = METER_FLOOR_DB
	_meter_target_db = METER_FLOOR_DB
	_reset_input_voice_visual()
	test_state = TestState.ERROR
	status_text = message


func _exit_tree() -> void:
	if Engine.has_singleton("Steam") and NetworkManager.steam_ready and (
		_capture_running or SettingsManager.microphone_test_active
	):
		Steam.stopVoiceRecording()
	_capture_running = false
	_reset_input_voice_visual()
	SettingsManager.set_microphone_test_active(false)
