# Event Block pinning knife

The former blue `BLOCK` label is replaced by the existing table knife from
`assets/environments/props/knife/knife.glb`. On a new block, the knife flies into
the selected card over 0.28s, settles for 0.16s, then remains completely still.
At the end of the second completed owner turn it pulls out and fades over
0.28s. Opposing turns do not age the block. The effect has no collision or input
Areas and does not delay gameplay. No additional RPC or replicated field is
needed: the existing `event_block_turns` state owns its lifetime on every peer.

The final pose follows the supplied reference: almost upright, with an 8/10
degree lean and its measured blade tip at card-local `(0.10, 0.05, -0.30)`, well
below the card/table surface. The shaft crosses the printed card face inside
the card footprint. Its original model/materials are preserved. The model's
world scale matches `GameTable/decortaions/knife`, accounting for the decoration
group's 1.405 scale as well as the knife's 0.215 scale; copying only the latter
would make it too small. The standalone default scale is therefore 0.302075.

Refreshing an active block and duplicate snapshots keep the same knife and
current animation. A new block during withdrawal cancels that exit. Stolen or
redrawn cards restore the pinned pose with their remaining duration. The knife
follows card movement, respects hidden stats, and stops immediately on confirmed
death or fresh setup. Existing save/card data and combat rules are unchanged.
The legacy `EventBlockBadge` node name remains for existing callers, but it
contains only the knife effect and no text/background badge.

Validation in `docs/validation/block-knife/` includes 41 focused checks, 106
card-effect unit checks, 127 event-card checks, the event-hand UI suite and the
real local ENet event-card network suite. The focused checks cover exact world-size equality with the
decoration, nearly upright shaft, deep tip penetration, face intersection,
both rows, two-turn release, replay/refresh, reblock during exit, concealment,
restoration and death/reset cleanup. The loaded-scene audit passes: 7 nodes,
2 meshes/surfaces/materials, 688 triangles, no collision, lights or particles.

Nine rendered views show entry, pinned state, one turn remaining, withdrawal,
release and four detail directions on the real Main table. Diagnostic detail
cameras hide occluding character cutouts only; every normal match-camera view
retains the full scene. Lamps are fixed at authored base energy and startup blur
finishes immediately; no extra lighting is added. A short matched 30-frame
before/after sample is recorded, not a general FPS claim. The owned render exits
without engine errors. Headless checks retain the existing ObjectDB exit warning.
Live Steam multiplayer and exported builds have not been tested.

The general card-localization suite still reports 129 failures among 4,663
checks, concerning missing catalog entries and effect title/description
expectations. The pre-change fixture reports the identical 129 failures.
The knife-specific locale/visibility assertion passes; unrelated catalog and
translation expectations were preserved.
