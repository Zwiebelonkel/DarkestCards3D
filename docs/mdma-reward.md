# Story level 25 MDMA reward

A saved victory in **story level 25** unlocks the supplied
`assets/environments/props/mdma/mdma.glb` package. It replaces unclaimed older
packages, waits until the player returns to the idle hub, falls onto the existing
table spot, and uses the same yellow hover outline and saved left-click pickup.
Later saved story/ordinary victories queue another MDMA package; losses, draws,
player XP levels and training do not unlock or queue it. Earning the Silver Bullet
from the [grave-name puzzle](grave-name-puzzle.md) permanently stops ordinary MDMA
drops, like the earlier package puzzles. Older saves that completed story 25
receive a pending package. The settings cheat button selects MDMA from that
milestone onward and can still force a debug drop after puzzle completion.

The shared effect lasts **60 seconds**, including **5-second fades**. Its own
CanvasLayer screen shader adds soft rose/amber halation, gentle breathing and
fine grain. MDMA adds an owned Master lo-fi distortion (drive 0.10 at full strength)
and quiet generated vinyl crackle, with strength following the visual fade.
The original music arrangement slows and drops in pitch to **85%** at full
effect strength, following the same fade-in/out. Cleanup restores its exact
previous pitch without restarting playback. MDMA does not reveal Hint1 or Hint2.
The gunshot hearing filter retains its first Master slot. Cleanup removes only
the owned MDMA effect; room filters, volumes and unrelated effects remain intact.

After the initial fade-in, the supplied recordings play one at a time:

| Recording | Listener-relative direction |
| --- | --- |
| Pablo | Front, local -Z |
| Trinity | Right, local +X |
| Stuart (`steward.mp3`) | Behind, local +Z |
| Hannah | Left, local -X |
| Separator (`seperator.mp3`) | Centered |

Each clip finishes before the next begins, with a 0.35-second gap. After the
separator the sequence restarts at Pablo until the visual effect ends. A real
AudioStreamPlayer3D follows the current camera, with a 2m source radius and no
distance attenuation. Spatial rendering follows Godot and the output device;
standard stereo does not provide a dedicated rear speaker or HRTF processing.
Pause freezes the countdown, delay timer and playing clips together. Expiry,
replacement by an admin drop, and scene exit stop all clips and pending callbacks.

`progression/mdma_consumed` records use history independently from
`progression/mdma_package_pending`. Unlock eligibility is derived from story
completion. Failed save transactions restore the previous currency, story and
package state. Clearing/switching profiles clears the MDMA state with the other
story packages.

## Editing and validation

- Shared pickup: `scripts/props/WeedPickup.gd`, `scenes/props/WeedPickup.tscn`.
- Audio sequence, source radius and crackle: `scripts/props/MdmaEffectAudio.gd`.
- Visual: `assets/shader/mdma.gdshader`.
- Model wrapper: `scenes/props/MdmaPackage.tscn`.
- `tools/mdma/build_assets.tscn` bakes the supplied MP3s into export-ready `.res`
  streams, the Silver Bullet icon, and menu/card translations. Rerun when sources change.
- `tools/weed/prepare_validation.ps1` creates an isolated project with redirected
  saves and Steam disabled. Run save-mutating suites sequentially in that copy.
- `tests/mdma_reward_test.tscn` covers the real story result, replacement, real
  picked input, failed saves, migration, reset, actual clip completion/looping,
  pause, fade-out, expiry, repeated wins and leaving during the effect.

Captures and reports: [validation/mdma-reward/](validation/mdma-reward/).
Audio playback timing and 3D placement were checked with the silent Dummy driver;
subjective sound and headphone localization were not auditioned. Exported builds
and live Steam were not tested.
