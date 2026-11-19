# MDMA reward validation — 2026-11-18

This folder records the initial package implementation. The later grave puzzle
and slower/lower music are validated in [../grave-name-puzzle/](../grave-name-puzzle/).

Godot 4.4.1, Vulkan Forward+, AMD Radeon RX 7600. Owned off-desktop jobs,
Dummy audio, isolated saves and Steam disabled. Existing editor/game processes
were left running.

| Suite | Checks | Result |
| --- | ---: | --- |
| MDMA rendered interaction, sequence and cleanup | 59 | PASS |
| Weed regression | 53 | PASS |
| Cocaine regression | 40 | PASS |
| Repeat-package/pump gate regression | 12 | PASS |
| Save slots | 174 | PASS |
| Settings/cheats | 72 | PASS |
| MDMA model asset contract | — | PASS |
| Shared pickup asset contract | — | PASS |

The final MDMA render had no script, shader or engine errors and no stderr.
Older full-scene regression suites retain their ObjectDB cleanup warning.
An initial attempt to run two save-mutating regression suites concurrently used
the same isolated profile; that attempt was discarded. Both suites passed when
run separately. The checked-in reports and captures describe the final MDMA run.

The supplied model has 4 nodes, 1 mesh, 2,512 triangles and 1 material.
The shared pickup has 22 runtime nodes (including the four audio children),
3 resident meshes, 7,168 stored triangles, 3 materials and 1 primitive picking
box. Only the currently selected package is visible. No lights or particles
were added. Runtime checks place the mesh above the real tabletop with less
than 8mm clearance. It is nonblocking; navigation and construction joins do not
apply.

All eleven final images were inspected at native resolution: four isolated
cardinal views, falling, landed, hover, fade-in, full effect, fade-out and expired.
The existing texture, bag proportions and yellow interaction outline fit the
neighboring packages. The rose/amber haze and soft halation are distinct from
the previous filters; the scene returns to its base appearance on expiry.

The actual audio completion signals produced indices **0,1,2,3,4,0,1**, matching
Pablo/front, Trinity/right, Stuart/behind, Hannah/left, separator/center and the
next loop. The source follows the current camera. Pause freezes both playback
and the effect clock. Expiry, admin replacement and scene exit stop the audio
and remove only the owned filter. This is runtime/timing and 3D-position evidence,
not a listening test or a headphone HRTF validation.

The matched 30-frame samples were 15.58ms mean / 16.84ms p95 with the effect and
16.66ms mean / 16.99ms p95 with the overlay hidden; each reported 44 3D draw calls.
These short samples show no obvious local regression and are not a performance
guarantee or an exported-build benchmark. Canvas passes are not represented by
the 3D draw-call count.

See `review_report.json` for timestamps, camera transforms, luminance diagnostics,
playback events and raw frame samples. Asset budgets and loaded geometry are
recorded in `model-audit.json` and `pickup-audit.json`. Exported builds, live
Steam and subjective sound were not tested.
