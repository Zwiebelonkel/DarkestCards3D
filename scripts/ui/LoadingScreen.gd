extends Control

## Standalone transition scene. Main is requested only after this screen draws.
## See https://docs.godotengine.org/en/4.4/tutorials/io/background_loading.html
const MAIN_MENU_SCENE := "res://scenes/main/MainMenu.tscn"

@export_file("*.tscn") var target_scene_path := "res://scenes/main/Main.tscn"
@export_range(0.0, 3.0, 0.05) var minimum_display_seconds := 0.6
@export_range(1.0, 30.0, 1.0) var laugh_fps := 12.0

@onready var portrait: TextureRect = %Satan
@onready var progress_bar: ProgressBar = %LoadingBar
@onready var laugh: AudioStreamPlayer = $Laugh

var _elapsed := 0.0
var _animation_seconds := 0.0
var _request_started := false
var _transition_queued := false
var _target_progress := 0.0
var _loaded_scene: PackedScene
var _portrait_atlas: AtlasTexture
var _voice_random := RandomNumberGenerator.new()


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_portrait_atlas = portrait.texture.duplicate() as AtlasTexture
	portrait.texture = _portrait_atlas
	_voice_random.randomize()
	laugh.finished.connect(_play_laugh)
	_begin_loading_after_draw()


func _begin_loading_after_draw() -> void:
	# process_frame fires before rendering. Two frame boundaries give the
	# black screen and portrait one full frame before requesting resources.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_play_laugh()
	var error := ResourceLoader.load_threaded_request(target_scene_path, "PackedScene")
	if error != OK:
		_loading_failed(error)
		return
	_request_started = true


func _process(delta: float) -> void:
	_elapsed += delta
	_animation_seconds += delta
	if _portrait_atlas != null:
		var frame := floori(_animation_seconds * laugh_fps) % 2
		_portrait_atlas.region = Rect2(frame * 64, 0, 64, 64)
	if not _request_started or _transition_queued:
		return
	if _loaded_scene == null:
		_poll_loading()
	progress_bar.value = move_toward(progress_bar.value, _target_progress, delta * 2.5)
	if _loaded_scene != null and _elapsed >= minimum_display_seconds and progress_bar.value >= 1.0:
		_transition_queued = true
		_finish_loading.call_deferred()


func _poll_loading() -> void:
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(target_scene_path, progress)
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if not progress.is_empty():
				_target_progress = maxf(_target_progress, clampf(float(progress[0]), 0.0, 1.0) * 0.95)
		ResourceLoader.THREAD_LOAD_LOADED:
			# Calling get before LOADED would block the animation's main thread.
			_loaded_scene = ResourceLoader.load_threaded_get(target_scene_path) as PackedScene
			if _loaded_scene == null:
				_loading_failed(ERR_INVALID_DATA)
				return
			_target_progress = 1.0
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_loading_failed(ERR_CANT_OPEN)


func _finish_loading() -> void:
	# Show a completed bar before scene instantiation and _ready run on the
	# main thread. The actual scene switch is deferred outside input/process.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var error := get_tree().change_scene_to_packed(_loaded_scene)
	if error != OK:
		_loading_failed(error)


func _play_laugh() -> void:
	if not is_inside_tree() or _transition_queued:
		return
	laugh.pitch_scale = _voice_random.randf_range(0.72, 0.88)
	laugh.play()


func _loading_failed(error: Error) -> void:
	_request_started = false
	_transition_queued = true
	laugh.stop()
	push_error("Could not load scene %s: %s" % [target_scene_path, error_string(error)])
	get_tree().change_scene_to_file.call_deferred(MAIN_MENU_SCENE)
