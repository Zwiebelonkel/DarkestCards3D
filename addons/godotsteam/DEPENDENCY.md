# GodotSteam dependency pin

The Windows online build uses a complete, versioned GodotSteam GDExtension
bundle. Do not update individual DLLs or substitute debug DLLs into release
builds. The build script verifies the dependency lock before exporting.

## Selected upstream bundle

- GodotSteam: **4.20.1 GDExtension**, tag `v4.20.1-gde`.
  The upstream archive's `plugin.cfg` reports `4.20`; retain that upstream
  metadata and identify the exact patch release by archive tag and hashes.
- Supported Godot baseline: **4.4+**, according to the upstream release.
- Steamworks SDK: **1.64**, including the bundle's matching `steam_api64.dll`.
- [Official release](https://codeberg.org/godotsteam/godotsteam/releases/tag/v4.20.1-gde).
- [Official archive](https://codeberg.org/godotsteam/godotsteam/releases/download/v4.20.1-gde/godotsteam-4.20.1-gdextension-plugin-4.4.zip), 27,426,509 bytes.
- Archive SHA-256: `1CB9430BB90A6302ED33A1F6536A2FEBEF7B1738EB0D584EF4740809867F68B1`.
- Archive and installed-file SHA-256 values are recorded in `dependency-lock.json`.
  Update that lock only from the verified upstream archive, together with the
  complete bundle and this record.

On Godot 4.4.1, the selected release bundle passes eight native peer
construction/destruction cycles and eight host socket lifecycle cycles, both
with process exit code 0, including Steam shutdown. The production native,
lifecycle, multiplayer exit and replacement regressions also pass as separate
release and debug exports, all eight runs with exit code 0. See
`tests/NETWORK_LIFECYCLE_TESTING.md` for the checks.

## Why 4.22.1 is excluded

The previously installed 4.22.1 release DLL reproducibly faults when a
`SteamMultiplayerPeer` loses its final reference. The built-in
`MultiplayerPeerExtension` control passes with the same Godot 4.4.1 release
engine. This distinguishes the extension's destruction path from a general
engine peer destructor failure.

The [4.22.1 native destructor](https://codeberg.org/godotsteam/godotsteam/src/tag/v4.22.1-gde/godotsteam_multiplayer_peer.cpp#L51)
calls `close()`, an inherited engine binding in a GDExtension. The
[4.20.1 destructor](https://codeberg.org/godotsteam/godotsteam/src/tag/v4.20.1-gde/godotsteam/godotsteam_multiplayer_peer.cpp#L48)
calls its own `_close()` implementation directly. The unsafe call appears in
the [branch-unification commit of 2026-08-09](https://codeberg.org/godotsteam/godotsteam/commit/ac09b60eeee085a8c605b16105bf73bcbee5bfa6).

[Godot 4.4.1 frees the extension instance from `Object::~Object()`](https://github.com/godotengine/godot/blob/4.4.1-stable/core/object/object.cpp#L2135),
after destruction of the engine's derived peer. Calling the inherited engine
binding at this point re-enters an object whose peer lifetime has ended. This
is the source-level explanation for the native fault; delaying GDScript
teardown cannot repair that destructor call. Version 4.22.1 still contains it.

## Updating the pin

Verify that a replacement uses direct native cleanup during destruction, then
run the isolated native probe as both an actual release export and a separate
debug export. Require the success marker and process exit code 0, with Steam
initialization available; `SKIP` is not a native test pass. Also run the
production lifecycle and multiplayer exit regressions. Record the source tag,
archive URL and SHA-256 hashes for the exact tested bundle. Keep all platform
libraries from one version.
