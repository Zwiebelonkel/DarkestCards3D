# Global playtime and Satan's 150-minute encounter

`PlaytimeManager` starts with the game and counts monotonic running time across
the main menu, settings, every room, matches and pause menus. It belongs to the
installation rather than a save slot. Selecting or resetting a slot does not
reset it. Time while the game is closed is excluded. Existing installations
start counting when this feature is first run; historical Steam playtime is
not imported.

`user://playtime.cfg` stores accumulated seconds and one-time encounter
completion. Checkpoints are written every five seconds, on focus loss and on
normal exit. Writes use a temporary file and retain the previous checkpoint
as a backup. Startup recovers the greatest valid time and completion flag
from these files. A forced process termination can lose up to five seconds
since the latest checkpoint.

After 9,000 seconds the encounter is pending until Main's hub (room 0) is
available. Other rooms, running matches, online sessions, active dialogs,
open detail views and camera transitions defer it. It also triggers when
returning to the hub or reopening the game, regardless of the current hub
side. The ordinary first-visit greeting finishes before this encounter.

The camera swings toward Satan for 2.8 seconds. World processing, physics
picking, journal, turn controls and pause navigation are locked; existing HUD
layers are hidden. Satan's two-frame laughing animation and the existing deep
voice sample remain active throughout the approach, text and return. Animation
and sound match the stream's faster laughter: 32 FPS and +7 semitones, using
the same shared tuning constants. The
line uses the local Steam persona name literally, with rich text disabled:

> NAME, Danke für dein Geld, du wirst es nie wiedersehen, fick dich.

The camera's lens and screen filters stay visible during approach, dialogue
and return. Only ordinary HUD layers are hidden; `screen_overlay_effects`
layers retain their existing visibility and materials even during the pause.

Settings → Cheats → `Brain Timer zurücksetzen` resets elapsed time and the
encounter completion flag, so the scene can trigger again after the configured
duration. The reset is saved globally using a new checkpoint generation;
older completed backups cannot undo it. Resetting also cancels an active
encounter and restores its camera and controls.

The speaker name is red. The complete line is also red, with small independent
letter movements from `SatanLaughTextEffect.gd`, including after the typewriter
finishes and while the world is paused. `DialogueStyle.gd` applies the display
stack directly, so persona names remain literal and character counts stay intact.
The same effect is used for the laughing final line of the Holy Water return.
Other lines keep their usual body color and do not move.

Without Steam, NAME uses the existing localized `Abschaum` fallback. The
requested sentence itself is German in every language. Left click, Space,
Enter, Escape or controller A first reveals the text, then dismisses it.
The camera returns to its original pose and lens over 1.6 seconds before
restoring input, HUD visibility, pause state and Satan's idle animation.
Completion is then saved globally and never replayed for other slots.

Removing the scene or accepting a Steam lobby during the presentation
restores the pause and leaves it pending. Focus loss does not dismiss the
dialog. `tests/satan_playtime_test.tscn` exercises checkpoint reload, pause
time, slot independence, hub deferral, literal persona names, continuous
laughter, input locks, restoration, one-time completion and interruptions.
Use the isolated test preparation helper and Godot MCP; success marker:
`SATAN_PLAYTIME_TESTS: PASS`. The render run writes
`test-user/satan-playtime-dialog.png` in the isolated project.
