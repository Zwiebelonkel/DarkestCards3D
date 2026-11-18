# Poison injection

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
