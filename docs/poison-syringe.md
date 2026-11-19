# Poison and healing injection

A successful poison application now presents the existing syringe model from
`assets/effects/syringe/adrenalin.glb`: 0.30 seconds to puncture the card, 0.40
seconds to press its separate `kolben`, then 0.30 seconds to pull upward and
disappear. Total visible lifetime is 1.0 second. It never delays combat or
turn progression. The established poison sound begins at the puncture and may
finish after the model disappears.

The source model, atlas and lit materials are unchanged. The reusable effect
scene orients its original +Z needle downward, offsets the needle tip to the
origin, and leans the model for the overhead camera. Only the plunger translates
into the barrel; the needle stays planted during that stroke. The effect follows
the target's current table position. Confirmed death cancels and hides the syringe
synchronously before the death flight. A lethal hit saved by Last Stand keeps
the injection running; freeing the target also cancels it immediately.
Match clear and online cinematic retirement remove all active injections.

`GameTable._present_poison_application` is used by the authoritative attack
resolver and both primary/additional online impact presenters. Existing impact
deduplication and per-duel poison tracking prevent repeated syringes from duplicate
packets or multi-strikes against one target. A later application can inject again.
Blocked hits, zero-damage hits and periodic poison ticks do not inject. Periodic
ticks keep the original `Poison.tscn` effect. Loading snapshots does not inject.

The same injection now accompanies every positive actual HP gain through
`GameTable._present_healing`, including regeneration, each healed neighbor and
the Heal event. Lifesteal and revival gains use the same shared presentation.
Full-health/zero-gain heals, strength-only particles and snapshots do not create
an injection. The existing reliable healing event creates one local syringe on
receiving fighters/spectators; normal sequence and instance checks reject
duplicates, stale turns and effects for a replaced card. Popup preferences do
not suppress the syringe. The legacy `_poison_syringes` list owns both types,
so death, freed targets, match clear and online retirement share cleanup.

Each poison or healing injection samples a private local yaw from 0 to TAU in
`play_on`. Rotating the whole effect about the planted tip preserves the original
inclination, puncture point, model scale, plunger movement and one-second timing.
Yaw stays fixed during that injection. Table/card gameplay RNG and network state
do not include or supply this cosmetic rotation.

The asset has six nodes, two mesh instances, three surfaces/materials and 172
triangles. It adds no lights, particle emitters or collision. The manifest and
`docs/validation/poison-syringe/asset_audit.json` record its bounds and budget.

Validation: `poison_syringe_test.tscn` covers 38 checks; the production combat
effect audit covers 283 checks. Rendered captures show each phase on the real
table and front/back/left/right detail views. For comparison, the room's flicker
is held at its authored base energy and startup blur finishes immediately; no
new lighting is added. The review report includes luminance checks and short
30-frame before/after samples. Player saves and the running editor are untouched.
The headless fixture still emits the existing ObjectDB warning on exit, with no
script/engine errors. Live Steam multiplayer and exported builds were not tested;
fighter/spectator impact presentation was checked locally.

The healing/yaw extension has 55 focused checks in
`tests/healing_syringe_test.tscn`. The existing poison suite passes 38 checks,
the production combat audit passes 283, and the event-card suite passes 132.
Current results live in `docs/validation/healing-syringe/`. Twelve rendered views
show an actual regeneration injection in all phases, four diagnostic directions
and four explicit quarter-turn yaw examples. Cardinal details temporarily hide
occluding characters; match-camera views retain them. The original room light
is used, with flicker fixed to base energy and startup blur finished. The render
and structural audit exit without engine errors; short matched 30-frame samples
are recorded after the original regen particles finish.

The focused remote tests cover healing packet replay, wrong-card/stale-turn
rejection, snapshots and disabled popup settings. In a fresh isolated fixture,
the larger local ENet suite passes its Heal cases but still fails three Switch
flight/barrier assertions. A matching fresh run with healing injections disabled
has the same three Switch failures. These are recorded in `network-fresh-run.json`
and `network-without-heal-injection-run.json`, not counted as a passing full
network suite. Earlier reused-fixture runs also hit opening-state/Piss failures;
fresh fixtures isolate those from the injection change. Live Steam multiplayer
and exported builds were not tested.
