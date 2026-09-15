extends Node
class_name SaveManager

## Owns profile paths before any progression autoload reads or recovers a save.
## Settings, diagnostics and exported art deliberately use their global paths.
signal slots_changed

const SLOT_COUNT := 3
const SAVE_ROOT := "user://saves"
const LEGACY_ROOT := "user://"
const REGISTRY_PATH := "user://save_slots.cfg"
const PROFILE_FILES: Array[String] = ["collection.json", "battle_deck.cfg", "card_upgrades.cfg", "currency.cfg"]
const MANAGER_NAMES: Array[String] = ["CollectionManager", "CardUpgradeManager", "DeckManager", "GameCurrency"]

var active_slot: int = 1
var storage_error: Error = OK
var _started_slots: Array[int] = []
var _switching := false


func _ready() -> void:
	storage_error = _initialize_storage()
	if storage_error != OK:
		push_error("Could not initialize save slots: " + error_string(storage_error))


func get_slot_directory(slot: int) -> String:
	return SAVE_ROOT.path_join("slot_%d" % slot) if _valid_slot(slot) else ""


func get_save_path(file_name: String) -> String:
	assert(file_name in PROFILE_FILES, "Unknown profile save file")
	return get_slot_directory(active_slot).path_join(file_name)


func _valid_slot(slot: int) -> bool:
	return slot >= 1 and slot <= SLOT_COUNT


func _initialize_storage() -> Error:
	var registry := ConfigFile.new()
	var registry_error := registry.load(REGISTRY_PATH)
	if registry_error != OK and registry_error != ERR_FILE_NOT_FOUND:
		return registry_error
	active_slot = clampi(int(registry.get_value("slots", "active", 1)), 1, SLOT_COUNT)
	var started: Variant = registry.get_value("slots", "started", [])
	_started_slots.clear()
	if started is Array or started is PackedInt32Array or started is PackedInt64Array:
		for slot: Variant in started:
			if _valid_slot(int(slot)) and not _started_slots.has(int(slot)):
				_started_slots.append(int(slot))
	for slot in range(1, SLOT_COUNT + 1):
		var error := DirAccess.make_dir_recursive_absolute(get_slot_directory(slot))
		if error != OK:
			return error
	if not bool(registry.get_value("slots", "legacy_imported", false)):
		# Copy, never move, the old single profile. Missing destination files can
		# safely resume an interrupted import; existing saves are never replaced.
		for file_name in PROFILE_FILES:
			var source := LEGACY_ROOT.path_join(file_name)
			if not FileAccess.file_exists(source):
				continue
			var destination := get_slot_directory(1).path_join(file_name)
			if not FileAccess.file_exists(destination):
				var temporary := destination + ".importing"
				var error := DirAccess.copy_absolute(source, temporary)
				if error == OK:
					error = DirAccess.rename_absolute(temporary, destination)
				if error != OK:
					return error
			if not _started_slots.has(1):
				_started_slots.append(1)
		return _save_registry(active_slot, _started_slots)
	return OK


func _save_registry(slot: int, started: Array[int]) -> Error:
	var registry := ConfigFile.new()
	registry.set_value("slots", "active", slot)
	registry.set_value("slots", "started", started)
	registry.set_value("slots", "legacy_imported", true)
	var temporary := REGISTRY_PATH + ".tmp"
	var error := registry.save(temporary)
	if error == OK:
		error = DirAccess.rename_absolute(temporary, REGISTRY_PATH)
	return error


func get_slot_summary(slot: int) -> Dictionary:
	var summary := {"exists": false, "level": 1, "xp": 0, "coins": 20.0, "card_count": 0}
	if not _valid_slot(slot):
		return summary
	var directory := get_slot_directory(slot)
	summary["exists"] = _started_slots.has(slot)
	var currency := ConfigFile.new()
	if currency.load(directory.path_join("currency.cfg")) == OK:
		summary["level"] = maxi(int(currency.get_value("progression", "level", 1)), 1)
		summary["xp"] = maxi(int(currency.get_value("progression", "xp", 0)), 0)
		summary["coins"] = float(currency.get_value("currency", "coin_cents", 2000)) / 100.0 if currency.has_section_key("currency", "coin_cents") else float(currency.get_value("currency", "coins", 20.0))
		if int(summary["level"]) > 1 or int(summary["xp"]) > 0 or not is_equal_approx(float(summary["coins"]), 20.0):
			summary["exists"] = true
	var path := directory.path_join("collection.json")
	if FileAccess.file_exists(path):
		var collection: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if collection is Dictionary:
			var cards: Variant = collection.get("cards", {})
			if cards is Dictionary:
				for count: Variant in cards.values():
					summary["card_count"] += maxi(int(count), 0)
			if int(summary["card_count"]) > 0:
				summary["exists"] = true
	return summary


func _can_change_profile() -> bool:
	if _switching or storage_error != OK:
		return false
	var network := get_node_or_null("/root/NetworkManager")
	if network != null and network.has_active_session():
		return false
	if network != null:
		if network.has_method("is_lobby_operation_pending") and network.is_lobby_operation_pending():
			return false
		if network.has_method("is_match_in_progress") and network.is_match_in_progress():
			return false
	# Old room/pack/slot-machine exit callbacks must finish before paths change.
	# Test harnesses outside scenes/ can exercise the same public API in isolation.
	var scene := get_tree().current_scene
	if scene != null and scene.scene_file_path.begins_with("res://scenes/"):
		return scene.scene_file_path == "res://scenes/main/MainMenu.tscn"
	return true


func _validate_slot(slot: int) -> Error:
	for file_name in PROFILE_FILES:
		var path := get_slot_directory(slot).path_join(file_name)
		if not FileAccess.file_exists(path):
			continue
		if file_name.ends_with(".json"):
			var file := FileAccess.open(path, FileAccess.READ)
			if file == null:
				return FileAccess.get_open_error()
			var content: Variant = JSON.parse_string(file.get_as_text())
			if not content is Dictionary:
				return ERR_FILE_CORRUPT
		else:
			var config := ConfigFile.new()
			var error := config.load(path)
			if error != OK:
				return error
	return OK


func _save_current_profile() -> Error:
	if not get_node("/root/CollectionManager").save_collection():
		return ERR_CANT_CREATE
	if not get_node("/root/CardUpgradeManager").save_upgrades():
		return ERR_CANT_CREATE
	if not get_node("/root/DeckManager").save_deck():
		return ERR_CANT_CREATE
	if not get_node("/root/GameCurrency").save():
		return ERR_CANT_CREATE
	return OK


func select_slot(slot: int) -> Error:
	if not _valid_slot(slot):
		return ERR_INVALID_PARAMETER
	if not _can_change_profile():
		return storage_error if storage_error != OK else ERR_BUSY
	var error := _validate_slot(slot)
	if error != OK:
		return error
	_switching = true
	error = _save_current_profile()
	if error != OK:
		_switching = false
		return error
	var started := _started_slots.duplicate()
	if not started.has(slot):
		started.append(slot)
	error = _save_registry(slot, started)
	if error != OK:
		_switching = false
		return error
	_started_slots = started
	if slot != active_slot:
		active_slot = slot
		_reload_managers()
	slots_changed.emit()
	_switching = false
	return OK


func _reload_managers() -> void:
	var collection_manager := get_node("/root/CollectionManager")
	var changed_ids: Array[String] = []
	for id: Variant in collection_manager.get_owned_cards():
		changed_ids.append(str(id))
	var upgrade_manager := get_node("/root/CardUpgradeManager")
	for id: Variant in upgrade_manager.upgrades:
		if not changed_ids.has(str(id)):
			changed_ids.append(str(id))
	var previous_signal_blocks: Array[bool] = []
	for manager_name in MANAGER_NAMES:
		var manager := get_node("/root/" + manager_name)
		previous_signal_blocks.append(manager.is_blocking_signals())
		manager.set_block_signals(true)
		manager.clear_profile_state()
	# Every manager sees only the new profile, even during load migrations or
	# pending transaction recovery. Observers see one completed profile change.
	for manager_name in MANAGER_NAMES:
		get_node("/root/" + manager_name).reload_profile()
	for index in range(MANAGER_NAMES.size()):
		get_node("/root/" + MANAGER_NAMES[index]).set_block_signals(previous_signal_blocks[index])
	for id: Variant in collection_manager.get_owned_cards():
		if not changed_ids.has(str(id)):
			changed_ids.append(str(id))
	for id: Variant in upgrade_manager.upgrades:
		if not changed_ids.has(str(id)):
			changed_ids.append(str(id))
	collection_manager.collection_changed.emit(changed_ids)
	for id in changed_ids:
		upgrade_manager.upgrades_changed.emit(id)
	var wallet := get_node("/root/GameCurrency")
	wallet.coins_changed.emit(wallet.get_coins())
	wallet.progression_changed.emit(wallet.get_level(), wallet.get_xp(), wallet.get_xp_required())


func reset_slot(slot: int) -> Error:
	if not _valid_slot(slot):
		return ERR_INVALID_PARAMETER
	if not _can_change_profile():
		return storage_error if storage_error != OK else ERR_BUSY
	_switching = true
	var directory := get_slot_directory(slot)
	var backup := directory + ".reset_%d" % Time.get_ticks_usec()
	# Swap out the complete profile, so a failure cannot delete only part of it.
	var error := DirAccess.rename_absolute(directory, backup)
	if error != OK:
		_switching = false
		return error
	error = DirAccess.make_dir_absolute(directory)
	var started := _started_slots.duplicate()
	started.erase(slot)
	if error == OK:
		error = _save_registry(active_slot, started)
	if error != OK:
		DirAccess.remove_absolute(directory)
		DirAccess.rename_absolute(backup, directory)
		_switching = false
		return error
	_started_slots = started
	if slot == active_slot:
		_reload_managers()
	# Only fixed, known profile filenames are removed; unrelated data is never
	# traversed. A failed cleanup leaves the retired backup available for recovery.
	for file_name in PROFILE_FILES:
		for suffix in ["", ".tmp", ".importing", ".fusion.tmp"]:
			var path := backup.path_join(file_name + suffix)
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(backup)
	slots_changed.emit()
	_switching = false
	return OK
