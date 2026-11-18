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
for the battle instance. The existing event-block badge continues to show its
own remaining turns.

`Card3D` owns gameplay state and updates `CardCombatIndicators`, which handles
only presentation. Poison application and ticking now use card methods so the
display updates at the same combat boundary as the state. Curse's transient
penalty is included in network and stolen-card snapshots. Repeated snapshots of
unchanged card data update combat state without rebuilding the artwork or
restarting seal animations. Initial snapshots and stolen-card redraws hide
already-spent seals immediately.

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
