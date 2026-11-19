# Battle seals and status indicators

The three consumable defensive effects (`shield_first_hit`, `last_stand`,
`grave_return`) lose their printed seal as soon as their actual combat charge is
used. Each seal shrinks and fades over 0.32 seconds. Its hover area and its entry
in an already-open effect overview become unavailable immediately. Other seals
keep their original slot. The owned card and shared catalogs are unchanged;
fresh battle setup restores the charges and full-size seals.

Applied statuses appear in a compact row starting at the card's upper-right
corner, using the existing effect symbols:

| Status | Color | Value |
| --- | --- | --- |
| Poison | Green | Remaining owner-turn damage ticks |
| Stun | Yellow | Icon until the next selected attack is skipped |
| Curse | Purple | Attack removed by applied curses |

New statuses pop into view. Expired poison and consumed stun shrink and fade
away; refreshing either during its exit cancels the pending hide. Curse lasts
for the battle instance. Event Block uses an embedded knife for its remaining
owner turns; see `docs/event-block-knife.md`.

`Card3D` owns gameplay state and updates `CardCombatIndicators`, which handles
only presentation. Poison application and ticking now use card methods so the
display updates at the same combat boundary as the state. Curse's transient
penalty is included in network and stolen-card snapshots. Repeated snapshots of
unchanged card data update combat state without rebuilding the artwork or
restarting seal animations. Initial snapshots and stolen-card redraws hide
already-spent seals immediately.

## Swarm Power multiplier

On table cards, Swarm Power appends a smaller orange `×2`, `×3`, etc. to the
printed base attack. A single living copy has no suffix. For example, `2 ×3`
means six outgoing attack damage before other damage modifiers; HP stays
unchanged. As in combat, only identical card IDs count, including living copies
on either side. Different Swarm species do not combine. Counterattack damage
continues to use the base attack.

The table derives the suffix from its current board each frame, using the same
copy-count helper as combat. Only factor changes rebuild the suffix. Draws,
deaths, growth and online snapshots therefore update it without extra network
state or changes to owned cards. The suffix follows the attack number's motion,
adapts its spacing to curses/strength changes, and hides with obscured stats or
the card's death dissolve.

`tests/swarm_power_display_test.tscn` covers one/two/three/ten copies, different
species, current attack changes, hidden stats, local fighter/spectator snapshot
reconciliation, death/refill and Chick growth. Its rendered run captures the
actual match table and closeups in `docs/validation/swarm-power-display/`.

## Validation

`tests/card_combat_indicators_test.tscn` checks actual damage and survival calls,
mid-animation scale/opacity, immediate hover updates, untouched passive seals,
duplicate snapshots, new replicas, theft/redraw, status reapplication during
exit, fresh-battle resets, death during consumption, and the production poison
hit and turn-start paths. The rendered run saves before/during/after images.

```powershell
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/card_combat_indicators_test.tscn' -SuccessMarker 'CARD_COMBAT_INDICATORS_TESTS: PASS' -ImportAssets
```

On 2026-11-17 the rendered focused suite passed 52 checks. The existing
card-effect unit, combat-effect audit, online bodyguard impact, and event-card
suites passed another 509 headless checks. Network coverage exercises local
snapshots and fighter/spectator packet handling; live Steam multiplayer and
exported builds were not tested. Results and inspected images:
`docs/validation/card-combat-indicators/`.
