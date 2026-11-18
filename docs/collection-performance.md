# Collection acquisition performance

Adding a pack previously saved and published the entire collection separately
for every card, then destroyed and recreated every displayed 3D card. Display
lookups also scanned all owned instances for each displayed card type, copied
all matching instances and sorted their Holo preference again. Unrelated loaded
stations refreshed alongside the pack even when the player was elsewhere.

## Changes

- `CollectionManager.add_card_instances()` stores a pack with one identity index,
  one atomic save and one change notification. Its result distinguishes storage
  failure from an already-collected or otherwise empty batch. Single-card
  acquisition uses the same path. Storage failures restore previous ownership
  and discovery metadata before returning; the pack keeps its revealed cards
  and allows another collect attempt.
- Collection refreshes reconcile existing nodes by card ID. New types create
  new nodes; losing the last copy removes only its node. Other cards retain
  their transforms, input connections and row scroll offsets. Changes in Holo
  identity or shared upgrades update the existing card. NEW badges also refresh
  correctly when a retained node is used by another profile.
- Bulk display lookup selects one representative per requested type in one
  pass, preferring the first owned Holo copy. Deck bulk lookup preserves stable
  Holo-first occurrence order. No persistent cache can become stale after a
  profile reload, fusion or legacy migration.
- Saves use compact JSON with the same schema and atomic replacement. The
  upgrade wall ignores changes involving only ordinary combat cards. The fusion
  workbench delays pending inventory rebuilds until it can be interacted with.

## Local measurements

Measured on 2026-11-13 with Godot 4.4.1, Windows, Vulkan Forward+, Radeon RX 7600,
5,000 owned instances across 89 combat card types. Each row times the synchronous
operation, not an entire frame or an FPS average. The previous source was copied
before changing production scripts; both versions used isolated test saves.

| Operation | Before | After |
| --- | ---: | ---: |
| Initial creation of the collection | 1,310 ms | 867 ms |
| Refresh without changes | 1,254 ms | 17 ms |
| Store five rolled pack cards | 322 ms | 57 ms |
| Refresh after acquiring those cards | 1,137 ms | 26 ms |

Headless measurements also fell from approximately 915–1,047 ms per refresh to
20–26 ms. Initial scene creation and the single durable save still scale with
collection size; the fix removes repeated full rebuilds and repeated saves.

## Validation

`tests/run_collection_tests.ps1` copies code into a temporary project, redirects
all player persistence to its `test-user` directory and uses the existing
transport-free network fixture. Imported art is shared without launching an
editor or reimporting assets. Test logs remain in the printed temporary directory.

```powershell
.\tests\run_collection_tests.ps1 -Godot 'C:\Users\Luca\Desktop\Godot_v4.4.1-stable_win64.exe' -Scenes collection_performance_test,holo_cards_test,secret_collection_refresh_test,collection_filter_test,collection_new_label_test,collection_scroll_test,collection_interaction_test,collection_discovery_test,card_fusion_test,auto_fusion_test,auto_fusion_workbench_test,upgrade_wall_collection_test,upgrade_room_collection_test,wall_collection_focus_test
```

The listed suites passed during local verification. The performance suite also
passed with actual 3D rendering. It verifies one save and one notification per
pack, persisted identities, duplicate replay, write failure and retry, detached
display values, Holo selection, node reuse, new types, last-copy removal and
preserved scroll/pose. The Holo integration suite additionally blocks a real
pack's save, checks that all revealed copies remain available, and retries.

The wall focus regression now compares the physical node count with the owned
wall entries instead of assuming seven cards: the fixture also owns an access
key. Existing shutdown resource warnings remain, including the ObjectDB warning
seen in the unchanged baseline. Live Steam sessions and exported builds were
not tested for this change.
