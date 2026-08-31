extends Control
class_name Matchmaking

signal closed

const NETWORK_MANAGER_PATH := NodePath("/root/NetworkManager")
const NO_LOBBY_ID := 0

const COLOR_STEAM_READY := Color(0.48, 0.84, 0.55, 1.0)
const COLOR_STEAM_ERROR := Color(0.94, 0.28, 0.31, 1.0)
const COLOR_STEAM_PENDING := Color(0.75, 0.7, 0.71, 1.0)
const COLOR_CONNECTED := Color(0.48, 0.84, 0.55, 1.0)
const COLOR_WAITING := Color(0.82, 0.56, 0.25, 1.0)
const COLOR_DISCONNECTED := Color(0.73, 0.2, 0.24, 1.0)

@onready var steam_status_label: Label = %SteamStatusLabel
@onready var status_label: Label = %StatusLabel
@onready var lobby_count_label: Label = %LobbyCountLabel
@onready var lobby_list: ItemList = %LobbyList
@onready var host_button: Button = %HostButton
@onready var refresh_button: Button = %RefreshButton
@onready var join_button: Button = %JoinButton
@onready var current_lobby_title: Label = %CurrentLobbyTitle
@onready var lobby_id_label: Label = %LobbyIdLabel
@onready var member_list_label: Label = %MemberListLabel
@onready var connection_label: Label = %ConnectionLabel
@onready var invite_button: Button = %InviteButton
@onready var start_button: Button = %StartButton
@onready var back_button: Button = %BackButton

var _network_manager: Node
var _selected_lobby_id := NO_LOBBY_ID


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_network_manager = get_node_or_null(NETWORK_MANAGER_PATH)

	host_button.pressed.connect(_on_host_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	join_button.pressed.connect(_on_join_pressed)
	invite_button.pressed.connect(_on_invite_pressed)
	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)
	lobby_list.item_selected.connect(_on_lobby_selected)
	lobby_list.item_activated.connect(_on_lobby_activated)

	if _network_manager == null:
		_set_steam_status(false, "Netzwerkdienst fehlt")
		_set_status("Der NetworkManager ist nicht verfügbar.", true)
		_update_controls()
		return

	_connect_network_signal(&"steam_status_changed", _on_steam_status_changed)
	_connect_network_signal(&"lobby_list_updated", _on_lobby_list_updated)
	_connect_network_signal(&"lobby_state_changed", _on_lobby_state_changed)
	_connect_network_signal(&"connection_state_changed", _on_connection_state_changed)
	_connect_network_signal(&"match_started", _on_match_started)
	_connect_network_signal(&"session_closed", _on_session_closed)
	_refresh_all()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


func open() -> void:
	visible = true
	_selected_lobby_id = NO_LOBBY_ID
	lobby_list.deselect_all()

	if _network_manager == null:
		_set_steam_status(false, "Netzwerkdienst fehlt")
		_set_status("Online-Modus nicht verfügbar: NetworkManager fehlt.", true)
		_update_controls()
		back_button.grab_focus()
		return

	_refresh_all()
	if _is_steam_ready() and not _is_in_lobby():
		_set_status("Offene Steam-Lobbys werden gesucht …")
		if not _call_network_bool(&"request_lobbies"):
			_set_status("Lobbys konnten nicht abgerufen werden.", true)
	if refresh_button.disabled:
		back_button.grab_focus()
	else:
		refresh_button.grab_focus()


func close_without_leaving() -> void:
	visible = false


func _connect_network_signal(signal_name: StringName, callback: Callable) -> void:
	if _network_manager.has_signal(signal_name) and not _network_manager.is_connected(signal_name, callback):
		_network_manager.connect(signal_name, callback)


func _on_steam_status_changed(ready: bool, message: String) -> void:
	_set_steam_status(ready, message)
	if not message.is_empty():
		_set_status(message, not ready)
	elif ready:
		_set_status("Steam ist bereit. Wähle eine Lobby oder hoste selbst.")
	else:
		_set_status("Steam ist nicht verfügbar.", true)
	_refresh_lobby_state()
	_update_controls()
	if ready and visible and not _is_in_lobby():
		_call_network_bool(&"request_lobbies")


func _on_lobby_list_updated(entries: Array) -> void:
	_populate_lobby_list(entries)
	if entries.is_empty():
		_set_status("Keine offenen Lobbys gefunden. Du kannst selbst eine hosten.")
	else:
		_set_status("%d offene %s gefunden." % [entries.size(), "Lobby" if entries.size() == 1 else "Lobbys"])
	_update_controls()


func _on_lobby_state_changed() -> void:
	_refresh_lobby_state()
	_update_controls()
	if _is_in_lobby():
		_clear_selection()
		_set_status(
			"Lobby geöffnet. Lade jetzt einen Freund ein."
			if _is_host()
			else "Lobby beigetreten. Warte, bis der Host das Match startet."
		)
	elif visible:
		_set_status("Keine Lobby aktiv. Wähle eine Lobby oder hoste selbst.")


func _on_connection_state_changed() -> void:
	_refresh_lobby_state()
	_update_controls()
	if _has_connected_opponent():
		_set_status("Gegenspieler verbunden. Das Match ist startbereit.")
	elif _is_in_lobby():
		_set_status("Lobby aktiv. Warte auf einen Gegenspieler.")


func _on_match_started() -> void:
	close_without_leaving()


func _on_session_closed(reason: String) -> void:
	_refresh_all()
	if visible:
		_set_status(reason if not reason.is_empty() else "Die Online-Sitzung wurde beendet.", not reason.is_empty())


func _on_host_pressed() -> void:
	_clear_selection()
	_set_status("Steam-Lobby wird erstellt …")
	if not _call_network_bool(&"create_lobby"):
		_set_status("Lobby konnte nicht erstellt werden.", true)
	_update_controls()


func _on_refresh_pressed() -> void:
	_clear_selection()
	_set_status("Offene Steam-Lobbys werden gesucht …")
	if not _call_network_bool(&"request_lobbies"):
		_set_status("Lobbys konnten nicht abgerufen werden.", true)
	_update_controls()


func _on_join_pressed() -> void:
	_join_selected_lobby()


func _on_invite_pressed() -> void:
	if _call_network_bool(&"invite_friends"):
		_set_status("Steam-Einladung wird geöffnet …")
	else:
		_set_status("Freunde konnten nicht eingeladen werden.", true)


func _on_start_pressed() -> void:
	if not _is_host():
		_set_status("Nur der Host kann das Match starten.", true)
		return
	if not _can_start_match():
		_set_status("Zum Starten muss ein Gegenspieler verbunden sein.", true)
		return

	_set_status("Match wird gestartet …")
	if not _call_network_bool(&"start_match"):
		_set_status("Das Match konnte nicht gestartet werden.", true)


func _on_back_pressed() -> void:
	if _network_manager != null and _is_in_lobby() and _network_manager.has_method(&"leave_lobby"):
		_network_manager.call(&"leave_lobby")
	close_without_leaving()
	closed.emit()


func _on_lobby_selected(index: int) -> void:
	_selected_lobby_id = _lobby_id_at(index)
	_update_controls()


func _on_lobby_activated(index: int) -> void:
	_selected_lobby_id = _lobby_id_at(index)
	_update_controls()
	_join_selected_lobby()


func _join_selected_lobby() -> void:
	if _selected_lobby_id == NO_LOBBY_ID:
		_set_status("Bitte zuerst eine Lobby auswählen.", true)
		return
	_set_status("Lobby wird betreten …")
	if not _call_network_bool(&"join_lobby", [_selected_lobby_id]):
		_set_status("Der Lobby konnte nicht beigetreten werden.", true)
	_update_controls()


func _refresh_all() -> void:
	if _network_manager == null:
		_update_controls()
		return

	var ready := _is_steam_ready()
	_set_steam_status(ready, "Bereit" if ready else "Nicht verfügbar")
	var entries_value: Variant = _network_manager.get("lobby_entries")
	_populate_lobby_list(entries_value if entries_value is Array else [])
	_refresh_lobby_state()
	_update_controls()


func _refresh_lobby_state() -> void:
	var lobby_id := _current_lobby_id()
	var in_lobby := lobby_id != NO_LOBBY_ID
	var host := in_lobby and _is_host()
	var connected := in_lobby and _has_connected_opponent()

	if not in_lobby:
		current_lobby_title.text = "KEINE LOBBY AKTIV"
		lobby_id_label.text = "LOBBY-ID: —"
		member_list_label.text = "Noch nicht in einer Lobby."
		connection_label.text = "NICHT VERBUNDEN"
		connection_label.add_theme_color_override("font_color", COLOR_DISCONNECTED)
		return

	current_lobby_title.text = "DEINE LOBBY · %s" % ("HOST" if host else "CLIENT")
	lobby_id_label.text = "LOBBY-ID: %d" % lobby_id
	var member_names := _get_lobby_member_names()
	if member_names.is_empty():
		member_list_label.text = "Spielerliste wird geladen …"
	else:
		var member_lines: PackedStringArray = []
		for member_name in member_names:
			member_lines.append("• %s" % member_name)
		member_list_label.text = "\n".join(member_lines)

	if connected:
		connection_label.text = "GEGENSPIELER VERBUNDEN"
		connection_label.add_theme_color_override("font_color", COLOR_CONNECTED)
	elif host:
		connection_label.text = "WARTE AUF GEGENSPIELER"
		connection_label.add_theme_color_override("font_color", COLOR_WAITING)
	else:
		connection_label.text = "WARTE AUF DEN HOST"
		connection_label.add_theme_color_override("font_color", COLOR_WAITING)


func _populate_lobby_list(entries: Array) -> void:
	var previous_selection := _selected_lobby_id
	lobby_list.clear()
	_selected_lobby_id = NO_LOBBY_ID

	for entry_value in entries:
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		var lobby_id := int(entry.get("id", NO_LOBBY_ID))
		if lobby_id == NO_LOBBY_ID:
			continue
		var lobby_name := str(entry.get("name", "Lobby von %s" % str(entry.get("owner_name", "Unbekannt"))))
		var owner_name := str(entry.get("owner_name", "Unbekannt"))
		var members := int(entry.get("members", 0))
		var max_members := int(entry.get("max_members", 2))
		lobby_list.add_item("%s    [%d/%d]" % [lobby_name, members, max_members])
		var item_index := lobby_list.item_count - 1
		lobby_list.set_item_metadata(item_index, lobby_id)
		lobby_list.set_item_tooltip(item_index, "Host: %s\nLobby-ID: %d" % [owner_name, lobby_id])
		if lobby_id == previous_selection:
			lobby_list.select(item_index)
			_selected_lobby_id = lobby_id

	var lobby_count := lobby_list.item_count
	lobby_count_label.text = "%d GEFUNDEN" % lobby_count


func _update_controls() -> void:
	var steam_ready := _is_steam_ready()
	var in_lobby := _is_in_lobby()
	var operation_pending := _is_lobby_operation_pending()
	var host := in_lobby and _is_host()
	var can_start := host and _can_start_match()

	host_button.disabled = not steam_ready or in_lobby or operation_pending
	refresh_button.disabled = not steam_ready or in_lobby or operation_pending
	join_button.disabled = not steam_ready or in_lobby or operation_pending or _selected_lobby_id == NO_LOBBY_ID
	lobby_list.mouse_filter = Control.MOUSE_FILTER_IGNORE if in_lobby or operation_pending or not steam_ready else Control.MOUSE_FILTER_STOP
	invite_button.disabled = not steam_ready or not in_lobby
	start_button.visible = host
	start_button.disabled = not can_start
	start_button.tooltip_text = "Match starten" if can_start else "Ein Gegenspieler muss verbunden sein."
	back_button.text = "LOBBY VERLASSEN" if in_lobby else "ZURÜCK"
	back_button.disabled = operation_pending


func _set_steam_status(ready: bool, detail: String) -> void:
	if ready:
		steam_status_label.text = "STEAM: BEREIT  ·  APP 480"
		steam_status_label.add_theme_color_override("font_color", COLOR_STEAM_READY)
	elif detail.to_lower().contains("prüf") or detail.to_lower().contains("initial"):
		steam_status_label.text = "STEAM: WIRD GEPRÜFT  ·  APP 480"
		steam_status_label.add_theme_color_override("font_color", COLOR_STEAM_PENDING)
	else:
		steam_status_label.text = "STEAM: OFFLINE  ·  APP 480"
		steam_status_label.add_theme_color_override("font_color", COLOR_STEAM_ERROR)


func _set_status(message: String, is_error := false) -> void:
	status_label.text = message
	status_label.add_theme_color_override(
		"font_color",
		Color(0.98, 0.47, 0.5, 1.0) if is_error else Color(0.9, 0.78, 0.79, 1.0)
	)


func _clear_selection() -> void:
	_selected_lobby_id = NO_LOBBY_ID
	lobby_list.deselect_all()


func _lobby_id_at(index: int) -> int:
	if index < 0 or index >= lobby_list.item_count:
		return NO_LOBBY_ID
	return int(lobby_list.get_item_metadata(index))


func _is_steam_ready() -> bool:
	return _network_manager != null and bool(_network_manager.get("steam_ready"))


func _current_lobby_id() -> int:
	if _network_manager == null:
		return NO_LOBBY_ID
	return int(_network_manager.get("current_lobby_id"))


func _is_in_lobby() -> bool:
	return _current_lobby_id() != NO_LOBBY_ID


func _is_host() -> bool:
	return _network_manager != null and bool(_network_manager.get("is_host"))


func _has_connected_opponent() -> bool:
	return _network_manager != null and _network_manager.has_method(&"has_connected_opponent") and bool(_network_manager.call(&"has_connected_opponent"))


func _is_lobby_operation_pending() -> bool:
	return (
		_network_manager != null
		and _network_manager.has_method(&"is_lobby_operation_pending")
		and bool(_network_manager.call(&"is_lobby_operation_pending"))
	)


func _can_start_match() -> bool:
	return _network_manager != null and _network_manager.has_method(&"can_start_match") and bool(_network_manager.call(&"can_start_match"))


func _get_lobby_member_names() -> Array[String]:
	var names: Array[String] = []
	if _network_manager == null or not _network_manager.has_method(&"get_lobby_member_names"):
		return names
	var names_value: Variant = _network_manager.call(&"get_lobby_member_names")
	if names_value is Array:
		for member_name in names_value:
			names.append(str(member_name))
	return names


func _call_network_bool(method_name: StringName, arguments: Array = []) -> bool:
	if _network_manager == null or not _network_manager.has_method(method_name):
		return false
	return bool(_network_manager.callv(method_name, arguments))
