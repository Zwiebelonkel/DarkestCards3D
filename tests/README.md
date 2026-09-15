# Feature checks

The [basement cat encounter](../docs/basement-cat.md) has a dedicated atomic
save/reward backend runner and `basement_cat_test.tscn` for actual door, D-key,
hover and click input. The integration suite verifies both choices, pauses,
failed-save retry, the shared gun effects, permanent absence and the looping
`catSpare` animation after reload. Use `-QuitAfterFrames 12000` for the visual
suite, which visits the basement repeatedly with fresh scene instances.

Black Market coverage is documented in [black-market.md](../docs/black-market.md).
The dedicated backend runner checks daily offers, direct purchases, profile
isolation and failed-save recovery. `black_market_room_test.tscn` uses actual
pointer input and the shared camera for room travel, board focus, purchases,
upgrade previews and pause/turn/travel locks.

Egg hatching uses the real table death/replacement flow. The dedicated suites
cover the 25% hatch chance, ownership-independent Chick creation in the Egg's
slot, ordinary draws after failed hatches, protection from lethal damage,
unchanged decks, multiple deaths, poison/combat, resets and duplicate removal.
The network suite uses real ENet peers to check authority, shared identities,
in-place hatching alongside normal draws, repeated snapshots and spectator state.

```powershell
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/egg_hatch_test.tscn' -SuccessMarker 'EGG_HATCH_TESTS: PASS' -ImportAssets
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/egg_hatch_network_test.tscn' -SuccessMarker 'EGG_HATCH_NETWORK_TESTS: PASS' -ImportAssets
```

Run from PowerShell with the path to your Godot 4.4.1 executable:

```powershell
./tests/run_progression_tests.ps1 -Godot 'C:/path/to/godot.exe'
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe'
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/card_death_test.tscn' -SuccessMarker 'CARD_DEATH_TESTS: PASS'
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/deck_stack_test.tscn' -SuccessMarker 'DECK_STACK_TESTS: PASS'
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/multiplayer_exit_test.tscn' -SuccessMarker 'MULTIPLAYER_EXIT_TESTS: PASS'
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/network_lifecycle_test.tscn' -SuccessMarker 'NETWORK_LIFECYCLE_TESTS: PASS'
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/upgrade_cost_test.tscn' -SuccessMarker 'UPGRADE_COST_TESTS: PASS'
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/god_pack_unlock_test.tscn' -SuccessMarker 'GOD_PACK_UNLOCK_TESTS: PASS'
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/holo_match_network_test.tscn' -SuccessMarker 'HOLO_MATCH_NETWORK_TESTS: PASS'
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/holo_cards_test.tscn' -SuccessMarker 'HOLO_CARDS_TESTS: PASS' -Visual
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/replacement_network_test.tscn' -SuccessMarker 'REPLACEMENT_NETWORK_TESTS: PASS'
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/card_blood_test.tscn' -SuccessMarker 'CARD_BLOOD_TESTS: PASS' -Visual
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/special_cards_test.tscn' -SuccessMarker 'SPECIAL_CARD_TESTS: PASS' -Visual -ImportAssets
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/collection_interaction_test.tscn' -SuccessMarker 'COLLECTION_INTERACTION_TESTS: PASS' -Visual -ImportAssets
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/eimer_card_test.tscn' -SuccessMarker 'EIMER_CARD_TESTS: PASS' -Visual -ImportAssets
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/lava_effect_test.tscn' -SuccessMarker 'LAVA_EFFECT_TESTS: PASS' -ImportAssets
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/event_cards_test.tscn' -SuccessMarker 'EVENT_CARD_TESTS: PASS'
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/event_cards_network_test.tscn' -SuccessMarker 'EVENT_CARDS_NETWORK_TESTS: PASS'
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/event_cards_visual_test.tscn' -SuccessMarker 'EVENT_CARDS_VISUAL_TESTS: PASS' -Visual
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/pack_foil_test.tscn' -SuccessMarker 'PACK_FOIL_TESTS: PASS' -Visual -ImportAssets
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/pack_quantity_test.tscn' -SuccessMarker 'PACK_QUANTITY_TESTS: PASS' -Visual
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/pack_batch_test.tscn' -SuccessMarker 'PACK_BATCH_TESTS: PASS'
```

Pack quantity checks click the real machine screen through its world-to-viewport
input forwarding. They cover the level-2 unlock, compact red/white controls,
the 41-coin/eight-pack limit, total prices for multiple pack types, dynamic
balance changes, and the existing God Pack lock. Two paid Basic packs then
run through foil tearing, reveal and collection in sequence, charging once
and unlocking the shop only after both are collected. The visual run saves
`pack-quantity-level-1.png`, `pack-quantity-8-packs-limit.png`, and
`pack-quantity-2-packs.png` in the isolated test directory.

Pack batch checks exercise the screen's level-2 guard, invalid and overflowing
quantities, total payment, synchronous signal reentry, sequential foil/reveal/
collection, and the eight-pack purchase with 41 coins. Unused packs still waiting
in the queue are refunded when leaving the screen or loading after interruption;
the pack already handed to the player remains charged. Wallet checks cover atomic
debit and queue persistence, failed saves and retries, exactly-once recovery,
stale reservations after reset, and simultaneous pending slot-payout recovery.

Pack foil checks exercise purchases, progressive tearing, reverse pulls,
release and regrab, focus loss, automatic detachment, reveal, collection and
reset for Basic, Ultra and God packs. They check the deformed grip's real
collision bounds, isolated mesh/material resources, original pack artwork,
single charges and exactly 5/7/10 collected cards. The visual run saves
`pack-foil-<type>-<stage>.png` for sealed, partial, released and detached foil.
The foil follows the camera-projected seam; perpendicular dragging lifts the
free strip. Releasing preserves the tear and lets the strip relax. Tuning lives
in PackOpeningScreen's `Pack Top Drag` / `Rip Physik` inspector groups.

The progression tests use a small temporary project. The match tests copy the
project and its imported assets to a temporary directory, redirect saves there,
and replace the Steam transport with a fixture. Import the project in Godot before
running these match tests. Add `-Visual` to render spectator and 3D visor views
(`level-visor-opening.png`, `level-visor-open.png`, `level-visor-main-menu.png`)
in the printed test directory. The tests never modify the player's saved profile.
Use `-ImportAssets` when testing newly added art; imports run in the temporary copy.

Coverage includes level boundaries, XP overflow, level bonuses, legacy saves,
profile reset, live 3D progress, persistent hinges, fullscreen top-pixel hover,
hinge interaction and removed status labels,
physical coin-clicker input in the main menu and spectator view, persistent
per-click rewards, immediate coin balance, and blocked clicks behind the visor,
exact hundredth-coin accumulation, fractional purchases and legacy balance migration,
role capacities and admission, spectator
departure, spectator board/camera/input, normal client board mirroring, and
duplicate result rewards. Match reward checks cover win/draw/loss coins with
and without a level-up, one combined saved balance, host/client results and
offline game-over checks. These checks do not replace a live four-client Steam test.

Combat regressions cover prompt replacement draws during the full death flight,
resetting both active animations safely, draw origins at the current pile top,
and exact remaining-card stack heights from 100 down to zero. Exit tests cover
deferred and idempotent transport teardown and the host waiting for the guest
to disconnect after both cinematics. Native Steam crashes still require a live
run with both Steam clients; the automated exit tests use a transport fixture.
The replacement-network test uses two real local ENet peers to exercise the
production guest RPCs, queued snapshots, consecutive double deaths, early
replacement draws, and late packets after the retired cards have been freed.
It also injects late battle packets after cinematic cleanup while the transport
is still connected for the exit handshake. Exit checks cover the corresponding
presentation barrier and stale Steam lobby callbacks.

Card blood checks cover isolated BloodMix materials, timed fading and repeated
hits, snapshot preservation, replacement cleanup, shield blocks, counter and
thorns survival effects, poison, and duplicate remote effects. The visual run
saves `blood-clean.png`, `blood-hit.png`, `blood-fading.png`, and `blood-faded.png`.
Card3D's `Treffer-Blut` inspector group controls fade duration (5 seconds by
default), maximum coverage, and color.

Spectators join before the host starts the match. Completed matches award
100/50/25 XP plus 10/5/2 Soul Coins for win/draw/loss. Level-up bonuses are added
on top of those match coins. Level 2 requires 100 XP and grants 25 Soul Coins;
each further level needs 50 more XP and grants 10 more Soul Coins than the last.
The 3D visor's clicker requires ownership of the `clicker` special card. It grants
0.02 Soul Coins plus 0.01 per owned `clicker_upgrade` copy on each left click.
Balances are stored as integer hundredths (`currency/coin_cents`) and displayed
with two decimal places; old whole-coin and fractional saves migrate on load.
Upgrades alone do not unlock the button. The unlock card is obtainable once,
including across cards drawn in the same pack. Existing duplicate unlocks convert
to upgrade copies on load, retaining their instance IDs and total card count.
Both cards are in normal pack pools and are excluded from decks,
AI combat pools, multiplayer payloads and combat upgrades. Their ownership
persists in the existing collection save.

Collection checks cover top-right amount labels, hover after detail close and
navigation, deck-fan transitions, and unavailable deck actions for special cards.

Eimer is an uncommon combat card with 1 attack, 5 HP and the Lava effect, available
in the usual uncommon pack pool. Lava hits every living opposing card on the
board together at attack impact, using normal damage mitigation. Only the
selected defender counters. A multi-strike can hit surviving original targets
again, but never cards drawn as replacements during the same action. Lava does
not add a second Cleave splash. Its standalone upgrade-effect rarity is legendary
because its damage scales with the attack of the card carrying it.

The Eimer card test checks collection/deck and pack availability, upgrade/effect
preservation, artwork and effect-icon loading, plus a real Card3D preview. Lava
combat tests exercise full-board hits, defense effects, simultaneous deaths,
replacement safety and normal single-target combat regressions.

Event checks cover the finite shared logical deck, effect-only draws, Switch identities,
all Strength tiers, legal targets, one event before an attack, two-owner-turn
Block duration, fully blocked passing, Steel replacement and combat-state
preservation, simultaneous and multiple kill triggers, KI ordering, and reset.
The event network suite uses real loopback ENet peers to check private hands,
host validation, mirrored targets, stale/duplicate/spectator requests, and
presentation barriers. The visual fixture checks the hidden event deck and original
match camera, then renders private hand peek/hover, Block badge, public reveal,
and a narrow viewport. Production Steam
transport still requires a live multiplayer check.

Screen input checks use the production upgrade and pack-shop meshes, collision
signals and SubViewports to verify button hover, press and release across a
3-by-3 grid, including after parent rotation and nonuniform scaling. Run with:

```powershell
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/screen_input_test.tscn' -SuccessMarker 'SCREEN_INPUT_TESTS: PASS' -Visual
```

Omit `-Visual` for input-only checks. The visual run also verifies exact CRT
marker bounds at 1000x650 and 1000x720 without a controller script, plus disabled
effect pass-through, and saves `screen-input-crt-*.png` in the isolated test directory.

Room travel checks exercise the standalone hospital door's hover and fixed frame,
camera flights through the two doorways, repeated round trips, A/D alignment in
both rooms, restored hub interactions, and blocked travel during packs, matches,
lobbies and pause. The visual run saves `room-travel-*.png` in the isolated copy.

```powershell
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/room_travel_test.tscn' -SuccessMarker 'ROOM_TRAVEL_TESTS: PASS' -ImportAssets -Visual
```

The reusable scenes are `scenes/props/HospitalDoor.tscn` and
`scenes/rooms/EmptyHospitalRoom.tscn`. The latter is instanced beside the hub in
Main. `scripts/rooms/build_hospital_shell.py` regenerates the textured room shell
with its door opening from the original hospital model; it leaves that model intact.

Starting-hand progression checks cover the five unique special cards, sequential
pack eligibility, duplicate reveal/collection callbacks, exact persisted instances,
resetting all slot unlocks, and exclusion from combat decks and upgrades. The visual
run also saves `starting-hand-cards.png` with all five real card previews.

```powershell
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/starting_hand_progression_test.tscn' -SuccessMarker 'STARTING_HAND_PROGRESSION_TESTS: PASS' -ImportAssets -Visual
```

Starting-hand backend checks exercise saved sparse slot positions, moving and
swapping chosen copies, replacement from the fan, exact duplicate-copy identity,
legacy decks, random gap filling, short decks with a chosen fifth slot, local
initial dealing and validated online preferences. Empty short-deck positions
never create cards or appear as card data in snapshots. UI checks use real mouse
input and Main's shared camera for locked drops, exact target assignment, gaps,
replacement, swapping, removal, reopening, reset/random decks, pause/focus
interruption and a narrower viewport. The visual run saves `starting-hand-*.png`.

```powershell
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/starting_hand_test.tscn' -SuccessMarker 'STARTING_HAND_TESTS: PASS' -ImportAssets
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/starting_hand_ui_test.tscn' -SuccessMarker 'STARTING_HAND_UI_TESTS: PASS' -ImportAssets -Visual
```

Deck fan geometry checks inspect actual even- and odd-card layouts and verify
that the imported card faces remain separated, including the middle pair.

```powershell
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/deck_fan_depth_test.tscn' -SuccessMarker 'DECK_FAN_DEPTH_TESTS: PASS' -Visual
```

Startup checks cover fullscreen defaults and reset while preserving saved windowed
preferences, plus Main's five-second wake blur from 5 to 0.265, pause/resume,
material isolation, scene reentry and interrupted teardown. They also run the
actual death/blackout/reveal sequence, verify the faster 2.5-second wake blur,
repeated wake interruptions and exclusion of the shared win/music reveal.
The visual run saves `wakeup-start.png`, `wakeup-settled.png` and
`wakeup-death-midpoint.png` in the isolated copy.

```powershell
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/startup_settings_test.tscn' -SuccessMarker 'STARTUP_SETTINGS_TESTS: PASS' -Visual
```

Cheat checks exercise the actual paused settings menu, exactly one level per
click with its normal coin bonus, fractional coin balances, save/reload, all five
unique starting-hand unlocks, partially unlocked collections, live deck slot
refresh, and coin grants during a pending slot payout. The visual run saves
`settings-cheats.png`.

```powershell
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/settings_cheats_test.tscn' -SuccessMarker 'SETTINGS_CHEATS_TESTS: PASS' -Visual
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/slot_machine_test.tscn' -SuccessMarker 'SLOT_MACHINE_TESTS: PASS' -ImportAssets -Visual
```

Slot checks cover the four physical buttons, bets, reel symbols and payouts,
plus all five tiers of reward glow, particles and animated payout announcements.
They verify that failed settlements, duplicate callbacks, losses and off-room
wins cannot trigger a reveal, and that leaving or pausing cancels it safely.
Visual captures include `slot-machine-gold-reward.png` and `slot-machine-win.png`.

Secret door-key checks cover silent knife acquisition, unique saved ownership,
exclusion from random rewards and combat, the collection's rendered **Zur Tür**
action, standalone collection handoff, the actual camera/opening sequence,
locked-door bypass prevention, room return, reset and preserved A/D alignment.
Room-travel and slot suites seed an already-used key to test their own features.

```powershell
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/slot_room_key_backend_test.tscn' -SuccessMarker 'SLOT_ROOM_KEY_BACKEND_TESTS: PASS' -ImportAssets
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/slot_room_key_ui_test.tscn' -SuccessMarker 'SLOT_ROOM_KEY_UI_TESTS: PASS' -ImportAssets -Visual
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/key_door_test.tscn' -SuccessMarker 'KEY_DOOR_TESTS: PASS' -ImportAssets -Visual
```

The pinned knife-card check uses the real Main knife, tests its blade/card
intersection, face-down orientation, paper thickness, disabled card picking,
actual mouse throw, shared flight/rotation/hide and unique secret reward.
Visual runs save `knife-card-table.png`, `knife-card-closeup.png` and
`knife-card-flight.png`.

```powershell
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/knife_card_test.tscn' -SuccessMarker 'KNIFE_CARD_TESTS: PASS' -ImportAssets -Visual
```

Upgrade-collection checks separate combat cards and the key from passive
upgrades without changing owned instances, clicker bonuses or starting slots.
The room integration uses Main's actual travel/turn camera and mouse input to
reach every mounted card, inspect details, close with Escape, pause, update
counts while a detail is open, and return to the hub. Captures are
`upgrade-room-wall.png` and `upgrade-room-detail.png` in the isolated directory.
Settings outline checks cover all seven sliders and both checkboxes, including
disabled/checked states, usable track width and actual volume/pitch drags.

Wall-camera checks move the actual pointer over a backing gap, verify closer
framing without oscillation, and animate the actual mounted card to detail and
back without a duplicate or close button. They check intermediate flight poses,
camera/control locks until return completes, rapid close during entry, repeated
close, and preserved card identity across collection refresh. The standalone
wall check also resets the collection during both flights. Pointer exit, pause,
turning, room travel and a return visit to the PackShop exercise camera cleanup.
Visual runs save `wall-focus-before.png`, `wall-focus-focused.png`,
`wall-focus-card-entry.png`, `wall-focus-card-detail.png`,
`wall-focus-card-return.png` and `wall-focus-released.png`.

```powershell
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/collection_filter_test.tscn' -SuccessMarker 'COLLECTION_FILTER_TESTS: PASS'
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/upgrade_room_collection_test.tscn' -SuccessMarker 'UPGRADE_ROOM_COLLECTION_TESTS: PASS' -ImportAssets -Visual
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/wall_collection_focus_test.tscn' -SuccessMarker 'WALL_COLLECTION_FOCUS_TESTS: PASS' -ImportAssets -Visual
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/settings_outlines_test.tscn' -SuccessMarker 'SETTINGS_OUTLINES_TESTS: PASS' -Visual
```

Card-fusion checks cover all six rarity transitions, exact consumed copies,
deck and starting-hand reservations, protected cards, mixed rarities, stale
selections, duplicate callbacks, save failure and reload. The workbench test
uses the real room camera and mouse rays to page, filter, select and fuse
physical cards, pause and return to the hub with current collection counts.
It checks that right-clicking creates no enlarged preview, preserves the
selection and leaves room controls available, and that extra instruction
and consumption text is absent from the workbench.
It also pauses during fusion and unloads Main before the animation finishes,
then reloads the saved reward to check interrupted exchanges.
The visual run saves `fusion-workbench-{overview,selected,reward,empty}.png`.
Use `-ImportAssets` to register the new workbench script in the isolated copy.

```powershell
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/card_fusion_test.tscn' -SuccessMarker 'CARD_FUSION_TESTS: PASS' -ImportAssets
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/fusion_workbench_test.tscn' -SuccessMarker 'FUSION_WORKBENCH_TESTS: PASS' -ImportAssets -Visual
```

Journal checks cover the complete card/event/effect catalogs and game rules without
changing ownership, decks, upgrades, currency, or random outcomes. Integration
uses J/Escape and actual mouse rays to open, browse, and close the physical book
in both rooms and during battle. It checks camera and graphics restoration,
interrupted animations, blocked world input, and real incoming online attacks
while reading. The visual run writes `journal-*.png` in the isolated copy.

```powershell
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/journal_content_test.tscn' -SuccessMarker 'JOURNAL_CONTENT_TESTS: PASS' -ImportAssets
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/journal_test.tscn' -SuccessMarker 'JOURNAL_TESTS: PASS' -ImportAssets -Visual
```

Localization coverage validates all five UTF-8 CSV columns, formatting placeholders,
scene captions, native Godot imports, language persistence and live language changes.
The world test checks pack quantity, selected upgrades, forge inputs, currency and
card state, and writes screenshots of the pack and upgrade screens in each language.
Card and journal tests also measure translated text against the actual 3D surfaces.

```powershell
python -X utf8 tests/audit_localization.py --scenes
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/localization_ui_test.tscn' -SuccessMarker 'LOCALIZATION_UI_TESTS: PASS' -ImportAssets
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/localization_table_test.tscn' -SuccessMarker 'LOCALIZATION_TABLE_TESTS: PASS' -ImportAssets
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/card_localization_test.tscn' -SuccessMarker 'CARD_LOCALIZATION_TESTS: PASS' -ImportAssets
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/model_localization_test.tscn' -SuccessMarker 'MODEL_LOCALIZATION_TESTS: PASS' -ImportAssets
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/journal_localization_test.tscn' -SuccessMarker 'JOURNAL_LOCALIZATION_TESTS: PASS' -ImportAssets
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/world_localization_test.tscn' -SuccessMarker 'WORLD_LOCALIZATION_TESTS: PASS' -ImportAssets -Visual
```

Catalog structure and authoring rules are documented in [localization.md](../docs/localization.md).

Damage-number checks exercise actual local attacks, counters, thorns, multiple
strikes, lava, cleave and poison, including armor, blocked hits and lethal damage.
They verify mirrored clients and spectators, duplicate and stale packet rejection,
snapshot updates without replay, and cleanup when the match ends. Numbers show
the damage taken; a completely blocked hit displays `0`.
Settings coverage also verifies that disabling numbers immediately clears active
popups while paused, preserves combat and blood effects locally and online, and
does not replay old hits when numbers are enabled again.
The visual test checks the 3D pop, blink, rise, separate simultaneous numbers and
fade without changing card state. It saves `damage-number-flash.png`,
`damage-number-blink.png` and `damage-numbers-simultaneous.png` in the isolated copy.

```powershell
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/damage_numbers_test.tscn' -SuccessMarker 'DAMAGE_NUMBERS_TESTS: PASS' -ImportAssets
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/damage_number_visual_test.tscn' -SuccessMarker 'DAMAGE_NUMBER_VISUAL_TESTS: PASS' -ImportAssets -Visual
```

Presentation preferences default to enabled and persist independently. Settings
tests cover existing config files, save/reload, reset, live checkbox updates and
all five translations. Turn-arrow tests use Main and real pointer events to
check edge visibility, click-only rotation, both rooms, modal input locks and
the retained A/D controls. The arrows render beneath the existing lens and CRT
filters and disappear when their setting is disabled.

```powershell
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/presentation_settings_test.tscn' -SuccessMarker 'PRESENTATION_SETTINGS_TESTS: PASS' -ImportAssets -Visual
./tests/run_match_feature_tests.ps1 -Godot 'C:/path/to/godot.exe' -TestScene 'res://tests/turn_arrows_test.tscn' -SuccessMarker 'TURN_ARROWS_TESTS: PASS' -ImportAssets -Visual
```
