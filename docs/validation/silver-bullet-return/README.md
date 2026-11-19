# Silver Bullet return dialogue — 2026-11-18

| Suite | Checks | Result |
| --- | ---: | --- |
| Silver Bullet return, rendered | 68 | PASS |
| Holy Water return regression | 71 | PASS |
| Crucifix return regression | 85 | PASS |

Tests used an isolated project with redirected saves, disabled Steam, Dummy audio
and owned off-desktop Godot 4.4.1 jobs. No script, shader or engine errors were
reported; the existing ObjectDB cleanup warning remains on full-scene exit.

The real graveyard-to-hub return starts the conversation only after acquiring
the Silver Bullet. The camera faces and slightly approaches Satan, music pauses,
and travel/turn input stays locked. The three exact German lines are tested in
order, with actor laughter and laughing text only on part three. Live switching
among all five languages refreshes each line. Completion restores music, camera,
lens, turn state and inward-facing arrival direction without consuming cards or
currency. A second return and a profile reload cannot replay the scene.

Backend checks cover no item, unrelated story items, training, failed-save retry,
independence from Holy Water/Crucifix flags and fresh-profile reset. Holy Water
and Crucifix still laugh only in their own fourth part. Their original scene
flow and saved gates pass unchanged.

All three captured dialogue parts were inspected at native resolution. Normal
lines remain readable in the existing panel. Part three shows Satan's laughing
face and red wobbling text without clipping. Audio state/timing was checked with
the silent driver; this is not a subjective listening test. Live Steam and
exported builds were not tested.
