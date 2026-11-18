# Steam achievements

`scripts/autoload/AchievementManager.gd` is the central registry and Steam
interface. It is registered as the `AchievementManager` autoload after
`NetworkManager`; the former placeholder's `class_name` was removed to avoid
colliding with the singleton name.

## Steamworks setup

Create and publish these ten achievements for App ID **5412220** in Steamworks.
The API names must match exactly. The manager's names and descriptions are
suggested display text; Steam's overlay uses the display text, translations and
icons configured in Steamworks. No Steamworks backend changes or icons have
been published by this implementation.

| API name | Suggested name | Unlock condition |
| --- | --- | --- |
| `ACH_FIRST_COMMON` | Common Ground | Obtain the first Common card. |
| `ACH_FIRST_UNCOMMON` | A Little Uncommon | Obtain the first Uncommon card. |
| `ACH_FIRST_RARE` | A Rare Find | Obtain the first Rare card. |
| `ACH_FIRST_EPIC` | An Epic Find | Obtain the first Epic card. |
| `ACH_FIRST_LEGENDARY` | A Living Legend | Obtain the first Legendary card. |
| `ACH_FIRST_MYTHIC` | Beyond Myth | Obtain the first Mythic card. |
| `ACH_FIRST_EXOTIC` | Something Exotic | Obtain the first Exotic card. |
| `ACH_FIRST_SECRET` | A Well-Kept Secret | Obtain the first Secret card. |
| `ACH_SATAN_PISS` | Pissed Off | Start Satan's stream (currently two clicks). |
| `ACH_SATAN_JUMPSCARE` | Too Close for Comfort | Start Satan's jumpscare (currently four clicks). |

The game uses `mythic` for Mythic and `exotic` for Exotic. Each rarity is an
independent unlock: acquiring a higher rarity does not grant lower rarities.

## Triggers and persistence

The manager listens to `CollectionManager.collection_changed` and checks
committed discovery history. Packs, fusion (including intermediate auto-fusion
rewards), Black Market purchases and special rewards use this existing commit
signal. Rolling or displaying an uncollected card does not grant an achievement.
Failed acquisition saves do not publish a change. Events and unknown card IDs
are excluded. Existing ownership and recorded historical ownership are checked
at startup and when another save slot is loaded.

`Main.gd` connects the actual stream's `emitting_changed(true)` signal and the
jumpscare's `started` signal. Rejected clicks and cancelled attempts that never
start an effect cannot award an achievement. Duplicate triggers are ignored.

Unlock timestamps are written atomically to `user://achievements.cfg`, outside
the three save slots. Starting or deleting a slot does not reset achievements.
This local file belongs to the installation's Godot user-data profile and is
shared across its slots; it is not partitioned by Steam account. Steam grants
are sent to the currently initialized account.

## Steam synchronization

The manager reuses NetworkManager's Steam initialization and callback pump.
GodotSteam 4.22 has no `requestCurrentStats`: stats are available after Steam
initialization ([GodotSteam maintainer explanation](https://github.com/GodotSteam/GodotSteam/discussions/851)).
`getAchievement` reads existing Steam ownership at connection. Pending local
unlocks call `setAchievement` followed by a batched `storeStats`; only a
successful `user_stats_stored(game_id, result)` callback confirms the batch.

Offline unlocks remain local and are retried on connection and each launch.
Rejected sets/stores, failure callbacks and missing callbacks retain pending
work, with retries every 30 seconds. New unlocks arriving during a store wait
for the next batch. No Steam reset or clear API is called.

Public methods: `unlock(id)`, `is_unlocked(id)`, `get_achievements()`,
`sync_pending()`, `record_satan_stream(emitting)` and `record_satan_jumpscare()`.
Signals: `achievement_unlocked(id)` for the first local unlock and
`achievement_synced(id)` for confirmed queued uploads.

## Verification

Run with isolated saves and native Steam initialization disabled:

```powershell
./tests/run_collection_tests.ps1 -Scenes achievement_manager_test,satan_stream_test,satan_jumpscare_test
```

The manager suite checks all eight rarities through real collection commits,
preview/duplicate rejection, failed-save retry, existing collection backfill,
cross-slot persistence, restart recovery, native method/signal availability,
and a fake Steam backend covering synchronous and asynchronous store failures,
batching and callbacks for another app. The existing Satan suites check both
achievement hooks through the real effects and input flow.

Live Steam overlay unlocks and exported builds require a separate test after
the ten matching definitions have been published in Steamworks.

Local validation: 58 manager checks, 23 stream checks and 52 jumpscare checks
passed (133 total). The full-scene Satan suites still report ObjectDB instance
leaks at exit; neither suite reported script errors.
