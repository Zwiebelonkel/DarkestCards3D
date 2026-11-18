# Story level 7 weed reward and pump puzzle

After a saved victory in **story level 7** (or later), the supplied `weed.glb`
bag falls from above the hub table, bounces once and rests on the right side,
clear of the mode buttons. The drop waits until the match has exited and the
idle offline table is available. Player level, ordinary matches and training
do not unlock it. Older saves that already completed story level 7 receive the
unclaimed reward too. After completing story level 20, the shared pickup selects
cocaine instead; see [cocaine-reward.md](cocaine-reward.md).

Hovering the landed bag adds the game's yellow outline. A left click commits
consumption, hides the bag and starts a **60-second** psychedelic camera effect.
The existing `lsd.gdshader` supplies distortion and color cycling, with **5 seconds
of smooth fade-in and 5 seconds of fade-out** within the 60-second duration.
A dedicated 24 dB low-pass on Master fades logarithmically from 20 kHz to
1200 Hz and back. `Main/Hint1` fades with the visual effect. Its material uses
`hint1.png` as the colored emission map at energy 3, with transparent background
and alpha blending for smooth fades. The supplied sheet has five 75-by-75 frames,
showing up, down, down, up, down with a moving white highlight. The hint sits to
Satan's left so the wider clue is clear of his sprite and the level board;
its orientation and shading are preserved. At expiry the overlay, high cut and
Hint1 are removed together. Pause freezes the timer; leaving the scene cleans
up the owned audio effect immediately.

While the effect is active, `theme4cursed.mp3` replaces `theme4.mp3` with a
0.3-second crossfade. `scripts/main/ThemeMusic.gd` plays both looping arrangements
in one synchronized stream, changing only their mix so switching does not
restart the music. Expiry crossfades back over the same duration. The existing
music volume, pitch, room filtering and cinematic fades apply to both layers.

After unlocking, the regular pickup returns after **every saved match victory**
(normal or story), until the pump puzzle has been completed. Losses, draws and
XP-only changes do not queue a new package. A new victory replaces any still
staged package; pending drops persist across reloads. Discovering Klopapier
permanently stops automatic weed drops, including after the card is exchanged.
An already staged package is removed immediately when the puzzle is solved.
The admin button still permits manual testing after completion.

Eligibility is committed with the
story victory and `GameCurrency.weed_consumed` records the first activation in
the existing `currency.cfg`. Failed saves leave the bag available. Old consumed
rewards remain evidence of a prior trip, while old player-level eligibility is
ignored unless story level 7 was completed. Other audio effects, bus volumes
and gunshot hearing recovery are preserved. Temporary effects do not resume
after leaving the scene.

## Admin button

Under **Settings → Cheats**, `Weed-Paket fallen lassen` queues a fresh package
before story level 20. After that milestone the button becomes
`Kokain-Paket fallen lassen` and selects cocaine.
It falls when the menu is closed and the idle hub is available. This can be
repeated after prior consumption and works before story level 7. It does not
advance story progress. The debug pickup activates the real effect; a weed
pickup counts as a first trip for the pump puzzle. A request from the main menu waits for the
hub; it is not persisted across quitting or a save-slot reset.

## Pump puzzle and Klopapier

After the effect has been activated at least once, set the five basement pump
switches, from left to right, to **up, down, down, up, down**. Each switch still
controls its own yellow/up or green/down lamp. A correct combination before the
first trip grants nothing.
The trip need not still be active when solving the puzzle.

`CollectionManager.claim_pump_puzzle_reward()` validates the gate and combination
and uses the existing atomic card acquisition. It grants exactly one
`toilet_paper` / **Klopapier** special key card and reveals it in front of the
camera. The card is excluded from random rewards, combat decks and fusion.
Discovery history prevents repeat rewards across reloads or loss of the card.
Failed writes permit retrying the solution. A matching state already set before
the first trip is checked on re-entering the cabinet's interaction context.

Klopapier has no door destination. It appears in the key tray once owned and can
be given to the prisoner at the near crypt viewpoint in exchange for the special
Story Cards item **Holy Water / Weihwasser**. Using it consumes one copy; the
exchange and reward are saved together. See [prisoner-dialogue.md](prisoner-dialogue.md).
`toilet_paper.svg` is a code-native pixel icon baked to a native ImageTexture;
`tools/weed/build_pump_reward_assets.tscn` also compiles the edited card/menu CSV
catalogs (cards, menus and game/group labels) in the five existing languages.

## Editing

- Placement: `Main/ScenePivot/GameTable/WeedPickup` in `scenes/main/Main.tscn`.
- Behavior: `scripts/props/WeedPickup.gd` and `scenes/props/WeedPickup.tscn`.
- Duration, fade durations, drop height/speed and high-cut frequency are Inspector properties.
- The imported source model and texture are unchanged.
- `inventory_outline.gdshader` has an optional world-space thickness mode for
  this compressed imported mesh; existing outline users retain their behavior.
- `lsd.gdshader` has an `effect_mix` parameter, defaulting to its old full effect.

## Verification

Prepare an isolated project, then run it with the Godot MCP owned-job tool:

```powershell
./tools/weed/prepare_validation.ps1
```

Use the returned directory as `project_path`, with
`scene_path=res://tests/weed_reward_test.tscn`,
`expected_output=WEED_REWARD_TESTS: PASS`, `timeout_seconds=45`, and
`mode=headless` or `mode=render`. Steam initialization is disabled, all saves
are redirected and render jobs use Dummy audio off desktop.

The final rendered weed/admin suite passed **64 checks**, the pump room suite
**77**, and the puzzle backend **19**. Save slots passed **174**, settings/cheats
**33** and the key tray **87**: **454 checks total**. These include story-victory
gating, real picked input, the real admin button click, fade progress, audio
cleanup, all incorrect pump combinations, failed-save retry, key uniqueness and
collect-only tray behavior. No script or shader errors occurred in the final
runs. Some full-scene suites retain the existing ObjectDB leak warning at exit.

The shared pickup asset now includes both variants: **13 nodes, 2 meshes,
4,656 triangles, 2 materials, 1 box shape, no lights or particles**. Only the
selected package mesh is visible. The bag's final world footprint
is approximately 36 by 50 cm, with about 4 mm tabletop clearance. Native front,
back, left and right views plus actual hub drop, landing, hover and effect views
were inspected. Construction joins and navigation are not applicable.

Reports and captures: [validation/weed-reward/](validation/weed-reward/).
Frame samples compare the same camera and consumed-object state with the
overlay enabled/disabled; they are short local samples, not an exported-build
benchmark. Live Steam and exported builds have not been tested for this change.
