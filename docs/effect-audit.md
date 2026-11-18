# Combat effect audit

The audit compares the effect catalog and innate card metadata with the actual
`GameTable._resolve_duel` and `_apply_start_turn_effects` execution paths. Deck
Burn and Draw On Kill are retired; legacy data migrates to Draw On Death. The current
catalog has **23 distinct effect types** (Armor has multiple rarity/value rows).

## Runtime coverage

Completed hit effects remain effective when the attacking card dies to the
counterattack or Thorns. Poison already resolves at contact. Stun and Curse
retain their attack-start parameters and apply once to surviving original
targets even after source cleanup. A dying attacker also finishes Cleave before
leaving its slot. Its own death can grant Draw On Death. Healing and
additional attacks require a living source.

`_check_effects_after_attacker_death` covers both sides, lethal counters and
Thorns, visible debuff indicators, actual skipped attacks, poison's next tick,
fully shielded hits, interrupted multi-strikes, Cleave casualties/rewards, and
fighter/spectator snapshot reconstruction. The new cases reproduced 18 failures
before the correction. The corrected audit passes 281 checks; damage numbers
(83), Lava (61), card combat indicators (49), and journal localization in all five
languages (9013) also pass. Evidence:
`docs/validation/card-combat-indicators/attack-effects-after-death.log`.

`tests/combat_effect_audit_test.tscn` uses the real table/card scenes. All listed
groups execute for both player and enemy. Only automatic scheduling of the next
turn is stopped in the test subclass; tests invoke the next turn-start boundary
explicitly. Attack contact animations, damage, death, replacements and event
draws run in production code. Exact zero/one probabilities and fixed random
intervals avoid statistical assertions. No player saves may be used: the test
refuses to run outside the isolated `res://test-user/` fixture.

After effect groups, the real table serializer and slot reconciler reconstruct
both fighter and spectator boards and compare HP, attack, effect metadata,
poison/stun state and consumed defenses. These checks cover reconstruction,
not transport authorization. Existing ENet suites below cover transport and ACKs.

| Declared type | Trigger and parameter contract | Executed audit cases |
| --- | --- | --- |
| `armor` | Incoming ordinary damage; rounded `value` reduction | `_check_defenses`: 10%, 25%, 35%, 50%, 75%; Bodyguard own armor |
| `shield_first_hit` | First positive ordinary hit only | `_check_defenses`: consume once, second hit, zero damage; target shield before Bodyguard |
| `regeneration` | Owner turn start; heal `value`, cap at max HP | `_check_poison_and_regeneration`; capped healing popup in `damage_numbers_test` |
| `poison` | Damaging hit applies `damage` and `turns`; tick on poisoned owner's turn | `_check_poison_and_regeneration`: three actual ticks, expiry, shield rejection; lethal tick in `_check_survival` |
| `lifesteal` | Heal `percent` of actual inflicted HP damage, capped | `_check_attack_modifiers`: overkill; `_check_cleave_and_chain`: includes splash; popup tests |
| `thorns` | Reflect `percent` of damage for each connected hit | `_check_strikes`: two/three reflections and one counter; `_check_revival_damage_records`: reflected damage remains recorded through resurrection; `lava_effect_test` secondary-target reflection |
| `cleave` | Adjacent opposing slots; configured `side_damage`; no friendly/distant splash | `_check_cleave_and_chain`: custom quarter damage, kill-chain and lifesteal combinations |
| `lava` | Full damage to each original opposing card at one contact; selected target counters once | `_check_lava_and_draw`; extensive `lava_effect_test` defenses, death, replacement immunity and remote impacts |
| `double_strike` | Configured `hits`, default 2; counter once | `_check_strikes`, including custom hit count |
| `triple_strike` | Configured `hits`, default 3; counter once | `_check_strikes` and reflection per hit |
| `stun` | Configured `chance`; consumes next requested attack | `_check_on_hit_status`: exact 0/1 probabilities, skipped attack, later recovery |
| `chain_attack` | Confirmed kill grants another actual duel | `_check_cleave_and_chain`: primary kill, splash-only kill, single end-turn boundary |
| `last_stand` | First lethal damage leaves 1 HP | `_check_survival`: ordinary, poison, execute, no second activation; redirected Bodyguard damage |
| `grave_return` | First death restores rounded half max HP | `_check_survival`: ordinary, poison, execute, single-use reconstruction; `_check_revival_damage_records`: low-HP revival retains poison, thorns and redirected Cleave damage |
| `execute` | Target reaches configured HP threshold after damage | `_check_survival`: above/below threshold, both survival types, no second lethal event after same-hit survival; `_check_revival_damage_records`: summed damage and Lifesteal after resurrection |
| `swarm_power` | Multiply by identical living cards on the battlefield | `_check_attack_modifiers`: identical cards on both sides count |
| `draw_on_death` | Actual death grants exactly one shared-pile event to the deceased card owner | `eternal_suffering_test`: ordinary, periodic and sacrifice deaths, no duplicate reward or reward for a kill/survival; `eternal_suffering_network_test`: private reward across ENet |
| `eternal_suffering` | Credit Card alone sacrifices itself on attack; target takes escalating persistent damage until neighbor healing | `eternal_suffering_test`: both sides, defenses, 1/3/5/7 damage, cure ordering, theft and snapshots; dedicated ENet suite |
| `curse` | Permanently reduce target attack by `value` | `_check_on_hit_status`: actual duel, clamp at zero, network state |
| `swap_stats` | Swap initial attack and maximum/current HP on setup | `_check_attack_modifiers`: swapped real hit and health; mirrored snapshot does not swap again |
| `random_damage` | Equal-chance 0.75× / 2× coin, revealed before each strike | Real duel damage audit plus `random_damage_coin_test`: timing, faces, multi-strikes, cancellation and remote presentation |
| `bodyguard` | One living adjacent guard, left before right; takes `percent` of raw hit without recursive sharing | `_check_bodyguard`: adjacency, own armor, protected shield, competing guards, counter, custom percent and lethal survival |
| `neighbor_heal` | Owner turn start heals adjacent allies by `value` | `_check_neighbor_heal`: no damage trigger, no self/distant healing, actual Paramedic and Repair Bot metadata |

The two innate healer descriptions use the same turn-start rule as the corrected
catalog. No new trigger type is introduced. Egg's card-ID-specific death hatch
is outside the effect-type list and remains covered by `egg_hatch_test` and
`egg_hatch_network_test`; those verify actual replacement behavior and ownership.

## Findings and agreed corrections

Source locations below name functions rather than mutable line numbers. The
original line references were sent to the implementation task as findings.

| Finding in original runtime | Agreed correction / regression coverage |
| --- | --- |
| Bodyguard declared but never executed | Shared ordinary-hit routing, target shield first, one adjacent guard, separate mitigation, no redirect recursion |
| Stun always applied, ignoring `chance` | Honor exact probability; boundary tests use 0 and 1 |
| Cleave hardcoded 50%, ignoring `side_damage` | Use declared fraction |
| Strike hit counts hardcoded, ignoring `hits` | Honor explicit count with safe bounds and unchanged defaults |
| Poison bypassed Last Stand and Grave Return | Raw periodic damage retains single-use survival |
| Execute bypassed survival and could immediately kill an already rescued target | One lethal-resolution opportunity per target/hit |
| Blocked or zero-damage attack still poisoned | Require an actual damaging hit |
| Cleave-only kills did not start Chain Attack | Propagate splash kill result |
| Lifesteal ran before Cleave, excluding its damage | Apply after splash using accumulated actual damage |
| Neighbor Heal catalog described damage-triggering while cards and table used turn start | Correct text to the existing, uniform turn-start rule |
| Deck Burn had no gameplay implementation | Remove declaration and replace legacy grants with Draw On Kill |
| Newly factored damage helper measured damage after resurrection | Preserve pre-survival HP loss; resurrection must not erase the hit's damage record |

Bodyguard redirects direct hits, counters, Cleave and Lava. Poison and reflected
Thorns damage are not redirected. Ordinary mitigation and survival belong to
each recipient; a shield on the original target prevents the entire hit before
redirection. Lava snapshots retain original object identities so replacement
cards cannot be struck by a later hit of the same action.

Two existing combination rules are explicitly retained: delayed poison kills
grant no Draw On Kill event, and Cleave splash does not trigger Thorns or other
on-hit effects. Redirected Bodyguard damage likewise does not trigger Thorns.
These are documented exceptions, not missing trigger fixes.
Last Stand reports its net prevented-lethal damage (HP before minus one);
Grave Return reports the HP removed before resurrection, rather than subtracting
the resurrected HP from the original hit. Dedicated integration tests inspect
Bodyguard's additional authoritative impact packets as well as the final states.

## Supporting regression suites

- `lava_effect_test`: real simultaneous impacts, all defenses, multi-hit target
  identity, replacement immunity, lethal counters, remote fighter/spectator
  presentation and interrupted cleanup.
- `damage_numbers_test`: actual reduced/blocked/overkill damage, separate
  reflection/counter numbers, poison and healing, remote impact/event replay.
- `event_cards_test` and `event_cards_network_test`: kill reward ownership,
  event timing, shared pile/privacy, real ENet admission and ACK barriers.
- `egg_hatch_test` and `egg_hatch_network_test`: card-only death replacement.
- `lower_rarity_cards_test`: authored low-rarity parameter values and canonical
  network data; its direct resolver checks alone are not treated as proof of
  table trigger wiring.
- `lava_reward_boundary_test` and `effect_upgrade_cost_test`: acquisition and
  upgrade restrictions, distinct from battle execution of valid metadata.

## Validation status

Verified with Godot 4.4.1 in an isolated copy of the project, with all persistent
paths redirected to `res://test-user/`; player saves were not opened by the tests.

| Executed suite | Result |
| --- | --- |
| `card_effect_unit_test` | PASS, 106 checks |
| `combat_effect_audit_test` | PASS, 237 checks, all 22 effect types on both sides, including Lava/Bodyguard replacement immunity |
| `bodyguard_online_impact_test` | PASS, 78 checks, fighter/spectator contact presentation |
| `deck_burn_migration_test` | PASS, 44 checks, legacy JSON/CFG and network payloads |
| `lava_effect_test` | PASS, 61 checks |
| `damage_numbers_test` | PASS, 83 checks |
| `card_death_test` | PASS, 56 checks |
| `event_cards_test` / `event_cards_network_test` | PASS, 88 local checks and real loopback ENet requests/ACKs |
| `effect_upgrade_cost_test` / `lower_rarity_cards_test` | PASS, 199 / 1,250 checks |
| `jester_offering_test` / `save_slots_test` | PASS, 40 / 174 checks |
| `card_fusion_test` / `journal_profile_test` | PASS, 114 / 143 checks |
| `journal_content_test` / `journal_localization_test` | PASS, 768 / 8,318 checks; all five languages and page layout |

All listed runs exited with code 0. Some existing scene suites still report
Godot resource/ObjectDB warnings during shutdown; no script errors occurred.
The new Bodyguard suite waits for full death-flight cleanup before exiting.
