# Swarm Power display validation — 2026-11-18

The isolated headless focused run passed 31 checks. The rendered Forward+ run
passed 36 checks, including five saved captures. Card-effect unit (106), combat
indicator (49), and full combat-effect audit (283) checks also passed.

Reviewed the rendered single/pair/trio and ten-copy closeups and actual match
table: the smaller orange factor sits beside the red base attack, follows its
motion and leaves HP separate. At ten copies, the two-digit factor remains
readable without covering the central effect seal. `2 ×3` means six outgoing
damage before other modifiers, with no suffix at one copy.

Coverage includes distinct Swarm species, copies on both sides, current attack
changes, hidden/revealed stats, language changes, fighter/spectator snapshot
reconciliation, deaths, replacement draws and Chick growth. The multiplier is
derived from the existing combat count and is absent from serialized state.

All successful runs exited with code 0 and no script/engine errors. Each also
reported the existing ObjectDB cleanup warning, including the unchanged unit
and audit suites. Real Steam multiplayer and exported builds were not tested.

Images: `01-single.png`, `02-pair.png`, `03-trio-closeup.png`,
`04-match-table.png`, `05-ten-copies.png`.
