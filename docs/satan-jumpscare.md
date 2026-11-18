# Idle Satan jumpscare

Click Satan four times within 1.5 seconds while facing the idle table in the hub.
Slow clicks expire. Right clicks and mouse releases do not count. The effect
runs for 1.05 seconds, followed by waking up on the floor and an eight-second
cooldown after recovery finishes.

Each ordinary idle click also nudges Satan 0.12 world units away from the camera
over 0.035 seconds and returns him in 0.1 seconds. Repeated clicks reuse the
same resting position, including during jumpscare cooldown. Recoil is stopped
and restored before the jumpscare or another interaction takes over.

At half the required clicks, the [authored Piss scene](satan-stream.md) emits
from Satan's lower body over the table toward the player's lower body. Its
emitter is directly editable under Satan in `GameTable.tscn`. The full jumpscare
immediately clears the stream and its sound.

`scripts/main/SatanJumpscare.gd` moves the existing Satan sprite directly in front
of the camera, plays its laughing sheet and independently shakes both sprite
and camera. A temporary OmniLight3D strobes at 10 Hz against a black environment.
The sound is `assets/sounds/SFX/jumpscare.mp3`, through the existing SFX volume
controls. It plays through normally
after the visual scare ends. Cosmetic shake uses a separate RNG.

After the close-up, Satan and the room return while the camera lies 0.25 units
above the hub floor, looking upward at 86 degrees with a slight roll. The camera
holds that pose for 0.8 seconds, then smoothly rises and rotates back to its
original pose over 3.2 seconds. The floor height comes from the hub room's world
position, rather than assuming the floor is at world zero. These timings and
the eye clearance are configurable on the jumpscare controller.

Main suspends camera owners, table/collection input, the journal, keys, clicker,
turn arrows and Pause throughout the scare, lying phase and getting up. HUD
canvases stay hidden until recovery completes. The camera overlay layers
are marked with the `screen_overlay_effects` group: lens effects and screen
post-processing retain their original visibility and materials throughout the
close-up, lying phase and getting up. Camera transform and HUD canvas
visibility restore exactly at the end; the render mask, environment and Satan's
animation/rendering state restore before waking up. Ordinary hover is cleared
before the scare takes ownership so a late
mouse-exit cannot overwrite its close-up. The effect does not alter progression,
cards, currency or intro completion.

The trigger is unavailable during the intro, matches, table setup screens,
screen focus/turn transitions, other rooms, modal UI and active/pending online
sessions. An incoming lobby cancels either the scare or recovery immediately,
restoring the original camera and input.

Waking up also starts the [procedural blood border](blood-overlay.md), which
remains below the scratches and pixelation and fades out over nine seconds.
It continues after the player has stood up; cancelling the sequence clears it.

## Verification

Run `tests/run_collection_tests.ps1 -Scenes satan_jumpscare_test,satan_greeting_test`.
The jumpscare suite covers actual viewport clicks, threshold/expiry, repeated
spam, simultaneous sprite/camera shake, light on/off states, floor clearance and
upward view, the lying hold, gradual rising, input/HUD locks across recovery,
exact camera/HUD restoration, preserved lens/screen overlays (including an
already hidden overlay), close-up cancellation and lobby cancellation
mid-rise. Render runs also capture the close-up, lying pose and getting up.
The extended suite passes 51 headless checks, including the half-click stream.
The close-up and floor captures were visually checked with the overlay effects
active; the render run completed without engine errors.
Full-scene shutdown can report leaked objects and resources still in use after
the passing suite.
Live Steam and exported builds require separate verification.
