# Satan halfway-click stream

In `scenes/table/GameTable.tscn`, select
`dealer/SatanMotionRoot/satan/Piss` and move that node to set the emission point.
It is an authored child of Satan, not a runtime-created substitute. Its local
position and rotation are never overwritten by the controller. The supplied
default places it on lower Satan. New droplets follow this source as Satan
moves; already emitted droplets remain in world space.

The effect starts on `ceil(clicks_required / 2)` clicks in the existing 1.5-second
window: two clicks with the current four-click jumpscare. Slow clicks expire;
right clicks, releases, unsafe contexts and jumpscare cooldown do not trigger it.
An active stream does not stack or restart on another halfway signal.

The target is 1.5 units below the player's camera and 0.2 units toward the table.
`scripts/effects/Piss.gd` computes a gravity arc reaching that target in 0.95
seconds. The default authored emission point and full arc clear the real table
mesh. Moving the source node deliberately changes the trajectory; it is not
automatically clamped back to a generated position.

The aim gently circles the lower player target (radius 0.12 units, 0.9 turns
per second), giving the emitted stream a slight corkscrew motion. Adjust
`Circle Radius` and `Circle Speed` on the Piss node in the inspector. The authored
emission point stays fixed relative to Satan.

Particles emit for 2.2 seconds; existing droplets then drain. Full jumpscare,
another table interaction, room/camera context change or an incoming lobby
clears the effect and looping sound. The halfway effect does not lock controls.

While particles are emitting, Satan loops his laughing sheet at 32 FPS with
faster voice playback. Hover cannot replace it. Emission end or cancellation
immediately restores ordinary animation and voice settings, even while existing
droplets are still draining; the full jumpscare then takes over normally.

The scene and audio originate from the user-supplied WaitingForHeavenStandalone
`Piss.tscn`, `piss.gd` and `audio/SFX/piss.mp3`. The yellow RibbonTrailMesh,
material, gravity/collision style and sound are reused. The source project is
unchanged; its achievement integration is not imported. The scene uses a native
`assets/sounds/SFX/piss_stream_audio.res` so the audio is immediately loadable
and included by scene dependencies, without a pending editor import.
`tests/import_satan_stream_audio.tscn` can rebuild this native resource from the
copied original MP3. The emitter budget is 420 particles, one draw pass, one
audio player and no added lights or collision shapes.

Verification: `satan_stream_test` covers halfway thresholds (four and five),
editable source transforms, ignored input, expiration, cooldown, natural drain,
unsafe contexts and lobby cancellation. `satan_jumpscare_test` also uses real
picked clicks, samples tabletop clearance and checks exact ballistic landing
and immediate shutdown before the scare. `satan_stream_visual.tscn` records
the player's view and four diagnostic angles through the actual lens/pixel
passes, plus paired idle/active process-time and draw-call samples.

Run `tests/run_collection_tests.ps1 -Scenes satan_stream_test,satan_jumpscare_test`.
All 22 stream and 51 jumpscare checks passed headless. Live Steam and exported
builds require separate verification. Some full-scene exits retain the existing
ObjectDB/resource shutdown warnings.
