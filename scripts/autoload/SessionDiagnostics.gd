extends Node

## Preload this script and call record() from lifecycle boundaries. Static lazy
## initialization also works in test fixtures that replace other autoloads.
## Only symbolic labels, booleans and counters belong here, never RPC payloads.
const LOG_DIRECTORY := "user://logs/sessions"
const MAX_LOG_FILES := 8
const MAX_LOG_BYTES := 524288
const MAX_STATE_FIELDS := 32
const STRING_FIELDS := [
	"state", "stage", "role", "mode", "status", "reason", "operation", "source",
	"phase", "result", "transport", "engine_version", "platform", "build",
	"renderer", "driver", "feature", "plugin_version", "steam_version",
	"engine_hash", "plugin_hash", "steam_binary_hash", "godotsteam_version", "library", "sha256", "version",
	"error_kind", "cause", "previous_status", "previous_event", "previous_session",
]
const VALUE_FIELDS := [
	"online", "host", "spectator", "connected", "exiting", "started", "finished",
	"success", "in_tree", "paused", "pending", "running", "elapsed", "duration",
	"error_code", "exit_code", "result_code", "index", "is_debug_build",
	"generation", "current_generation", "leaving", "active_lobby", "match_in_progress",
	"result", "response", "error", "status", "old_state", "connection_state", "end_reason",
	"cancelled", "original_host_changed", "chat_state", "debug_build",
]

static var _started := false
static var _ended := false
static var _io_warning_reported := false
static var _file: FileAccess
static var _session_id := ""
static var _log_path := ""
static var _marker_path := ""
static var _directory := ""
static var _part := 0
static var _started_ticks := 0
static var _marker_status := "running"
static var _last_event := "runtime.start"
static var _last_fingerprint := ""
static var _last_write_ticks := -1000
static var _suppressed_repeats := 0
static var _prose_redactors: Array[RegEx] = []


func _enter_tree() -> void:
	_ensure_started()
	set_process(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		note_shutdown("window_close_request")


func _exit_tree() -> void:
	if not _started or _ended:
		return
	# This is an observed teardown stage, not proof of successful process exit.
	# Native Steam/renderer destruction can still crash after this callback.
	_marker_status = "exit_tree_reached"
	record("runtime.exit_tree", {"status": _marker_status})
	if _file != null:
		_file.flush()
		_file.close()
		_file = null
	_ended = true


static func record(event: String, state: Dictionary = {}) -> void:
	if not _ensure_started() or _file == null:
		return
	var event_name := _token(event, 96)
	if event_name.is_empty():
		event_name = "diagnostics.invalid_event"
	var safe_state := _sanitize_state(state)
	var fingerprint := event_name + JSON.stringify(safe_state)
	var now := Time.get_ticks_msec()
	if fingerprint == _last_fingerprint and now - _last_write_ticks < 1000:
		_suppressed_repeats += 1
		return
	if _suppressed_repeats > 0:
		safe_state["suppressed_repeats"] = _suppressed_repeats
		_suppressed_repeats = 0
	_last_fingerprint = fingerprint
	_last_write_ticks = now
	_append_line(event_name, safe_state)


static func note_shutdown(reason: String = "requested") -> void:
	if not _ensure_started():
		return
	_marker_status = "shutdown_requested"
	record("runtime.shutdown_requested", {"reason": reason, "status": _marker_status})


static func get_log_path() -> String:
	_ensure_started()
	return _log_path


static func _ensure_started() -> bool:
	if _ended or Engine.is_editor_hint():
		return false
	if _started:
		return _file != null
	_started = true
	_started_ticks = Time.get_ticks_msec()
	_directory = ProjectSettings.globalize_path(LOG_DIRECTORY)
	var directory_error := DirAccess.make_dir_recursive_absolute(_directory)
	if directory_error != OK:
		_report_io_failure(directory_error)
		return false
	var unix_msec := int(Time.get_unix_time_from_system() * 1000.0)
	_session_id = "%d_%d_%d" % [unix_msec, OS.get_process_id(), Time.get_ticks_usec()]
	_marker_path = _directory.path_join("session-%s.state.json" % _session_id)
	var previous := _read_previous_marker()
	if not _open_segment():
		return false
	var version := Engine.get_version_info()
	_append_line("runtime.start", {
		"engine_version": "%d.%d.%d-%s.%s" % [
			int(version.get("major", 0)), int(version.get("minor", 0)), int(version.get("patch", 0)),
			_token(str(version.get("status", "unknown")), 24), _token(str(version.get("build", "unknown")), 24),
		],
		"engine_hash": _token(str(version.get("hash", "unknown")), 64),
		"platform": OS.get_name(),
		"build": "debug" if OS.is_debug_build() else "release",
		"is_debug_build": OS.is_debug_build(),
		"has_editor_feature": OS.has_feature("editor"),
		"has_template_feature": OS.has_feature("template"),
		"has_release_feature": OS.has_feature("release"),
		"has_debug_feature": OS.has_feature("debug"),
	})
	if not previous.is_empty():
		var previous_status := _token(str(previous.get("status", "unknown")), 48)
		# No shutdown marker is treated as verified clean: an engine/native crash
		# during teardown must remain distinguishable from an ordinary tree exit.
		var previous_event := "runtime.previous_run_interrupted"
		if previous_status in ["shutdown_requested", "exit_tree_reached"]:
			previous_event = "runtime.previous_shutdown_unverified"
		_append_line(previous_event, {
			"previous_status": previous_status,
			"previous_event": _token(str(previous.get("last_event", "unknown")), 96),
			"previous_session": _token(str(previous.get("session", "unknown")), 96),
		})
	_prune_logs()
	return true


static func _open_segment() -> bool:
	_log_path = _directory.path_join("session-%s-%03d.jsonl" % [_session_id, _part])
	_file = FileAccess.open(_log_path, FileAccess.WRITE)
	if _file == null:
		_report_io_failure(FileAccess.get_open_error())
		return false
	return true


static func _append_line(event: String, safe_state: Dictionary) -> void:
	if _file == null:
		return
	var row := {
		"timestamp_utc": Time.get_datetime_string_from_system(true, true) + "Z",
		"session": _session_id,
		"elapsed_ms": Time.get_ticks_msec() - _started_ticks,
		"event": event,
		"state": safe_state,
	}
	var line := JSON.stringify(row)
	if _file.get_position() + line.to_utf8_buffer().size() + 1 > MAX_LOG_BYTES:
		_file.flush()
		_file.close()
		_part += 1
		if not _open_segment():
			return
		_prune_logs()
	_file.store_line(line)
	_file.flush()
	if _file.get_error() != OK:
		_report_io_failure(_file.get_error())
	_last_event = event
	_write_marker()


static func _write_marker() -> void:
	var temporary := _marker_path + ".tmp"
	var marker := FileAccess.open(temporary, FileAccess.WRITE)
	if marker == null:
		_report_io_failure(FileAccess.get_open_error())
		return
	marker.store_string(JSON.stringify({
		"session": _session_id,
		"process_id": OS.get_process_id(),
		"status": _marker_status,
		"last_event": _last_event,
		"timestamp_utc": Time.get_datetime_string_from_system(true, true) + "Z",
	}))
	marker.flush()
	var write_error := marker.get_error()
	marker.close()
	if write_error != OK:
		_report_io_failure(write_error)
		return
	# Replace after a complete flushed write; leave the prior marker intact on
	# failure. The valid temporary file is also recoverable at the next startup.
	var rename_error := DirAccess.rename_absolute(temporary, _marker_path)
	if rename_error != OK:
		_report_io_failure(rename_error)


static func _read_previous_marker() -> Dictionary:
	var names: Array[String] = []
	for name in DirAccess.get_files_at(_directory):
		if name.begins_with("session-") and (name.ends_with(".state.json") or name.ends_with(".state.json.tmp")):
			names.append(name)
	names.sort()
	names.reverse()
	for name in names:
		var marker_file := FileAccess.open(_directory.path_join(name), FileAccess.READ)
		if marker_file == null or marker_file.get_length() > 8192:
			continue
		var value: Variant = JSON.parse_string(marker_file.get_as_text())
		marker_file.close()
		if not value is Dictionary:
			continue
		var marker: Dictionary = value
		var process_id := int(marker.get("process_id", 0))
		if process_id > 0 and process_id != OS.get_process_id() and OS.is_process_running(process_id):
			continue
		return marker
	return {}


static func _prune_logs() -> void:
	var files: Array[String] = []
	for name in DirAccess.get_files_at(_directory):
		if name.begins_with("session-") and name.ends_with(".jsonl"):
			files.append(name)
	files.sort()
	var remaining := files.size()
	for name in files:
		if remaining <= MAX_LOG_FILES:
			break
		var path := _directory.path_join(name)
		if path == _log_path or _belongs_to_live_foreign_process(name):
			continue
		if DirAccess.remove_absolute(path) == OK:
			remaining -= 1
	# Keep markers while their corresponding retained logs exist. A previous
	# marker is never overwritten by a new session; its final stage stays intact.
	var retained := DirAccess.get_files_at(_directory)
	for name in retained:
		if not name.begins_with("session-") or not (name.ends_with(".state.json") or name.ends_with(".state.json.tmp")):
			continue
		var path := _directory.path_join(name)
		if path == _marker_path or path == _marker_path + ".tmp" or _belongs_to_live_foreign_process(name):
			continue
		var prefix := name.get_slice(".state.json", 0) + "-"
		var has_log := false
		for candidate in retained:
			if candidate.begins_with(prefix) and candidate.ends_with(".jsonl"):
				has_log = true
				break
		if not has_log:
			DirAccess.remove_absolute(path)


static func _belongs_to_live_foreign_process(file_name: String) -> bool:
	var process_text := file_name.get_slice("_", 1)
	if not process_text.is_valid_int():
		return false
	var process_id := int(process_text)
	return process_id > 0 and process_id != OS.get_process_id() and OS.is_process_running(process_id)


static func _sanitize_state(state: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var omitted := 0
	for raw_key: Variant in state:
		if result.size() >= MAX_STATE_FIELDS:
			omitted += 1
			continue
		var key := str(raw_key).to_lower()
		if _token(key, 48) != key or key.ends_with("_id") or key in ["id", "name", "text", "payload", "data", "token", "secret", "password"]:
			omitted += 1
			continue
		var value: Variant = state[raw_key]
		if typeof(value) in [TYPE_STRING, TYPE_STRING_NAME] and key in ["event", "message"]:
			# These two fields are reserved for application-authored stage labels
			# and error messages. Never pass chat/persona strings as log messages.
			result[key] = _sanitize_prose(str(value), 160 if key == "event" else 256)
		elif typeof(value) in [TYPE_STRING, TYPE_STRING_NAME] and key in STRING_FIELDS:
			var label := _token(str(value), 96)
			if not label.is_empty():
				result[key] = label
			else:
				omitted += 1
		elif typeof(value) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT] and _is_counter_key(key):
			if typeof(value) != TYPE_FLOAT or is_finite(float(value)):
				result[key] = value
			else:
				omitted += 1
		else:
			omitted += 1
	if omitted > 0:
		result["omitted_fields"] = omitted
	return result


static func _is_counter_key(key: String) -> bool:
	if key in VALUE_FIELDS or key.begins_with("is_") or key.begins_with("has_"):
		return true
	for suffix in ["_count", "_size", "_sequence", "_generation", "_ms", "_msec", "_usec", "_seconds", "_frames", "_active", "_ready", "_pending", "_valid", "_visible", "_enabled"]:
		if key.ends_with(suffix):
			return true
	return false


static func _token(value: String, limit: int) -> String:
	if value.is_empty() or value.length() > limit:
		return ""
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code in [45, 46, 58, 95]):
			return ""
	return value


static func _sanitize_prose(value: String, limit: int) -> String:
	if _prose_redactors.is_empty():
		for pattern in [
			"(?i)\\b(?:https?|steam)://\\S+",
			"[A-Za-z]:[\\\\/][^\\s,;]+",
			"\\b[0-9]{1,3}(?:\\.[0-9]{1,3}){3}(?::[0-9]+)?\\b",
			"\\b[0-9]{9,}\\b",
			"(?i)\\b(?:token|password|secret|authorization)\\s*[:=]\\s*\\S+",
			"(?i)\\b(?:persona(?:_name)?|user(?:name)?|player(?:_name)?|benutzer(?:name)?|spieler(?:name)?|name)\\s*[:=]\\s*(?:\"[^\"]*\"|'[^']*'|[^,;]+)",
		]:
			var regex := RegEx.new()
			if regex.compile(pattern) == OK:
				_prose_redactors.append(regex)
	var result := ""
	for index in range(mini(value.length(), 1024)):
		var code := value.unicode_at(index)
		result += value.substr(index, 1) if code >= 32 and code != 127 else " "
	for regex in _prose_redactors:
		result = regex.sub(result, "[redacted]", true)
	return result.strip_edges().left(limit)


static func _report_io_failure(error: int) -> void:
	if _io_warning_reported:
		return
	_io_warning_reported = true
	push_warning("Session diagnostics could not persist data (error %d)." % error)
