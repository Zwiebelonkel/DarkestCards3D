# Blood border overlay

The visual effect lives entirely in `assets/shader/blood_border.gdshader`.
It is a single procedural shader with no textures or other shader dependencies.
`fade_progress = 0` shows the blood; `1` removes it completely. Progress both
retracts the rim beyond the screen edges and reduces its opacity. A translucent,
continuous border surrounds a clear area with rounded corners and soft edges.
Subtle noise adds texture and slight variation without breaking the outline.
Each playback uses an independent cosmetic RNG to vary `pattern_seed`.

`scenes/ui/BloodOverlay.tscn` supplies the CanvasLayer/ColorRect, and
`scripts/ui/BloodOverlay.gd` provides `play(seconds = -1)` and `clear()`.
The default playback lasts nine seconds, including a 0.9-second initial hold.
Each instance owns its material; repeated playback replaces the existing tween.
The rectangle ignores input, hides completely when idle, pauses with offline
Pause, and cleans up its tween on scene exit.

Main starts the blood on the table's `player_wakeup_started` signal after being
shot, and on SatanJumpscare's `recovery_started` signal as the player wakes on
the floor. It continues fading after the player has stood up. Ordinary startup,
the greeting, the jumpscare close-up and a win reveal do not trigger it. Skipping
the death presentation or cancelling the jumpscare clears the effect.

The stack is blood (CanvasLayer 0), lens/scratches (1), then pixelation (128).
Full-viewport BackBufferCopy nodes before the lens and pixel shaders make each
pass read the previous pass, including the blood. This follows Godot's
[screen-reading shader guidance](https://docs.godotengine.org/en/4.4/tutorials/shaders/screen-reading_shaders.html).
All three effect layers belong to `screen_overlay_effects` and remain available
throughout Satan's scare and recovery.

Run `tests/run_collection_tests.ps1 -Scenes blood_overlay_test,satan_jumpscare_test,startup_settings_test,offline_exit_skip_test`.
The blood suite checks playback, pause, repeat and cancellation. In render mode
it additionally measures the actual images: continuous, translucent red edges
on all four sides and a clear center, reduced
coverage and opacity over time, exact restoration, and the effect of pixelation
and scratches on the blood. Other suites exercise the actual two wake-up paths
and cancellation/skip behavior. Live Steam and exported builds are separate.

Verified: blood suite 9 checks headless and 18 rendered; jumpscare 46 checks
headless and rendered; startup/death wake 30 headless and 33 rendered; offline
skip suite 290 headless. The actual floor and death-wake captures were visually
inspected. Rendered blood and jumpscare runs completed without engine errors;
some full-scene shutdowns still report the existing ObjectDB leak warning.
