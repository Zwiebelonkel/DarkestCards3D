# Ambient screams

`scripts/main/AmbientScreams.gd` is created once by `Main.gd` when gameplay starts.
The first scream and each subsequent scream wait a fresh random 300–600 seconds
of unpaused gameplay. Main-menu time does not count. Leaving Main frees the timer
and sound source. Each client runs its own local ambience.

Each event randomly selects one of the three recordings in
`res://assets/sounds/SFX/screams/`, with pitch scale 0.8–1.2. The spatial emitter
appears 5–12 metres horizontally from the current viewport camera, in any
direction, with a vertical offset of -1 to +2 metres. It stays at that world
position during playback. A missing camera skips the event and starts a fresh
interval. Audio uses the SFX bus at -8 dB, unit size 8 and maximum distance 40.

Recordings are preloaded explicitly so they are included in exported builds;
add new recordings to `SCREAMS` when extending the folder.

Validation: `tests/ambient_screams_test.tscn` covers initial delay, rescheduling,
camera-relative placement after movement, sample/pitch variation, SFX routing,
fixed source position, pausing and cleanup. Run with the isolated save-safe
`tests/run_collection_tests.ps1 -Scenes ambient_screams_test` runner.
