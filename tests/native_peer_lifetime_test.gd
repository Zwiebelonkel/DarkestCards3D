extends Node

# Standalone engine control. Copy only this scene/script into a minimal project
# with no autoloads or GDExtensions, then run the same PCK with debug/release
# export templates. This test never initializes Steam or opens sockets.
const CYCLES := 8


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	print("NATIVE_PEER_LIFETIME_ENGINE: ", Engine.get_version_info().string)
	print("NATIVE_PEER_LIFETIME_BUILD: ", "debug" if OS.is_debug_build() else "release")
	print("NATIVE_PEER_LIFETIME_STEAM_PRESENT: ", ClassDB.class_exists("SteamMultiplayerPeer"))
	for cycle in range(CYCLES):
		print("NATIVE_PEER_LIFETIME_CREATE: ", cycle)
		var peer := MultiplayerPeerExtension.new()
		var witness: WeakRef = weakref(peer)
		print("NATIVE_PEER_LIFETIME_RELEASE: ", cycle)
		peer = null
		if witness.get_ref() != null:
			push_error("Native peer remained alive after releasing its final reference")
			get_tree().quit(1)
			return
		print("NATIVE_PEER_LIFETIME_RELEASED: ", cycle)
	print("NATIVE_PEER_LIFETIME_TEST: PASS")
	get_tree().quit(0)
