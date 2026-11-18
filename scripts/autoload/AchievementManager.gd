extends Node

## Permanent Steam achievements, independent of the three save slots.
## API names must match the published Steamworks achievement definitions.
signal achievement_unlocked(achievement_id: String)
signal achievement_synced(achievement_id: String)

const SAVE_PATH := "user://achievements.cfg"
const RETRY_SECONDS := 30.0
const SATAN_PISS := "ACH_SATAN_PISS"
const SATAN_JUMPSCARE := "ACH_SATAN_JUMPSCARE"
const RARITY_ACHIEVEMENTS := {
	"common": "ACH_FIRST_COMMON",
	"uncommon": "ACH_FIRST_UNCOMMON",
	"rare": "ACH_FIRST_RARE",
	"epic": "ACH_FIRST_EPIC",
	"legendary": "ACH_FIRST_LEGENDARY",
	"mythic": "ACH_FIRST_MYTHIC",
	"exotic": "ACH_FIRST_EXOTIC",
	"secret": "ACH_FIRST_SECRET",
}
const ACHIEVEMENTS := {
	"ACH_FIRST_COMMON": {"name": "Nothing Special", "description": "Obtain your first Common card."},
	"ACH_FIRST_UNCOMMON": {"name": "A Little Uncommon", "description": "Obtain your first Uncommon card."},
	"ACH_FIRST_RARE": {"name": "A Rare Find", "description": "Obtain your first Rare card."},
	"ACH_FIRST_EPIC": {"name": "An Epic Find", "description": "Obtain your first Epic card."},
	"ACH_FIRST_LEGENDARY": {"name": "A Living Legend", "description": "Obtain your first Legendary card."},
	"ACH_FIRST_MYTHIC": {"name": "Beyond Myth", "description": "Obtain your first Mythic card."},
	"ACH_FIRST_EXOTIC": {"name": "Something Exotic", "description": "Obtain your first Exotic card."},
	"ACH_FIRST_SECRET": {"name": "A Well-Kept Secret", "description": "Obtain your first Secret card."},
	"ACH_SATAN_PISS": {"name": "Pissed Off", "description": "Make Satan start his stream by clicking him twice."},
	"ACH_SATAN_JUMPSCARE": {"name": "Too Close for Comfort", "description": "Trigger Satan's jumpscare."},
}

var _unlocked: Dictionary = {}
var save_path := SAVE_PATH
var _pending: Dictionary = {}
var _inflight: Array[String] = []
var _steam: Object
var _steam_connected := false
var _retry_elapsed := 0.0
var _save_dirty := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_state()
	CollectionManager.collection_changed.connect(_on_collection_changed)
	NetworkManager.steam_status_changed.connect(_on_steam_status_changed)
	if Engine.has_singleton("Steam"):
		_steam = Engine.get_singleton("Steam")
	# GodotSteam 4.22 loads stats at initialization; requestCurrentStats was removed.
	_connect_steam()
	_on_collection_changed(CollectionManager.get_discovered_card_ids())


func _process(delta: float) -> void:
	_retry_elapsed += delta
	if _retry_elapsed < RETRY_SECONDS:
		return
	_retry_elapsed = 0.0
	if _save_dirty:
		_save_state()
	if not _steam_connected:
		_connect_steam()
	else:
		# Missing callbacks and failed stores keep their pending unlocks for retry.
		_inflight.clear()
		sync_pending()


func is_unlocked(achievement_id: String) -> bool:
	return _unlocked.has(achievement_id)


func get_achievements() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for achievement_id: String in ACHIEVEMENTS:
		var entry: Dictionary = ACHIEVEMENTS[achievement_id].duplicate(true)
		entry["id"] = achievement_id
		entry["unlocked"] = is_unlocked(achievement_id)
		entry["unlocked_at"] = int(_unlocked.get(achievement_id, 0))
		entry["pending"] = _pending.has(achievement_id)
		result.append(entry)
	return result


func unlock(achievement_id: String) -> bool:
	if not ACHIEVEMENTS.has(achievement_id) or is_unlocked(achievement_id):
		return false
	_unlocked[achievement_id] = int(Time.get_unix_time_from_system())
	_pending[achievement_id] = true
	_save_state()
	achievement_unlocked.emit(achievement_id)
	sync_pending()
	return true


func record_satan_stream(emitting: bool) -> void:
	if emitting:
		unlock(SATAN_PISS)


func record_satan_jumpscare() -> void:
	unlock(SATAN_JUMPSCARE)


func _on_collection_changed(card_ids: Array[String]) -> void:
	# This signal follows a committed collection save, including fusion and Secrets.
	# History also covers already-owned cards and cards consumed by auto fusion.
	for card_id: String in card_ids:
		if not CardDatabase.is_collectible_card(card_id) or not CollectionManager.has_discovered_card(card_id):
			continue
		var rarity := str(CardDatabase.get_card(card_id).get("rarity", "")).to_lower()
		if RARITY_ACHIEVEMENTS.has(rarity):
			unlock(str(RARITY_ACHIEVEMENTS[rarity]))


func _steam_available() -> bool:
	return is_instance_valid(_steam) and NetworkManager.steam_ready


func _on_steam_status_changed(ready: bool, _message: String) -> void:
	if ready:
		_connect_steam()
	else:
		_steam_connected = false
		_inflight.clear()


func _connect_steam() -> void:
	if _steam_connected or not _steam_available():
		return
	if not _steam.is_connected("user_stats_stored", _on_user_stats_stored):
		_steam.connect("user_stats_stored", _on_user_stats_stored, CONNECT_DEFERRED)
	_steam_connected = true
	# Read once on connection. Never mistake a locally staged setAchievement for
	# a confirmed store when retrying an unsuccessful request in this session.
	for achievement_id: String in ACHIEVEMENTS:
		var status: Dictionary = _steam.getAchievement(achievement_id)
		if bool(status.get("ret", false)) and bool(status.get("achieved", false)):
			if not is_unlocked(achievement_id):
				_unlocked[achievement_id] = int(Time.get_unix_time_from_system())
			_pending.erase(achievement_id)
	_save_state()
	sync_pending()


func sync_pending() -> void:
	if not _steam_connected or not _steam_available() or not _inflight.is_empty():
		return
	for achievement_id: String in _pending:
		if _steam.setAchievement(achievement_id):
			_inflight.append(achievement_id)
	if _inflight.is_empty():
		return
	_retry_elapsed = 0.0
	if not _steam.storeStats():
		_inflight.clear()


func _on_user_stats_stored(game_id: int, result: int) -> void:
	if game_id != NetworkManager.APP_ID or _inflight.is_empty():
		return
	var submitted := _inflight.duplicate()
	_inflight.clear()
	# Steam EResult 1 = OK. All other results leave the batch pending.
	if result != 1:
		return
	for achievement_id: String in submitted:
		_pending.erase(achievement_id)
		achievement_synced.emit(achievement_id)
	_save_state()
	sync_pending()


func _load_state() -> void:
	var config := ConfigFile.new()
	if config.load(save_path) != OK:
		return
	for achievement_id: String in ACHIEVEMENTS:
		var timestamp := int(config.get_value("unlocked", achievement_id, 0))
		if timestamp > 0:
			_unlocked[achievement_id] = timestamp
			# Reconcile with Steam each launch, including an interrupted last store.
			_pending[achievement_id] = true


func _save_state() -> bool:
	var config := ConfigFile.new()
	for achievement_id: String in _unlocked:
		config.set_value("unlocked", achievement_id, _unlocked[achievement_id])
	var error := config.save(save_path + ".tmp")
	if error == OK:
		error = DirAccess.rename_absolute(save_path + ".tmp", save_path)
	_save_dirty = error != OK
	if _save_dirty:
		push_warning("Could not save achievements: " + error_string(error))
	return not _save_dirty
