extends Node

# Bounded native DLL smoke test for both editor/debug and exported release.
# It opens only local host sockets; it creates no Steam lobby or invitations.
var failures := 0
const CYCLES := 8


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	print(("PASS " if condition else "FAIL ") + description)
	if not condition:
		failures += 1


func _run() -> void:
	print("NATIVE_PEER_PROBE_BUILD: " + ("debug" if OS.is_debug_build() else "release"))
	var release_only := OS.get_cmdline_user_args().has("--release-only")
	print("NATIVE_PEER_PROBE_MODE: " + ("release-only" if release_only else "production-teardown"))
	check(DeckManager.SAVE_PATH.begins_with("res://test-user/"), "Native probe uses isolated saves")
	if OS.get_cmdline_user_args().has("--inspect-library"):
		print("NATIVE_PEER_LIBRARY_MANIFEST: " + FileAccess.get_file_as_string("res://addons/godotsteam/godotsteam.gdextension"))
		await get_tree().create_timer(5.0).timeout
	if OS.get_cmdline_user_args().has("--generic-extension"):
		for cycle in range(CYCLES):
			var generic := MultiplayerPeerExtension.new()
			var generic_weak: WeakRef = weakref(generic)
			generic = null
			check(generic_weak.get_ref() == null, "Generic MultiplayerPeerExtension cycle %d releases without Steam" % cycle)
		print("NATIVE_GENERIC_PROBE: " + ("PASS" if failures == 0 else "FAIL"))
		get_tree().quit(0 if failures == 0 else 1)
		return
	var initialized: Dictionary = Steam.get_steam_init_result()
	if initialized.is_empty():
		initialized = Steam.steamInitEx(480, false)
	if int(initialized.get("status", -1)) != Steam.STEAM_API_INIT_RESULT_OK:
		print("NATIVE_PEER_PROBE: SKIP Steam initialization unavailable (status %d)" % int(initialized.get("status", -1)))
		get_tree().quit(0)
		return
	NetworkManager.steam_ready = true
	Steam.initRelayNetworkAccess()
	for cycle in range(CYCLES):
		var peer := SteamMultiplayerPeer.new()
		peer.server_relay = true
		peer.no_nagle = true
		var error := peer.create_host(0)
		check(error == OK, "Native cycle %d creates a host socket" % cycle)
		if error != OK:
			break
		NetworkManager._steam_peer = peer
		get_tree().get_multiplayer().multiplayer_peer = peer
		var native_weak: WeakRef = weakref(peer)
		peer = null
		if release_only:
			# Diagnostic control: distinguish destructor failure from close()
			# followed by a second close inside the native destructor.
			var retiring: SteamMultiplayerPeer = NetworkManager._steam_peer
			NetworkManager._steam_peer = null
			get_tree().get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
			retiring = null
		else:
			NetworkManager.leave_lobby("Native smoke cycle")
			check(native_weak.get_ref() != null and NetworkManager._is_leaving, "Native cycle %d retains peer during deferred close" % cycle)
		for frame in range(4):
			await get_tree().process_frame
		check(native_weak.get_ref() == null and not NetworkManager._is_leaving and get_tree().get_multiplayer().multiplayer_peer is OfflineMultiplayerPeer, "Native cycle %d detaches, closes and releases peer" % cycle)
	NetworkManager.steam_ready = false
	Steam.steamShutdown()
	print("NATIVE_PEER_PROBE: " + ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)
