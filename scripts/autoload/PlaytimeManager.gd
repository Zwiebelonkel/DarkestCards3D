extends Node
## Global running time, independent of scenes and save slots. Closed-game time
## is deliberately excluded; only the accumulated duration crosses restarts.
signal expired
signal timer_reset
## 2.5 * 60.0 * 60.0
const LIMIT_SECONDS := 30
const SAVE_INTERVAL := 5.0
const SAVE_PATH := "user://playtime.cfg"

var elapsed_seconds := 0.0
var encounter_completed := false
var storage_error: Error = OK
var _last_tick_usec := 0
var _unsaved_seconds := 0.0
var _expiry_emitted := false
var _generation := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_state()
	_last_tick_usec = Time.get_ticks_usec()
	_expiry_emitted = elapsed_seconds >= LIMIT_SECONDS


func _load_state() -> void:
	# Recover the newest valid checkpoint, including an interrupted atomic save.
	for path in [SAVE_PATH, SAVE_PATH + ".tmp", SAVE_PATH + ".bak"]:
		var config := ConfigFile.new()
		if config.load(path) != OK:
			continue
		var value: Variant = config.get_value("playtime", "elapsed_seconds", -1.0)
		if not (value is float or value is int) or not is_finite(float(value)) or float(value) < 0.0:
			continue
		var generation := maxi(int(config.get_value("playtime", "generation", 0)), 0)
		if generation < _generation:
			continue
		if generation > _generation:
			_generation = generation
			elapsed_seconds = 0.0
			encounter_completed = false
		elapsed_seconds = maxf(elapsed_seconds, float(value))
		encounter_completed = encounter_completed or bool(config.get_value("playtime", "encounter_completed", false))


func _sample_clock() -> void:
	var now := Time.get_ticks_usec()
	if _last_tick_usec == 0:
		_last_tick_usec = now
		return
	var seconds := maxf(float(now - _last_tick_usec) / 1000000.0, 0.0)
	_last_tick_usec = now
	elapsed_seconds += seconds
	_unsaved_seconds += seconds
	if not _expiry_emitted and elapsed_seconds >= LIMIT_SECONDS:
		_expiry_emitted = true
		expired.emit()


func _process(_delta: float) -> void:
	_sample_clock()
	if _unsaved_seconds >= SAVE_INTERVAL:
		flush()


func is_encounter_pending() -> bool:
	return elapsed_seconds >= LIMIT_SECONDS and not encounter_completed


func complete_encounter() -> Error:
	encounter_completed = true
	return flush()


func reset_timer() -> Error:
	# A new generation supersedes old completed backups, even if the process
	# stops between writing the temporary checkpoint and replacing the primary.
	_generation += 1
	elapsed_seconds = 0.0
	encounter_completed = false
	_expiry_emitted = false
	_unsaved_seconds = 0.0
	_last_tick_usec = Time.get_ticks_usec()
	var error := flush()
	timer_reset.emit()
	return error


func flush() -> Error:
	_sample_clock()
	var config := ConfigFile.new()
	config.set_value("playtime", "elapsed_seconds", elapsed_seconds)
	config.set_value("playtime", "encounter_completed", encounter_completed)
	config.set_value("playtime", "generation", _generation)
	storage_error = config.save(SAVE_PATH + ".tmp")
	if storage_error == OK and FileAccess.file_exists(SAVE_PATH):
		storage_error = DirAccess.copy_absolute(SAVE_PATH, SAVE_PATH + ".bak")
	if storage_error == OK:
		storage_error = DirAccess.rename_absolute(SAVE_PATH + ".tmp", SAVE_PATH)
	_unsaved_seconds = 0.0
	if storage_error != OK:
		push_warning("Could not save global playtime: " + error_string(storage_error))
	return storage_error


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		flush()


func _exit_tree() -> void:
	flush()
