# First-visit greeting

New and reset save slots enter the hub in darkness, directly in front of Satan's
animated eyes. After a short hold the camera returns to its normal pose over
12 seconds while Satan explains packs, the Collection and building a deck.
All lights, emissive props, screens and HUD remain hidden until both the dialog
and camera movement have finished. Their previous states are then restored,
the music starts from the beginning, and `scare.mp3` plays once on the SFX bus.

Canvas layers in `screen_overlay_effects` keep their current visibility and
materials throughout the intro. The camera's lens, grain, pixel and vignette
passes therefore remain active over the eyes and dialogue, as in normal play.

The typewriter and syllable sample match the existing NPC dialogs. Satan uses
the Black Market dealer's -16-semitone voice offset, with no sentence-end sound.
Music stays stopped throughout the greeting. Lines advance automatically;
left click, Space, Enter or gamepad A reveals the current line or advances it.
Gameplay, pause, journal, keys and camera turning stay locked throughout.

Text and timing live in `scripts/main/SatanGreeting.gd`; translations are in
`localization/game.csv`. The greeting uses the current Steam persona name, or
"Abschaum" if Steam is unavailable or the name is empty. Names render literally.

`intro/greeting_completed` is stored in each slot's `currency.cfg` after successful
completion. Aborted intros replay; failed saves roll back the completion flag.
Existing saves without this key are treated as already greeted. Online entry
bypasses the intro, and an incoming lobby cancels it without marking it complete.

`Main.greeting_enabled` can disable this presentation for isolated scene fixtures.
The shared match test runner sets that scene property to false in its temporary
copy; the greeting suite explicitly enables it for its instances.

```powershell
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/satan_greeting_test.tscn' -SuccessMarker 'SATAN_GREETING_TESTS: PASS' -ImportAssets -Visual -QuitAfterFrames 16000
```

The isolated suite checks real input, camera movement, darkness and restoration,
dialog timing and voice, literal names, persistence, slot switching, interruption,
online entry and failed saves. Visual runs capture eyes, greeting and restored hub.
