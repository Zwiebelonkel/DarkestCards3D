extends Node
class_name SatanVoiceChat

signal remote_voice_activity_changed(activity: int)
signal remote_voice_level_changed(level: float)

enum RemoteVoiceActivity { SILENT, SPEAKING, LOUD }

const VOICE_BUS_NAME: StringName = &"SatanVoice"
const VOICE_SAMPLE_RATE := 24000
const INITIAL_DECOMPRESS_BUFFER_BYTES := 32768
const MAX_DECOMPRESS_BUFFER_BYTES := 96000
const MAX_COMPRESSED_DRAIN_BYTES := 64 * 1024
const MAX_COMPRESSED_RECOVERY_BYTES := 1024 * 1024
const STOP_DRAIN_BUFFER_BYTES := 8192
const STOP_DRAIN_TIMEOUT_SECONDS := 1.0
const VOICE_ENVELOPE_MAGIC := 0x43564344 # "DCVC" in little-endian byte order.
const VOICE_ENVELOPE_VERSION := 2
const VOICE_ENVELOPE_HEADER_BYTES := 7
const LEGACY_VOICE_ENVELOPE_HEADER_BYTES := 6
const DEFAULT_MICROPHONE_GAIN_PERCENT := 100
const MAX_MICROPHONE_GAIN_PERCENT := 2000
const MAX_PENDING_PACKETS := 8
const MAX_SEQUENCE_LEAD := 64
const MAX_PACKETS_DECODED_PER_FRAME := 8
const MAX_GAP_SILENCE_PACKETS := 2
const START_BUFFER_SECONDS := 0.06
const RECOVERY_BUFFER_SECONDS := 0.08
const MAX_TOTAL_BUFFER_SECONDS := 0.18
const GENERATOR_BUFFER_SECONDS := 0.12
const MISSING_PACKET_WAIT_SECONDS := 0.035
const REMOTE_PACKET_TIMEOUT_SECONDS := 0.35
const CAPTURE_RETRY_SECONDS := 2.0
const RETIRED_STREAM_TTL_MSEC := 5000
const MAX_RETIRED_STREAMS := 8
const VOICE_LEVEL_FLOOR_DB := -60.0
const VOICE_LEVEL_WINDOW_FRAMES := 480
const VOICE_LEVEL_MIN_WINDOW_FRAMES := 120
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
const VOICE_LEVEL_SIGNAL_EPSILON := 0.005
const VOICE_LEVEL_ZERO_EPSILON := 0.001

const VOICE_RESULT_OK := 0
const VOICE_RESULT_NOT_INITIALIZED := 1
const VOICE_RESULT_NOT_RECORDING := 2
const VOICE_RESULT_NO_DATA := 3
const VOICE_RESULT_BUFFER_TOO_SMALL := 4

var _anchor: Node3D = null
var _output_player: AudioStreamPlayer3D = null
var _output_playback: AudioStreamGeneratorPlayback = null
var _pitch_effect: AudioEffectPitchShift = null
var _rng := RandomNumberGenerator.new()

var _match_active := false
var _capture_running := false
var _capture_start_pending := false
var _capture_start_elapsed_seconds := 0.0
var _capture_stop_pending := false
var _capture_stop_elapsed_seconds := 0.0
var _capture_retry_seconds := 0.0
var _capture_warning_emitted := false
var _send_stream_id := 0
var _send_sequence := 0

var _receive_stream_id := 0
var _next_receive_sequence := -1
var _compressed_packets: Dictionary = {}
var _retired_receive_streams: Dictionary = {}
var _pcm_queue := PackedVector2Array()
var _missing_packet_wait_seconds := 0.0
var _remote_packet_age_seconds := 0.0
var _last_decoded_frame_count := 0
var _output_started := false
var _recovering_from_underrun := false
var _last_playback_skip_count := 0
var _active_remote_pitch_percent := 62
var _remote_voice_activity := RemoteVoiceActivity.SILENT
var _speech_attack_seconds := 0.0
var _loud_attack_seconds := 0.0
var _speech_hold_seconds := 0.0
var _loud_hold_seconds := 0.0
var _voice_attack_gap_seconds := 0.0
var _received_remote_pcm_this_frame := false
var _remote_voice_level := 0.0
var _last_emitted_remote_voice_level := 0.0


func configure(anchor: Node3D) -> void:
	_anchor = anchor


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_pitch_effect = _ensure_voice_bus_and_pitch_effect()
	_create_output_player()
	if not SettingsManager.satan_voice_settings_changed.is_connected(_on_settings_changed):
		SettingsManager.satan_voice_settings_changed.connect(_on_settings_changed)
	if not SettingsManager.microphone_test_state_changed.is_connected(
		_on_microphone_test_state_changed
	):
		SettingsManager.microphone_test_state_changed.connect(
			_on_microphone_test_state_changed
		)
	if not NetworkManager.voice_packet_received.is_connected(_on_voice_packet_received):
		NetworkManager.voice_packet_received.connect(_on_voice_packet_received)
	if not NetworkManager.connection_state_changed.is_connected(_on_connection_state_changed):
		NetworkManager.connection_state_changed.connect(_on_connection_state_changed)
	if not NetworkManager.session_closing.is_connected(_on_session_closing):
		NetworkManager.session_closing.connect(_on_session_closing)
	if not NetworkManager.session_closed.is_connected(_on_session_closed):
		NetworkManager.session_closed.connect(_on_session_closed)
	_on_settings_changed()


func _process(delta: float) -> void:
	_process_remote_audio(delta)
	_process_local_capture(delta)


func set_match_active(active: bool) -> void:
	if _match_active == active:
		_refresh_session_state()
		return
	_match_active = active
	if not _match_active:
		_stop_capture()
		_suspend_or_clear_remote_audio()
	else:
		_refresh_session_state()


func _on_settings_changed() -> void:
	_apply_voice_volume()
	_refresh_session_state()


func _on_microphone_test_state_changed(is_active: bool) -> void:
	if is_active:
		# The microphone test takes over the Steam recorder. It drains the short
		# Steam tail before starting, so this node must no longer poll that tail.
		if _capture_running:
			_stop_capture(true)
		else:
			_capture_start_pending = false
			_capture_stop_pending = false
	_refresh_session_state()


func _on_connection_state_changed() -> void:
	_refresh_session_state()


func _on_session_closing() -> void:
	_stop_session_audio()


func _on_session_closed(_reason: String) -> void:
	_stop_session_audio()


func _stop_session_audio() -> void:
	_match_active = false
	_stop_and_clear()


func _session_should_run() -> bool:
	return (
		_match_active
		and SettingsManager.satan_voice_enabled
		and NetworkManager.steam_ready
		and NetworkManager.is_match_in_progress()
		and NetworkManager.has_connected_opponent()
	)


func _capture_should_run() -> bool:
	return _session_should_run() and not SettingsManager.microphone_test_active


func _output_should_run() -> bool:
	# The local live monitor uses the same pitch-shift bus. Pausing incoming
	# voice during that explicit test avoids two owners fighting over the FX.
	return _session_should_run() and not SettingsManager.microphone_test_active


func _transport_can_resume() -> bool:
	return (
		NetworkManager.is_match_in_progress()
		and NetworkManager.has_connected_opponent()
	)


func _refresh_session_state() -> void:
	if _capture_should_run():
		if (
			not _capture_running
			and not _capture_start_pending
			and not _capture_stop_pending
			and _capture_retry_seconds <= 0.0
		):
			_request_capture_start()
	elif _capture_running:
		_stop_capture(SettingsManager.microphone_test_active)
	elif not _capture_should_run():
		_capture_start_pending = false

	if not _output_should_run():
		_suspend_or_clear_remote_audio()


func _request_capture_start() -> void:
	if (
		_capture_running
		or _capture_start_pending
		or _capture_stop_pending
		or not Engine.has_singleton("Steam")
		or not NetworkManager.steam_ready
		or not _capture_should_run()
	):
		return
	# Always confirm that Steam's previous recorder owner has fully stopped.
	# This also protects the rare case where the settings controller left the
	# tree before it could finish its own STOPPING drain.
	Steam.stopVoiceRecording()
	_capture_start_pending = true
	_capture_start_elapsed_seconds = 0.0


func _start_capture_now() -> void:
	if not _capture_should_run() or not NetworkManager.steam_ready:
		_capture_start_pending = false
		return
	Steam.startVoiceRecording()
	_capture_start_pending = false
	_capture_start_elapsed_seconds = 0.0
	_capture_running = true
	_capture_retry_seconds = 0.0
	_send_stream_id = _rng.randi_range(1, NetworkManager.VOICE_MAX_STREAM_ID)
	_send_sequence = 0


func _stop_capture(handoff_to_microphone_test := false) -> void:
	_capture_start_pending = false
	_capture_start_elapsed_seconds = 0.0
	if (
		_capture_running
		and Engine.has_singleton("Steam")
		and NetworkManager.steam_ready
	):
		Steam.stopVoiceRecording()
		_capture_stop_pending = (
			not handoff_to_microphone_test
			and NetworkManager.steam_ready
		)
		_capture_stop_elapsed_seconds = 0.0
	_capture_running = false
	_capture_retry_seconds = 0.0
	_send_stream_id = 0
	_send_sequence = 0


func _process_local_capture(delta: float) -> void:
	if _capture_stop_pending:
		_drain_stopped_capture(delta)
		return
	if _capture_start_pending:
		if _capture_should_run():
			_drain_before_capture_start(delta)
		else:
			_capture_start_pending = false
		return

	if not _capture_should_run():
		if _capture_running:
			_stop_capture(SettingsManager.microphone_test_active)
		return

	if not _capture_running:
		_capture_retry_seconds = maxf(_capture_retry_seconds - delta, 0.0)
		if _capture_retry_seconds <= 0.0:
			_request_capture_start()
		return

	var available_voice: Dictionary = Steam.getAvailableVoice()
	if available_voice.is_empty():
		_handle_capture_failure(VOICE_RESULT_NOT_INITIALIZED)
		return
	var available_result := int(available_voice.get("result", VOICE_RESULT_NO_DATA))
	var available_size := int(available_voice.get("size", 0))
	if available_result == VOICE_RESULT_NO_DATA:
		return
	if available_result != VOICE_RESULT_OK:
		_handle_capture_failure(available_result)
		return
	if available_size <= 0:
		return
	if available_size > MAX_COMPRESSED_DRAIN_BYTES:
		if available_size <= MAX_COMPRESSED_RECOVERY_BYTES:
			# A stalled frame can leave a large local backlog. Drain and discard it
			# in one call instead of repeatedly transmitting stale speech.
			Steam.getVoice(available_size)
			return
		_handle_capture_failure(VOICE_RESULT_BUFFER_TOO_SMALL)
		return

	var voice_data: Dictionary = Steam.getVoice(available_size)
	var voice_result := int(voice_data.get("result", VOICE_RESULT_NO_DATA))
	if voice_result == VOICE_RESULT_NO_DATA:
		return
	if voice_result != VOICE_RESULT_OK:
		_handle_capture_failure(voice_result)
		return
	_capture_warning_emitted = false
	var payload: PackedByteArray = voice_data.get("buffer", PackedByteArray())
	var written_size := mini(int(voice_data.get("size", payload.size())), payload.size())
	if written_size <= 0:
		return
	payload = payload.slice(0, written_size)
	if (
		payload.size()
		> NetworkManager.VOICE_MAX_PACKET_BYTES - VOICE_ENVELOPE_HEADER_BYTES
	):
		# The data has been drained from Steam. Dropping an oversized chunk keeps
		# latency bounded and avoids fragmentation on the real-time RPC channel.
		return
	var pitch_percent := clampi(roundi(SettingsManager.satan_voice_pitch * 100.0), 35, 90)
	var microphone_gain_percent := clampi(
		roundi(SettingsManager.microphone_gain * 100.0),
		0,
		MAX_MICROPHONE_GAIN_PERCENT
	)
	var network_payload := _pack_voice_payload(payload, microphone_gain_percent)
	NetworkManager.send_voice_packet(
		_send_stream_id,
		_send_sequence,
		pitch_percent,
		network_payload
	)
	_send_sequence += 1
	if _send_sequence > NetworkManager.VOICE_MAX_SEQUENCE:
		_send_stream_id = _rng.randi_range(1, NetworkManager.VOICE_MAX_STREAM_ID)
		_send_sequence = 0


func _handle_capture_failure(result: int) -> void:
	_stop_capture()
	_capture_retry_seconds = CAPTURE_RETRY_SECONDS
	if not _capture_warning_emitted:
		_capture_warning_emitted = true
		push_warning(
			"Satan Voice Chat: Steam-Mikrofon konnte nicht gelesen werden "
			+ "(VoiceResult %d). Die Aufnahme wird erneut versucht." % result
		)


func _drain_before_capture_start(delta: float) -> void:
	_capture_start_elapsed_seconds += delta
	if not Engine.has_singleton("Steam") or not NetworkManager.steam_ready:
		_capture_start_pending = false
		return
	var result := _drain_capture_tail_once()
	if result == VOICE_RESULT_NOT_RECORDING:
		_start_capture_now()
		return
	if result == VOICE_RESULT_NOT_INITIALIZED:
		_handle_capture_failure(result)
		return
	if _capture_start_elapsed_seconds >= STOP_DRAIN_TIMEOUT_SECONDS:
		Steam.stopVoiceRecording()
		_capture_start_elapsed_seconds = 0.0
		if not _capture_warning_emitted:
			_capture_warning_emitted = true
			push_warning(
				"Satan Voice Chat: Warte weiter auf die Freigabe des Steam-Mikrofons."
			)


func _drain_stopped_capture(delta: float) -> void:
	_capture_stop_elapsed_seconds += delta
	if not Engine.has_singleton("Steam") or not NetworkManager.steam_ready:
		_finish_capture_stop_drain()
		return

	# Steam continues capturing briefly after stopVoiceRecording(). Discard all
	# of that tail until getVoice() confirms VOICE_RESULT_NOT_RECORDING, so no
	# local-test tail can become the first packet of an online session.
	var result := _drain_capture_tail_once()
	if result in [VOICE_RESULT_NOT_INITIALIZED, VOICE_RESULT_NOT_RECORDING]:
		_finish_capture_stop_drain()
		return

	if _capture_stop_elapsed_seconds >= STOP_DRAIN_TIMEOUT_SECONDS:
		Steam.stopVoiceRecording()
		_capture_stop_elapsed_seconds = 0.0
		if not _capture_warning_emitted:
			_capture_warning_emitted = true
			push_warning(
				"Satan Voice Chat: Warte weiter auf das Ende der Steam-Aufnahme."
			)


func _drain_capture_tail_once() -> int:
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


func _finish_capture_stop_drain() -> void:
	_capture_stop_pending = false
	_capture_stop_elapsed_seconds = 0.0


func _pack_voice_payload(
	steam_payload: PackedByteArray,
	microphone_gain_percent: int
) -> PackedByteArray:
	microphone_gain_percent = clampi(microphone_gain_percent, 0, MAX_MICROPHONE_GAIN_PERCENT)
	# Keep the original format for its supported range; larger gains need two bytes.
	var use_legacy := microphone_gain_percent <= 200
	var network_payload := PackedByteArray()
	network_payload.resize(LEGACY_VOICE_ENVELOPE_HEADER_BYTES if use_legacy else VOICE_ENVELOPE_HEADER_BYTES)
	network_payload.encode_u32(0, VOICE_ENVELOPE_MAGIC)
	network_payload[4] = 1 if use_legacy else VOICE_ENVELOPE_VERSION
	if use_legacy:
		network_payload[5] = microphone_gain_percent
	else:
		network_payload.encode_u16(5, microphone_gain_percent)
	network_payload.append_array(steam_payload)
	return network_payload


func _unpack_voice_payload(network_payload: PackedByteArray) -> Dictionary:
	# Pre-envelope clients sent Steam's compressed bytes directly. Keep those
	# packets playable at neutral gain while both peers migrate to this format.
	if (
		network_payload.size() < 4
		or network_payload.decode_u32(0) != VOICE_ENVELOPE_MAGIC
	):
		return {
			"valid": not network_payload.is_empty(),
			"microphone_gain": 1.0,
			"payload": network_payload,
		}

	# Once the magic matches, malformed or future envelope versions must not be
	# passed to Steam as compressed audio.
	if network_payload.size() <= LEGACY_VOICE_ENVELOPE_HEADER_BYTES:
		return {"valid": false}
	var version := int(network_payload[4])
	var header_bytes := LEGACY_VOICE_ENVELOPE_HEADER_BYTES
	var microphone_gain_percent := int(network_payload[5])
	if version == VOICE_ENVELOPE_VERSION:
		header_bytes = VOICE_ENVELOPE_HEADER_BYTES
		if network_payload.size() <= header_bytes:
			return {"valid": false}
		microphone_gain_percent = network_payload.decode_u16(5)
	elif version != 1:
		return {"valid": false}
	if microphone_gain_percent > (200 if version == 1 else MAX_MICROPHONE_GAIN_PERCENT):
		return {"valid": false}
	return {
		"valid": true,
		"microphone_gain": float(microphone_gain_percent) / 100.0,
		"payload": network_payload.slice(header_bytes),
	}


func _on_voice_packet_received(
	stream_id: int,
	sequence: int,
	pitch_percent: int,
	payload: PackedByteArray
) -> void:
	if not _output_should_run():
		return
	var voice_envelope := _unpack_voice_payload(payload)
	if not bool(voice_envelope.get("valid", false)):
		return
	var steam_payload: PackedByteArray = voice_envelope.get(
		"payload",
		PackedByteArray()
	)
	if steam_payload.is_empty():
		return
	_prune_retired_receive_streams()
	if _retired_receive_streams.has(stream_id):
		return
	if stream_id != _receive_stream_id:
		_reset_receive_stream(stream_id, sequence)
	elif _next_receive_sequence >= 0 and sequence < _next_receive_sequence:
		return
	elif sequence - _next_receive_sequence > MAX_SEQUENCE_LEAD:
		_reset_receive_stream(stream_id, sequence)
	if _compressed_packets.has(sequence):
		return
	if _compressed_packets.size() >= MAX_PENDING_PACKETS:
		_reset_receive_stream(stream_id, sequence)
	_compressed_packets[sequence] = {
		"pitch_percent": pitch_percent,
		"microphone_gain": float(voice_envelope.get("microphone_gain", 1.0)),
		"payload": steam_payload.duplicate(),
	}
	_remote_packet_age_seconds = 0.0


func _reset_receive_stream(stream_id: int, first_sequence: int) -> void:
	if _receive_stream_id != 0 and _receive_stream_id != stream_id:
		_retire_receive_stream(_receive_stream_id)
	_reset_remote_voice_activity()
	_stop_output_player()
	_compressed_packets.clear()
	_pcm_queue.clear()
	_receive_stream_id = stream_id
	_next_receive_sequence = first_sequence
	_missing_packet_wait_seconds = 0.0
	_remote_packet_age_seconds = 0.0
	_last_decoded_frame_count = 0
	_output_started = false
	_recovering_from_underrun = false


func _retire_receive_stream(stream_id: int) -> void:
	if stream_id <= 0:
		return
	_retired_receive_streams[stream_id] = (
		Time.get_ticks_msec() + RETIRED_STREAM_TTL_MSEC
	)
	_prune_retired_receive_streams()
	while _retired_receive_streams.size() > MAX_RETIRED_STREAMS:
		var oldest_stream_id := 0
		var oldest_expiry := 9_223_372_036_854_775_807
		for retired_id: Variant in _retired_receive_streams.keys():
			var expiry := int(_retired_receive_streams[retired_id])
			if expiry < oldest_expiry:
				oldest_expiry = expiry
				oldest_stream_id = int(retired_id)
		_retired_receive_streams.erase(oldest_stream_id)


func _prune_retired_receive_streams() -> void:
	var now_msec := Time.get_ticks_msec()
	for retired_id: Variant in _retired_receive_streams.keys():
		if int(_retired_receive_streams[retired_id]) <= now_msec:
			_retired_receive_streams.erase(retired_id)


func _process_remote_audio(delta: float) -> void:
	if not _output_should_run():
		_reset_remote_voice_activity()
		if _receive_stream_id != 0 or _output_started:
			_suspend_or_clear_remote_audio()
		return

	_received_remote_pcm_this_frame = false
	_speech_hold_seconds = maxf(_speech_hold_seconds - delta, 0.0)
	_loud_hold_seconds = maxf(_loud_hold_seconds - delta, 0.0)
	if _receive_stream_id != 0:
		_remote_packet_age_seconds += delta
	_drain_ordered_packets(delta)
	if _received_remote_pcm_this_frame:
		_voice_attack_gap_seconds = 0.0
	else:
		_advance_remote_voice_level(0.0, delta)
		_voice_attack_gap_seconds += delta
		if _voice_attack_gap_seconds >= VOICE_ATTACK_MAX_GAP_SECONDS:
			_speech_attack_seconds = 0.0
			_loud_attack_seconds = 0.0
	_publish_remote_voice_activity()
	_publish_remote_voice_level()
	_start_output_when_buffered()
	_pump_output_queue()

	if (
		_receive_stream_id != 0
		and _remote_packet_age_seconds >= REMOTE_PACKET_TIMEOUT_SECONDS
	):
		_suspend_remote_audio()


func _suspend_or_clear_remote_audio() -> void:
	if _transport_can_resume():
		_suspend_remote_audio()
	else:
		_clear_remote_audio()


func _suspend_remote_audio() -> void:
	# Steam may emit no packets during silence. Keep the stream/sequence epoch so
	# the same capture session can also resume after a local pause or mic test.
	_stop_output_player()
	_compressed_packets.clear()
	_pcm_queue.clear()
	_missing_packet_wait_seconds = 0.0
	_remote_packet_age_seconds = 0.0
	_last_decoded_frame_count = 0
	_recovering_from_underrun = false
	_reset_remote_voice_activity()


func _drain_ordered_packets(delta: float) -> void:
	if _next_receive_sequence < 0:
		return

	for _packet_index in range(MAX_PACKETS_DECODED_PER_FRAME):
		if _compressed_packets.has(_next_receive_sequence):
			var packet: Dictionary = _compressed_packets[_next_receive_sequence]
			_compressed_packets.erase(_next_receive_sequence)
			var payload: PackedByteArray = packet.get("payload", PackedByteArray())
			var frames := _decompress_voice_packet(payload)
			if not frames.is_empty():
				frames = _apply_pcm_gain(
					frames,
					float(packet.get("microphone_gain", 1.0))
				)
				_register_remote_voice_frames(frames)
			else:
				_reset_remote_voice_attack()
				if _last_decoded_frame_count > 0:
					frames = _make_silence(_last_decoded_frame_count)
			if not frames.is_empty():
				_last_decoded_frame_count = frames.size()
				_set_remote_pitch(int(packet.get("pitch_percent", 62)))
				_append_pcm_frames(frames)
			_next_receive_sequence += 1
			_missing_packet_wait_seconds = 0.0
			continue

		if _compressed_packets.is_empty():
			return
		var lowest_sequence := _get_lowest_pending_sequence()
		if lowest_sequence < _next_receive_sequence:
			_compressed_packets.erase(lowest_sequence)
			continue
		if lowest_sequence == _next_receive_sequence:
			continue

		_missing_packet_wait_seconds += delta
		if _missing_packet_wait_seconds < MISSING_PACKET_WAIT_SECONDS:
			return
		var missing_count := lowest_sequence - _next_receive_sequence
		_reset_remote_voice_attack()
		if _last_decoded_frame_count > 0:
			for _missing_index in range(mini(missing_count, MAX_GAP_SILENCE_PACKETS)):
				_append_pcm_frames(_make_silence(_last_decoded_frame_count))
		_next_receive_sequence = lowest_sequence
		_missing_packet_wait_seconds = 0.0


func _register_remote_voice_frames(frames: PackedVector2Array) -> void:
	_received_remote_pcm_this_frame = true
	var window_start := 0
	while window_start < frames.size():
		var window_end := mini(window_start + VOICE_LEVEL_WINDOW_FRAMES, frames.size())
		var window_count := window_end - window_start
		if (
			window_count < VOICE_LEVEL_MIN_WINDOW_FRAMES
			and frames.size() >= VOICE_LEVEL_MIN_WINDOW_FRAMES
		):
			break
		var levels := _measure_remote_voice_window(frames, window_start, window_end)
		_register_remote_voice_window(
			levels.x,
			levels.y,
			float(window_count) / float(VOICE_SAMPLE_RATE)
		)
		window_start = window_end


func _register_remote_voice_window(
	rms_db: float,
	peak_db: float,
	window_seconds: float
) -> void:
	_advance_remote_voice_level(
		_map_remote_voice_level(rms_db, peak_db),
		window_seconds
	)

	var speech_rms_threshold := (
		SPEECH_KEEP_RMS_DB
		if _remote_voice_activity != RemoteVoiceActivity.SILENT
		else SPEECH_START_RMS_DB
	)
	var speech_peak_threshold := (
		SPEECH_KEEP_PEAK_DB
		if _remote_voice_activity != RemoteVoiceActivity.SILENT
		else SPEECH_START_PEAK_DB
	)
	if rms_db >= speech_rms_threshold and peak_db >= speech_peak_threshold:
		if _remote_voice_activity != RemoteVoiceActivity.SILENT:
			_speech_hold_seconds = SPEECH_HOLD_SECONDS
			_speech_attack_seconds = 0.0
		else:
			_speech_attack_seconds += window_seconds
			if _speech_attack_seconds >= SPEECH_ATTACK_SECONDS:
				_speech_hold_seconds = SPEECH_HOLD_SECONDS
				_speech_attack_seconds = 0.0
	else:
		_speech_attack_seconds = 0.0

	var loud_rms_threshold := (
		LOUD_KEEP_RMS_DB
		if _remote_voice_activity == RemoteVoiceActivity.LOUD
		else LOUD_START_RMS_DB
	)
	var loud_peak_threshold := (
		LOUD_KEEP_PEAK_DB
		if _remote_voice_activity == RemoteVoiceActivity.LOUD
		else LOUD_START_PEAK_DB
	)
	var loud_hold_refreshed := false
	if rms_db >= loud_rms_threshold and peak_db >= loud_peak_threshold:
		if _remote_voice_activity == RemoteVoiceActivity.LOUD:
			_loud_hold_seconds = LOUD_HOLD_SECONDS
			_loud_attack_seconds = 0.0
			loud_hold_refreshed = true
		else:
			_loud_attack_seconds += window_seconds
			if _loud_attack_seconds >= LOUD_ATTACK_SECONDS:
				_loud_hold_seconds = LOUD_HOLD_SECONDS
				_loud_attack_seconds = 0.0
				loud_hold_refreshed = true
	else:
		_loud_attack_seconds = 0.0
	if loud_hold_refreshed:
		_speech_hold_seconds = maxf(_speech_hold_seconds, SPEECH_HOLD_SECONDS)


func _map_remote_voice_level(rms_db: float, peak_db: float) -> float:
	# Both values must rise together. This keeps short peak-only clicks from
	# making the portrait jump while preserving the perceived speech volume.
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


func _advance_remote_voice_level(target_level: float, duration: float) -> void:
	target_level = clampf(target_level, 0.0, 1.0)
	duration = maxf(duration, 0.0)
	if duration <= 0.0:
		return
	var tau := (
		VOICE_LEVEL_ATTACK_TAU_SECONDS
		if target_level > _remote_voice_level
		else VOICE_LEVEL_RELEASE_TAU_SECONDS
	)
	var blend := 1.0 - exp(-duration / maxf(tau, 0.001))
	_remote_voice_level = clampf(
		lerpf(_remote_voice_level, target_level, blend),
		0.0,
		1.0
	)
	if (
		target_level <= 0.0
		and _remote_voice_level < VOICE_LEVEL_ZERO_EPSILON
	):
		_remote_voice_level = 0.0


func _publish_remote_voice_level() -> void:
	var changed_enough := (
		absf(_remote_voice_level - _last_emitted_remote_voice_level)
		>= VOICE_LEVEL_SIGNAL_EPSILON
	)
	var reached_exact_zero := (
		_remote_voice_level == 0.0
		and _last_emitted_remote_voice_level != 0.0
	)
	if not changed_enough and not reached_exact_zero:
		return
	_last_emitted_remote_voice_level = _remote_voice_level
	remote_voice_level_changed.emit(_remote_voice_level)


func get_remote_voice_level() -> float:
	return _remote_voice_level


func _measure_remote_voice_levels(frames: PackedVector2Array) -> Vector2:
	if frames.is_empty():
		return Vector2(VOICE_LEVEL_FLOOR_DB, VOICE_LEVEL_FLOOR_DB)

	var max_window_rms := 0.0
	var peak := 0.0
	var window_start := 0
	while window_start < frames.size():
		var window_end := mini(window_start + VOICE_LEVEL_WINDOW_FRAMES, frames.size())
		var window_count := window_end - window_start
		if window_count >= VOICE_LEVEL_MIN_WINDOW_FRAMES or frames.size() < VOICE_LEVEL_MIN_WINDOW_FRAMES:
			var levels := _measure_remote_voice_window(frames, window_start, window_end)
			max_window_rms = maxf(max_window_rms, db_to_linear(levels.x))
			peak = maxf(peak, db_to_linear(levels.y))
		window_start = window_end

	return Vector2(
		clampf(linear_to_db(maxf(max_window_rms, 0.001)), VOICE_LEVEL_FLOOR_DB, 0.0),
		clampf(linear_to_db(maxf(peak, 0.001)), VOICE_LEVEL_FLOOR_DB, 0.0)
	)


func _measure_remote_voice_window(
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
		clampf(linear_to_db(maxf(rms, 0.001)), VOICE_LEVEL_FLOOR_DB, 0.0),
		clampf(linear_to_db(maxf(peak, 0.001)), VOICE_LEVEL_FLOOR_DB, 0.0)
	)


func _publish_remote_voice_activity() -> void:
	var next_activity := RemoteVoiceActivity.SILENT
	if _loud_hold_seconds > 0.0:
		next_activity = RemoteVoiceActivity.LOUD
	elif _speech_hold_seconds > 0.0:
		next_activity = RemoteVoiceActivity.SPEAKING
	_set_remote_voice_activity(next_activity)


func _set_remote_voice_activity(activity: int) -> void:
	activity = clampi(
		activity,
		RemoteVoiceActivity.SILENT,
		RemoteVoiceActivity.LOUD
	)
	if _remote_voice_activity == activity:
		return
	_remote_voice_activity = activity
	remote_voice_activity_changed.emit(_remote_voice_activity)


func _reset_remote_voice_activity() -> void:
	_reset_remote_voice_attack()
	_speech_hold_seconds = 0.0
	_loud_hold_seconds = 0.0
	_voice_attack_gap_seconds = 0.0
	_received_remote_pcm_this_frame = false
	_reset_remote_voice_level()
	_set_remote_voice_activity(RemoteVoiceActivity.SILENT)


func _reset_remote_voice_level() -> void:
	var should_emit_zero := (
		_remote_voice_level != 0.0
		or _last_emitted_remote_voice_level != 0.0
	)
	_remote_voice_level = 0.0
	if not should_emit_zero:
		return
	_last_emitted_remote_voice_level = 0.0
	remote_voice_level_changed.emit(0.0)


func _reset_remote_voice_attack() -> void:
	_speech_attack_seconds = 0.0
	_loud_attack_seconds = 0.0


func _get_lowest_pending_sequence() -> int:
	var lowest := 2_147_483_647
	for sequence_value: Variant in _compressed_packets.keys():
		lowest = mini(lowest, int(sequence_value))
	return lowest


func _decompress_voice_packet(payload: PackedByteArray) -> PackedVector2Array:
	if payload.is_empty() or not Engine.has_singleton("Steam") or not NetworkManager.steam_ready:
		return PackedVector2Array()
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
	return _pcm16_bytes_to_frames(pcm_bytes, valid_size)


func _pcm16_bytes_to_frames(
	pcm_bytes: PackedByteArray,
	valid_size: int
) -> PackedVector2Array:
	valid_size = mini(valid_size, pcm_bytes.size())
	valid_size -= valid_size % 2
	if valid_size <= 0:
		return PackedVector2Array()
	var frames := PackedVector2Array()
	frames.resize(valid_size >> 1)
	for frame_index in range(frames.size()):
		var sample := float(pcm_bytes.decode_s16(frame_index * 2)) / 32768.0
		frames[frame_index] = Vector2(sample, sample)
	return frames


func _apply_pcm_gain(
	frames: PackedVector2Array,
	microphone_gain: float
) -> PackedVector2Array:
	microphone_gain = clampf(
		microphone_gain, SettingsManager.MIN_MICROPHONE_GAIN, SettingsManager.MAX_MICROPHONE_GAIN
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


func _make_silence(frame_count: int) -> PackedVector2Array:
	var silence := PackedVector2Array()
	silence.resize(maxi(frame_count, 0))
	return silence


func _append_pcm_frames(frames: PackedVector2Array) -> void:
	if frames.is_empty():
		return
	_pcm_queue.append_array(frames)
	var max_total_frames := roundi(MAX_TOTAL_BUFFER_SECONDS * VOICE_SAMPLE_RATE)
	var max_queue_frames := maxi(
		max_total_frames - _get_generator_buffered_frame_count(),
		0
	)
	if _pcm_queue.size() > max_queue_frames:
		var recovery_frames := roundi(RECOVERY_BUFFER_SECONDS * VOICE_SAMPLE_RATE)
		var keep_frames := mini(max_queue_frames, recovery_frames)
		_pcm_queue = (
			PackedVector2Array()
			if keep_frames <= 0
			else _pcm_queue.slice(_pcm_queue.size() - keep_frames)
		)


func _get_generator_buffered_frame_count() -> int:
	if not _output_started or _output_playback == null:
		return 0
	var generator_capacity := roundi(GENERATOR_BUFFER_SECONDS * VOICE_SAMPLE_RATE)
	var available_frames := clampi(
		_output_playback.get_frames_available(),
		0,
		generator_capacity
	)
	return generator_capacity - available_frames


func _start_output_when_buffered() -> void:
	if _output_started or not _is_output_player_valid():
		return
	var target_buffer_seconds := (
		RECOVERY_BUFFER_SECONDS
		if _recovering_from_underrun
		else START_BUFFER_SECONDS
	)
	var start_frames := roundi(target_buffer_seconds * VOICE_SAMPLE_RATE)
	if _pcm_queue.size() < start_frames:
		return

	var stream := AudioStreamGenerator.new()
	stream.mix_rate = float(VOICE_SAMPLE_RATE)
	stream.buffer_length = GENERATOR_BUFFER_SECONDS
	_output_player.stop()
	_output_player.stream = stream
	_output_player.pitch_scale = 1.0
	_output_player.play()
	_output_playback = _output_player.get_stream_playback() as AudioStreamGeneratorPlayback
	_output_started = _output_playback != null
	if not _output_started:
		_output_player.stop()
		_output_player.stream = null
		return
	_last_playback_skip_count = _output_playback.get_skips()
	_recovering_from_underrun = false


func _pump_output_queue() -> void:
	if not _output_started or _output_playback == null:
		return
	var skip_count := _output_playback.get_skips()
	if skip_count > _last_playback_skip_count:
		_stop_output_player()
		_recovering_from_underrun = true
		return
	_last_playback_skip_count = skip_count
	if _pcm_queue.is_empty():
		return
	var available_frames := _output_playback.get_frames_available()
	if available_frames <= 0:
		return
	var push_count := mini(available_frames, _pcm_queue.size())
	var push_frames := _pcm_queue.slice(0, push_count)
	if _output_playback.push_buffer(push_frames):
		_pcm_queue = _pcm_queue.slice(push_count)


func _set_remote_pitch(pitch_percent: int) -> void:
	_active_remote_pitch_percent = clampi(pitch_percent, 35, 90)
	if _pitch_effect != null:
		_pitch_effect.pitch_scale = float(_active_remote_pitch_percent) / 100.0


func _create_output_player() -> void:
	if _anchor == null or not is_instance_valid(_anchor):
		return
	_output_player = AudioStreamPlayer3D.new()
	_output_player.name = "SatanVoiceOutput"
	_output_player.bus = VOICE_BUS_NAME
	_output_player.unit_size = 2.5
	_output_player.max_distance = 24.0
	_output_player.pitch_scale = 1.0
	_anchor.add_child(_output_player)


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


func _apply_voice_volume() -> void:
	var voice_bus := AudioServer.get_bus_index(VOICE_BUS_NAME)
	if voice_bus < 0:
		return
	var volume := clampf(SettingsManager.satan_voice_volume, 0.0, SettingsManager.MAX_SATAN_VOICE_VOLUME)
	AudioServer.set_bus_volume_db(voice_bus, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(voice_bus, volume <= 0.0)


func _clear_remote_audio() -> void:
	_retire_receive_stream(_receive_stream_id)
	_reset_remote_voice_activity()
	_stop_output_player()
	_compressed_packets.clear()
	_pcm_queue.clear()
	_receive_stream_id = 0
	_next_receive_sequence = -1
	_missing_packet_wait_seconds = 0.0
	_remote_packet_age_seconds = 0.0
	_last_decoded_frame_count = 0
	_output_started = false
	_recovering_from_underrun = false


func _stop_output_player() -> void:
	if _is_output_player_valid():
		_output_player.stop()
		_output_player.stream = null
	_output_playback = null
	_output_started = false
	_last_playback_skip_count = 0


func _stop_and_clear() -> void:
	_stop_capture()
	_clear_remote_audio()


func _is_output_player_valid() -> bool:
	return _output_player != null and is_instance_valid(_output_player)


func _exit_tree() -> void:
	_stop_and_clear()
