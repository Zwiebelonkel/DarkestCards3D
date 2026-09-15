# Network lifecycle regressions

`network_lifecycle_test.tscn` exercises production teardown ordering, cancellation
of pending lobby operations, deferred callback generations, original host
departure before P2P connects, and stale cinematic finalizers. Its final scenario
uses two actual ENet peers and the real Main scene: the host disconnects while
the client is animating an attack and holding a replacement snapshot.

Run it with the existing isolated runner:

```powershell
./tests/run_match_feature_tests.ps1 -Godot $Godot -TestScene res://tests/network_lifecycle_test.tscn -SuccessMarker 'NETWORK_LIFECYCLE_TESTS: PASS'
```

The runner prints the temporary project directory and redirects every player
save path before any autoload starts. Keep that directory for export checks.
The same project also contains `multiplayer_exit_test.tscn`,
`replacement_network_test.tscn`, and `network_roles_test.gd`.

## Native export check

The editor and a debug export do not establish that the release engine and
GodotSteam library safely destroy native peers. Build a complete release export
of the isolated project, using the installed matching Godot export template:

```powershell
Copy-Item -LiteralPath ./export_presets.cfg -Destination $SandboxRoot
$ReleaseRoot = Join-Path $SandboxRoot 'release-export'
New-Item -ItemType Directory -Path $ReleaseRoot -Force
$ExportArgs = @('--headless', '--path', ('"{0}"' -f $SandboxRoot),
    '--export-release', '"Windows Desktop"',
    ('"{0}"' -f (Join-Path $ReleaseRoot 'DarkestCards.exe')))
$ExportProcess = Start-Process -FilePath $Godot -ArgumentList $ExportArgs -WindowStyle Hidden -Wait -PassThru
if ($ExportProcess.ExitCode -ne 0) { throw "Export failed: $($ExportProcess.ExitCode)" }
New-Item -ItemType Directory -Path (Join-Path $ReleaseRoot 'test-user') -Force
```

Run the generated executable from its own directory with its emitted DLLs and
embedded project. No `--main-pack` or `--path` overlay is needed. The following
scenes can be passed as the scene argument:

- `res://tests/network_lifecycle_test.tscn`: complete lifecycle regression.
- `res://tests/native_peer_probe.tscn`: eight native host socket creation and
  teardown cycles with a running Steam client. It does not create Steam lobbies
  or send invitations. Success requires `NATIVE_PEER_PROBE: PASS`; `SKIP` means
  Steam initialization was unavailable and the native path was not tested.
- `res://tests/multiplayer_exit_test.tscn` and
  `res://tests/replacement_network_test.tscn`: existing exit and replacement RPC
  regressions.

Use `--headless --rendering-method gl_compatibility --max-fps 120` for transport
checks. A rendered run with the production renderer additionally covers the
actual visual path. Save each run with `--log-file` and inspect both its success
marker and process exit code: a native fault may happen after the last printed
GDScript assertion.

The native probe accepts optional arguments after `--`:

- `--release-only` compares native destruction without an explicit `close()`.
- `--generic-extension` destroys built-in `MultiplayerPeerExtension` instances
  without using Steam.
- `--inspect-library` prints the exported extension manifest and pauses for five
  seconds so the process's actual loaded DLL paths and hashes can be inspected.

For a completely independent engine control, copy only
`native_peer_lifetime_test.gd` and its `.tscn` into a minimal project with no
autoloads, addons, or imported extension list. Run its PCK with both matching
Godot export templates. Require `NATIVE_PEER_LIFETIME_STEAM_PRESENT: false`,
`NATIVE_PEER_LIFETIME_TEST: PASS`, and exit code 0. The generic mode above still
loads the main project's extension and autoloads, even though it makes no Steam
calls itself.

A debug control should be built separately with `--export-debug`, retaining its
matching generated debug DLL. Keep each build and its logs separate.

## GodotSteam destructor regression and dependency pin

The Godot 4.4.1 built-in `MultiplayerPeerExtension` destruction control passes
in both debug and release, including a project with no Steam extension or
autoloads. The 4.22.1 `SteamMultiplayerPeer` release probe faults on native
destruction. Do not describe this as a generic Godot peer destructor failure
or infer that it only occurs at application shutdown: lobby leave and online
match completion also release the peer.

The [4.22.1 destructor](https://codeberg.org/godotsteam/godotsteam/src/tag/v4.22.1-gde/godotsteam_multiplayer_peer.cpp#L51)
calls inherited `close()`, which re-enters the engine peer binding during
destruction. [Godot frees the extension from its `Object` base destructor](https://github.com/godotengine/godot/blob/4.4.1-stable/core/object/object.cpp#L2135),
after the engine's derived peer has been destroyed. The
[4.20.1 destructor](https://codeberg.org/godotsteam/godotsteam/src/tag/v4.20.1-gde/godotsteam/godotsteam_multiplayer_peer.cpp#L48)
uses direct `_close()` cleanup. The unsafe call is present in the
[2026-08-09 branch-unification commit](https://codeberg.org/godotsteam/godotsteam/commit/ac09b60eeee085a8c605b16105bf73bcbee5bfa6)
and remains in 4.22.1. This source difference explains why deferred GDScript
teardown cannot by itself fix native final-reference release.

The selected replacement is the official 4.20.1 GDExtension bundle for Godot
4.4+ and Steamworks 1.64. Its upstream `plugin.cfg` reports `4.20`; use the
release archive tag and hashes to identify patch release 4.20.1. Its native
release passes eight construction/destruction cycles and eight host socket
lifecycle cycles on Godot 4.4.1, including Steam shutdown and process exit
code 0. The production native, lifecycle, multiplayer exit and replacement
regressions also pass in both release and debug exports: eight runs with
success markers, matching DLL hashes and process exit code 0.
The source URL and pin procedure are recorded
in `addons/godotsteam/DEPENDENCY.md`;
`dependency-lock.json` records the exact tested archive and library hashes.
Validate the actual release DLL, its bundled Steam API, and process exit code.
Never treat a debug control or a `SKIP` marker as release-native coverage.

The repeatable matrix runner accepts an already isolated fixture from the
runner above and a directory containing the official matching templates:

```powershell
./tests/run_native_export_matrix.ps1 -Godot $Godot -Fixture $SandboxRoot -Templates $Templates
```

It exports both modes, verifies the DLL pair, and writes per-run logs and
`results.json` into a new directory inside the fixture. The fixture must have
the current project sources and pinned addon; real player saves remain outside
the fixture.
