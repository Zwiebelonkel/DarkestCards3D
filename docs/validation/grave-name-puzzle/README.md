# Grave-name puzzle / MDMA music validation — 2026-11-18

Godot 4.4.1, Forward+ Vulkan on AMD Radeon RX 7600. Tests used owned off-desktop
render/headless jobs, Dummy audio, isolated saves and disabled Steam.

| Suite | Checks | Result |
| --- | ---: | --- |
| Grave puzzle, real input and reward render | 56 | PASS |
| MDMA pickup, playback, slower/lower music and cleanup | 60 | PASS |
| Existing boiler puzzle / story rewards | 86 | PASS |
| Existing cocaine reward | 40 | PASS |
| Existing weed reward, fresh isolated profile | 53 | PASS |
| Save slots | 174 | PASS |

The grave and MDMA render runs had no script/shader/engine errors and empty
stderr. The older regression suites retain their known ObjectDB cleanup warning.
The weed suite requires a fresh fixture: reusing a profile after the boiler
suite leaves the pump's acquisition history on disk and intentionally suppresses
weed. The accepted run uses a new isolated project/profile.

Backend checks reject all **255** incorrect four-click combinations, incomplete
or overlong sequences, claims before MDMA use, training and duplicate rewards.
A failed save leaves the collection unchanged. Actual viewport input proves
four distinct grave hovers, low-pitch click recordings, both repeated-name and
distinct-name wrong attempts, the name-finished → separator → retry sequence,
pause, real room travel and the animated Silver Bullet reveal. Reload preserves
first use and one-time discovery. Solving stops ordinary MDMA drops/requeues.

The original graves' positions, rotations and inscriptions were compared with
the authored scene at runtime and are unchanged. Scene inspection finds the
four named graves without warnings. No scene geometry, navigation, lighting or
physical blocking was added; only four picking areas with mesh-fitted primitive
boxes and conditional material overlays are created by the controller.

All six captures were visually inspected at native size: the real grave row,
one yellow hover outline per grave, and the Silver Bullet story-card reveal.
The localized title, silver ammunition icon and description fit the existing
card layout. The underlying dark graveyard lighting is preserved.

MDMA music now reaches exactly **0.85 × the prior pitch/speed** at full strength
and returns to the exact prior value on expiry. The clue recordings retain their
own playback rate. Playback timing, pitch properties and source positions were
tested silently; subjective sound, headphone localization, live Steam and
exported builds were not auditioned/tested.

The broad card-localization suite remains failing with **129 existing failures**
both before and after this change: before 129/4663, after 129/4697. The comparison
restored the original card catalog and compiled translations in the isolated
copy only. Failures concern existing dman/event catalog entries and effect
presentation checks. The added Silver Bullet rows introduce no new failures;
its name/icon and Story Card classification also pass the focused suite.

`review_report.json` records grave capture times/camera transforms; `mdma-review.json`
records the latest MDMA playback and frame observations. Logs include the accepted
focused/regression runs and both localization comparisons. The baseline restore
and all test writes were confined to isolated copies.
