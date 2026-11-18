# Boiler puzzle and Jester trade

Set the basement boilers to **1: 3.4, 2: 5.1, 3: 5.8, 4: 1.8** and use the
cocaine package at least once. The first-use flag is permanent; the visual
effect does not need to be active. Both conditions can be fulfilled in either
order. Training cannot grant the reward.

The pressure shown to one decimal place is what counts. The actual numbered
nodes are used, independently of their scene-tree order. The puzzle is checked
after releasing a valve and on entering an available boiler view, so rewards
do not interrupt a drag. Valve settings remain local to the current scene.

Turn a valve clockwise (right) to increase pressure and counterclockwise (left)
to decrease it. All four boilers share `scenes/props/BoilerGauge.tscn`: a stepped
brass bezel, ivory 0–6 bar dial with tenth-unit divisions, a tapered red pointer
with counterweight, and a recessed numeric readout. The pointer follows the
printed 270-degree clockwise scale. Regenerate the static instrument with
`tools/boiler_gauge/build.tscn` in render mode; only the pointer and digits move
at runtime. The readout uses two animated number drums: tenths roll continuously,
with a mechanical carry of the whole-number drum through 9 → 0, in either
direction. On release the drums seat at the exact rounded tenth used by the
puzzle. The short seating animation also finishes during pause. The shared
digit atlas is baked into the scene; there are no live counter viewports.

Valve release now settles the internal pressure onto exactly the displayed
tenth. The main scene also observes settled settings and first-use/training
state changes, so a missed or temporarily blocked release callback does not
leave a valid solution unclaimed. An unchanged failed state is not saved
repeatedly every frame; changing a setting or revisiting an available view
allows another attempt.

The one-time reward is the legendary special card **Jester Eye** (German:
**Jester-Auge**). Its acquisition history is saved, so consuming or losing it
cannot reset the puzzle. A failed save leaves the reward available to retry.
Neither unlocking the graveyard nor rescuing the Jester is required to obtain
the eye. The rescue requirement applies only to the later Crucifix exchange.
As with the weed/pump puzzle, ordinary cocaine drops stop once the eye has been
discovered. The explicit admin drop remains available.

The first return to the main room after receiving the Crucifix plays a separate
Satan conversation, using the Holy Water sequence's camera approach, music
pause, input locks, voice and final-sentence laughter. Satan reacts to the
cross, doubts its protection and tells the player to keep it. The dialogue
never mentions the eye. Afterward the camera returns to the normal hub
position and lens, facing into the room away from the entrance used to
return: basement → pack shop, graveyard → game table. The same direction
applies to ordinary returns without a dialogue. Its turn state is synchronized
with that arrival view, so subsequent A/D turns start there.
Music resumes. The saved `crucifix_return_dialogue_seen` flag is
independent of `holy_water_return_dialogue_seen`; both conversations remain
available if both items were discovered. Owning only the eye does not trigger
this sequence. Failed flag saves leave it pending for a later
return. The dialogue is translated into all five game languages.

At the rescued Jester's station in the graveyard, hover the bottom edge to open
the existing card tray and click the eye. The eye is consumed and exactly one
**Crucifix** (**Kruzifix**) is saved in the same transaction. Pause, dialogue,
turning away, the crypt viewpoint and being in another room block this action.
The usual card reveal shows both rewards.

The Crucifix belongs to **Story Cards**, alongside Holy Water. Both new cards
are excluded from combat and random packs. The eye behaves like Toilet Paper
in the tray; the Crucifix stays in the collection. No further use is assigned
to the Crucifix here. Names, descriptions and tray guidance support all five
game languages.

Implementation: `scripts/autoload/CollectionManager.gd`, `scripts/main/Main.gd`,
`scripts/ui/AccessKeyTray.gd`, `data/cards.json`. Native pixel icons are rebuilt
with `tools/weed/build_pump_reward_assets.gd`.

Checks: `tests/boiler_puzzle_test.tscn` exercises the gate, every individual
wrong setting, display rounding, atomic failed-save recovery, NPC gates,
real tray input, reward reveals, history and save reload. Use an isolated copy
with redirected saves, as for the existing pump/prisoner suites. Marker:
`BOILER_PUZZLE_TESTS: PASS`.

`tests/crucifix_return_test.tscn` exercises actual graveyard return travel,
the new dialogue in every language, camera/audio restoration, one-time state,
failed saves, training, profile independence and the separate Holy Water flag.
The existing `holy_water_return_test.tscn` verifies the original conversation.

Validation on 2026-11-17: the rendered puzzle/trade suite passed 69 checks.
The existing boiler (91), prisoner trade (25), Jester offering (49), cocaine
reward (40) and repeat-package (12) checks also passed. Screenshots and logs:
[validation/boiler-puzzle/](validation/boiler-puzzle/). The new card reveals
follow the camera while station focus moves. Exported builds and live Steam
were not part of this validation.
