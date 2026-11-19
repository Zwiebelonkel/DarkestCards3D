# Story level 20 cocaine reward

A saved victory in **story level 20** replaces the weed pickup with the supplied
`cocaine.glb` package. Player level and ordinary victories do not qualify.
The package waits for the idle hub after the match, then falls onto the same
table spot, settles, gains a yellow hover outline, and disappears when clicked.
An unclaimed weed bag is replaced, so two packages never coexist.
After story level 25, [MDMA](mdma-reward.md) becomes the selected package instead.

The effect lasts **60 seconds**, including **5 seconds of smooth fade-in and
5 seconds of fade-out**. `cocaine.gdshader` uses faster ripples, pulsing zoom,
radial RGB separation, sharper contrast and cyan/magenta edges. The original
music becomes **35% faster and higher in pitch** at full strength, then returns
to its exact previous pitch. Playback is not restarted. Cocaine does not add
the weed high-cut or select the cursed arrangement. Existing room audio filters
and music volume continue to apply. Pause freezes the countdown; leaving the
scene removes the temporary effect and restores music speed immediately.

**Hint2 remains the existing `EmptyRoom/hint2` sprite**, authored in
`scenes/rooms/EmptyHospitalRoom.tscn`. Its position, rotation, pixel size (0.027),
four animation frames and parent are preserved. There is no second Hint2 next
to Hint1 in the hub. The existing sprite starts hidden and fades with the cocaine
effect at its own hospital wall location. `hint2_emission.tres` uses the red
symbols as its emission texture at energy 3, with alpha blending and no billboard.

After unlocking, cocaine returns after every saved victory until the
[boiler puzzle](boiler-puzzle.md) grants the Jester Eye. Its acquisition history
permanently stops ordinary cocaine drops, including after trading the eye.
Pending drops are persisted
separately from first-use history. First use is tracked by
`progression/cocaine_consumed` in the existing currency save. Eligibility is
derived from completed story level 20, including older saves. Failed victory or
consumption saves restore the prior state and permit retry. A consumed cocaine
reward never falls back to an older unclaimed weed reward. Cocaine does not set
the weed-use history required by the pump puzzle.

In **Settings → Cheats**, the existing package button changes to
`Kokain-Paket fallen lassen` once story level 20 is completed. It can drop another
package after consumption and does not advance the story. Before that milestone
the same button continues to drop weed.

## Editing and validation

- Shared controller and Inspector durations: `scripts/props/WeedPickup.gd` and
  `scenes/props/WeedPickup.tscn`.
- Cocaine model wrapper: `scenes/props/CocainePackage.tscn`; imported assets are unchanged.
- Music multiplier: `COCAINE_SPEED` in `scripts/main/ThemeMusic.gd`.
- Hint2 placement: edit its existing node in `scenes/rooms/EmptyHospitalRoom.tscn`.

Use `tools/weed/prepare_validation.ps1` to create an isolated project with
redirected saves and Steam disabled. Run `res://tests/cocaine_reward_test.tscn`
through the Godot MCP owned render job with completion marker
`COCAINE_REWARD_TESTS: PASS`. Rendering uses Dummy audio off desktop.

The final cocaine render suite passed **52 checks**, including real picked
input, story gating, failed-save rollback, separate consumption histories,
repeat admin drops, pause/expiry/scene exit, and preservation of Hint2's authored
pose and size. The weed regression suite passed **53 checks** headlessly.
Earlier checks in this implementation also passed save slots (174) and
settings/cheats (33). No script or shader errors occurred in the final runs;
full-scene suites still report the existing ObjectDB leak warning at exit.

Both asset contracts pass. The standalone cocaine model contains **4 nodes,
1 mesh, 2,512 triangles and 1 material**. The shared pickup contains **13 nodes,
2 meshes, 4,656 triangles, 2 materials and 1 box picking shape**; only one model
is visible at a time. No lights or particles were added. The real tabletop
clearance remains below 8 mm. Construction joins and navigation are not
applicable to this nonblocking pickup.

Native front, back, left and right captures, table drop/landing/hover, fades,
admin UI and Hint2 from the real hospital turning anchor were visually reviewed.
The hospital review turns the test camera 180 degrees from the slot machine;
it does not move the hint. Captures, timestamps, scene modification times,
luminance diagnostics, short frame samples, audits and final run logs are in
[validation/cocaine-reward/](validation/cocaine-reward/). The frame samples are
local observations, not exported-build benchmarks. Live Steam and exports have
not been tested.
