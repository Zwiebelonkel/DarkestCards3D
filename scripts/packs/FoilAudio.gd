extends Node
class_name FoilAudio

## Short, dry foil sounds driven by actual peel movement. Both arguments to
## set_motion are normalized (0..1); callers should update them while dragging.
## No AudioServer settings are changed: the existing SFX bus controls volume.
const SAMPLE_RATE := 22050
const VOICE_COUNT := 3
const MOTION_TIMEOUT := 0.12
const MIN_MOTION := 0.025

static var _crinkle_streams: Array[AudioStreamWAV] = []
static var _tear_stream: AudioStreamWAV

var _voices: Array[AudioStreamPlayer] = []
var _tear_player: AudioStreamPlayer
var _target_speed := 0.0
var _target_tension := 0.0
var _smooth_speed := 0.0
var _smooth_tension := 0.0
var _motion_age := MOTION_TIMEOUT
var _next_crinkle := 0.0
var _voice_index := 0
var _crinkle_index := 0
var _tear_cooldown := 0.0


func _ready() -> void:
	_prepare_streams()
	for index in range(VOICE_COUNT):
		var player := _make_player("FoilCrinkle%d" % index)
		_voices.append(player)
	_tear_player = _make_player("FoilTear")
	set_process(false)


func _make_player(player_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.bus = &"SFX"
	player.volume_db = -24.0
	add_child(player)
	return player


func set_motion(speed: float, tension: float) -> void:
	_target_speed = clampf(speed, 0.0, 1.0) if is_finite(speed) else 0.0
	if _target_speed < MIN_MOTION:
		_target_speed = 0.0
	_target_tension = clampf(tension, 0.0, 1.0) if is_finite(tension) else 0.0
	_motion_age = 0.0
	if _target_speed >= MIN_MOTION or _smooth_speed >= MIN_MOTION:
		set_process(true)


func play_tear() -> void:
	# A held mouse button or repeated snap notification must not stack tears.
	if not is_instance_valid(_tear_player) or _tear_cooldown > 0.0:
		return
	_silence_motion()
	_tear_player.stream = _tear_stream
	_tear_player.pitch_scale = 1.0
	_tear_player.volume_db = -12.0
	_tear_player.play()
	_tear_cooldown = 0.24
	set_process(true)


func stop() -> void:
	_silence_motion()
	if is_instance_valid(_tear_player):
		_tear_player.stop()
	_tear_cooldown = 0.0
	set_process(false)


func _silence_motion() -> void:
	_target_speed = 0.0
	_target_tension = 0.0
	_smooth_speed = 0.0
	_smooth_tension = 0.0
	_motion_age = MOTION_TIMEOUT
	_next_crinkle = 0.0
	for player in _voices:
		player.stop()


func _process(delta: float) -> void:
	_motion_age += delta
	_tear_cooldown = maxf(0.0, _tear_cooldown - delta)
	if _motion_age >= MOTION_TIMEOUT:
		_target_speed = 0.0
		_target_tension = 0.0
	var smoothing := 1.0 - exp(-delta * 24.0)
	_smooth_speed = lerpf(_smooth_speed, _target_speed, smoothing)
	_smooth_tension = lerpf(_smooth_tension, _target_tension, smoothing)
	_next_crinkle -= delta
	# Tension alone is silent. Emit only while a fresh, moving pull is present.
	if _target_speed >= MIN_MOTION and _smooth_speed >= MIN_MOTION:
		if _next_crinkle <= 0.0 and _tear_cooldown <= 0.0:
			_play_crinkle()
			_next_crinkle = lerpf(0.17, 0.055, _smooth_speed) * lerpf(1.0, 0.88, _smooth_tension)
	else:
		for player in _voices:
			if player.playing:
				player.volume_db = move_toward(player.volume_db, -60.0, delta * 360.0)
				if player.volume_db <= -55.0:
					player.stop()
	if _target_speed < MIN_MOTION and _smooth_speed < 0.002 and _tear_cooldown <= 0.0:
		var any_playing := is_instance_valid(_tear_player) and _tear_player.playing
		for player in _voices:
			any_playing = any_playing or player.playing
		if not any_playing:
			set_process(false)


func _play_crinkle() -> void:
	if _voices.is_empty() or _crinkle_streams.is_empty():
		return
	var player := _voices[_voice_index % _voices.size()]
	player.stream = _crinkle_streams[_crinkle_index % _crinkle_streams.size()]
	# Deterministic variation avoids a mechanical loop without using global RNG.
	var pitch_variation := float((_crinkle_index * 3) % 5 - 2) * 0.018
	player.pitch_scale = lerpf(0.92, 1.13, _smooth_tension) + pitch_variation
	player.volume_db = -23.0 + _smooth_speed * 8.0 + _smooth_tension * 2.0
	player.play()
	_voice_index += 1
	_crinkle_index += 1


static func _prepare_streams() -> void:
	if not _crinkle_streams.is_empty():
		return
	for index in range(5):
		_crinkle_streams.append(_synthesize_crinkle(0.085 + index * 0.008, 12 + index, 4103 + index * 97))
	_tear_stream = _synthesize_crinkle(0.23, 46, 91733)


static func _synthesize_crinkle(duration: float, grains: int, seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var count := int(duration * SAMPLE_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	# Discrete micro-bursts are separated by quiet gaps, unlike continuous hiss.
	for _grain in range(grains):
		var length := rng.randi_range(42, 190)
		var start := rng.randi_range(1, count - length - 1)
		var strength := rng.randf_range(0.18, 0.65) * lerpf(1.0, 0.55, float(start) / count)
		for index in range(length):
			var phase := float(index) / (length - 1)
			var envelope := sin(phase * PI)
			samples[start + index] += rng.randf_range(-1.0, 1.0) * envelope * envelope * strength
	var low := 0.0
	var softened := 0.0
	var peak := 0.001
	for index in range(count):
		var raw := float(samples[index])
		# Remove boomy low frequencies, then soften the brittle high edge.
		low = lerpf(low, raw, 0.16)
		softened = lerpf(softened, raw - low, 0.58)
		var edge := minf(1.0, minf(float(index) / 80.0, float(count - 1 - index) / 100.0))
		samples[index] = softened * maxf(edge, 0.0)
		peak = maxf(peak, absf(samples[index]))
	var pcm := PackedByteArray()
	pcm.resize(count * 2)
	var gain := 0.7 / peak
	for index in range(count):
		var sample := clampi(int(samples[index] * gain * 32767.0), -32768, 32767)
		pcm[index * 2] = sample & 255
		pcm[index * 2 + 1] = (sample >> 8) & 255
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = pcm
	return stream
