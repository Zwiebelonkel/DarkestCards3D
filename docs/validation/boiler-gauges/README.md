# Boiler gauge review — 2026-11-18

All four basement boilers instance the same static `BoilerGauge.tscn`.
The aged brass housing has a rolled bezel, inset ivory dial, sixty tenth-unit
divisions, seven numbered marks, a high-pressure band, slotted screws and a
recessed numeric display. The raised red pointer includes a counterweight.
Clockwise valve input increases pressure; the pointer follows the same direction.

## Verification

- Rendered real-input boiler suite: **115 checks passed**, including all four
  wheels, clockwise/counterclockwise direction, repeated angle wrap, 0/6 stops,
  immediate reversal, rounding, focus, pause, journal and room travel.
- Rendered puzzle and Jester trade suite: **89 checks passed**, including all
  exact solution values, reward gating, release settlement, trade and return.
- Packed-scene reload and integrated room inspection passed without engine
  errors or structural warnings. Four instances, with two meshes each.
- Asset audit passed: four nodes, two meshes, six surfaces, six materials,
  8,413 triangles; no added light, collider or runtime construction.
- All ten final images in `after/` were inspected at native resolution:
  four isolated sides, oblique bezel, room context, gameplay focus and three
  pressure positions. Dial/bezel overlap, central pivot and rear mounting
  collar pass. The collar overlaps the vessel skin by approximately 17 mm in
  boiler-local coordinates. Navigation and ground-contact gates do not apply
  to this wall-mounted decorative instrument.

## Render cost

Matched 1280×720 captures on the local RX 7600, Forward+, with 60 measured
frames per camera. The existing editor/game remained running; these are local
V-sync-limited observations, not an exported-build performance guarantee.

| View | Average before / after | p95 before / after | Draws before / after |
| --- | --- | --- | --- |
| Room | 16.664 / 16.661 ms | 16.751 / 16.689 ms | 780 / 791 |
| Focused boiler | 16.663 / 16.662 ms | 16.710 / 16.711 ms | 894 / 914 |

Reported render memory increased by 455,930 bytes. Exact camera poses,
timestamps and image luminance are in the two `review_report.json` files.

## Test-run note

The initial puzzle run missed the unrelated Jester tray click (three assertions).
An unchanged rerun passed all 89 checks; the original baseline also passed.
Both attempts are retained. No tray gameplay code was changed. Initial visual
review cleanup occasionally reported an ObjectDB shutdown leak; the review
runner now frees its viewport before exit, and the final render job is clean.

All gameplay jobs used isolated project copies with redirected saves and
Dummy audio. Screenshots were captured off desktop through owned bounded
Godot jobs. Existing editor and game processes were left running. Steam and
exported builds were not tested.
