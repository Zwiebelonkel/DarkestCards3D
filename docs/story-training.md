# Story and training modes

The table offers **Story**, **Training**, and the existing **Multiplayer** button.

Both selectors live on a framed physical board on the table. The board's surface
uses an embedded viewport, as the upgrade machines do; there is no fullscreen
setup overlay. Level tokens are raised 3D pieces.
The complete board slides in from the left and exits to the left over 0.32 seconds,
keeping its content visible until the exit finishes. Its camera target stays fixed.
Mouse rays project clicks, scrolling, dropdowns and number entry onto the board. The shared `ScreenCameraFocus`
controller moves to its camera marker. Back and match start cancel any remaining
focus tween and restore position, orientation and the standard field of view.

## Story

- 100 levels in a scrolling path. At most ten level buttons intersect the viewport, including partial rows while scrolling.
- Only level 1 starts unlocked. Winning level N unlocks N+1 and changes that connection to a solid line. Completed levels can be replayed.
- Uses the existing AI, combat cards, effects, opening hand, event cards, and normal deck size.
- Enemy decks progress from common cards to a mix of increasingly rare real combat cards, retaining their innate effects. At level N, each card has `1 + round(0.95 × (N − 1))` attack and `3 + round(1.9 × (N − 1))` defense. Growth is 5% gentler, from 1 attack / 3 defense to 95 attack / 191 defense at level 100. Player upgrades never affect these templates.
- Rarity percentages interpolate between the milestones below. Evenly spaced quantiles allocate the mix to the requested deck size, making replays consistent and rarity thresholds nondecreasing as levels rise. Combat shuffles the deck before dealing. Secret discovery cards, events and special cards are excluded; missing rarity pools are removed before normalizing.

| Level | Common | Uncommon | Rare | Epic | Legendary | Mythic | Exotic |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 100% | 0% | 0% | 0% | 0% | 0% | 0% |
| 20 | 55% | 35% | 10% | 0% | 0% | 0% | 0% |
| 40 | 20% | 35% | 30% | 15% | 0% | 0% | 0% |
| 60 | 5% | 15% | 30% | 30% | 20% | 0% | 0% |
| 80 | 0% | 5% | 15% | 30% | 30% | 15% | 5% |
| 100 | 0% | 0% | 5% | 15% | 30% | 30% | 20% |

- Each victory grants `50 + 10 × (N − 1)` XP and `5 + (N − 1)` coins before existing permanent bonuses. Replays grant the same rewards. Draws and losses grant nothing.
- Completion and rewards are saved together in the active slot's `currency.cfg`, under `story/completed_level`. Old saves default to zero completed levels. Slot switching and reset use the existing profile lifecycle.
- A failed save rolls back both rewards and completion. The result screen offers another attempt through Exit. Duplicate result callbacks cannot pay twice.

## Training

The game has one saved battle deck. Select five distinct copies from that deck; their saved identities, Holo state, upgraded stats, and combat effects are retained. Then configure five opposing slots from the combat catalog or as training cards. An empty or short player deck must first be filled in the collection.

Training cards allow integer attack from 0 to 1,000,000 and defense from 1 to 1,000,000. They are temporary combat dictionaries, never catalog or collection entries. Defense is the existing HP stat. Opposing real cards use their native catalog stats and effects.

Both sides deal exactly five combat cards with no initial reserve. Existing combat effects, transformations, stolen cards, and event cards keep their usual behavior. Restart restores the configured cards. Leave returns to the mode menu immediately.

Training targets always show actual damage popups, even when ordinary damage numbers are disabled. A log on the table retains the last five hits, including zero damage and poison. The target number remains stable if an event moves a card. Restart and leave are physical buttons between the two card rows.

No outcome grants XP, coins, story progress, collection cards, or other persistent rewards. Manual and passive clicker income is suspended during configuration and combat. Leaving or destroying the table releases the suspension, without accruing income for the elapsed training time.

Online transport, RPCs, combat resolution, and reward amounts are unchanged. Online startup clears local setup state and training suspension.

## Verification

The focused `story_rarity_test.tscn` suite checks all 100 levels at deck sizes 1,
5 and 20, rarity progression, native effects, unchanged stats/catalog, repeatable
decks and invalid inputs. It passed 13,105 checks on Godot 4.4.1. Run it through
the isolated runner below with `-TestScene 'res://tests/story_rarity_test.tscn'`
and `-SuccessMarker 'STORY_RARITY_TESTS: PASS'`.

```powershell
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/offline_modes_test.tscn' -SuccessMarker 'OFFLINE_MODES_TESTS: PASS' -ImportAssets -Visual
```

The isolated test covers all level strengths, locks, saves, slot switching/reset, failed saves, projected mouse-wheel input, keyboard deck selection, both setup steps, upgraded and native effects, real damage, unchanged profile files during training, restart, and host/client reward isolation. Camera tests check position, rotation, field of view, and tween release when leaving or starting matches during focus transitions. Screenshots are written to the printed temporary project directory. A live two-client Steam session is still needed to verify the external Steam service end to end.

Validation on Godot 4.4.1: the rendered offline suite passed 2,299 checks. Screen input, fusion workbench, journal content, offline exit, and network lifecycle suites also passed. The wall-focus suite still expects seven cards although its fixture creates eight distinct cards; its three count assertions fail. The minimal progression runner lacks existing SaveSlots, CardUpgradeManager, EventDeck, and cat-image dependencies and cannot compile. These broader fixture limitations are separate from the passing offline suite.
