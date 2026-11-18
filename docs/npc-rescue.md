# NPC liberation

Fresh profiles introduce only `angelImprisoned` behind Satan. The four NPCs at their
normal locations stay hidden and their interactions remain blocked until freed.
The transforms and animations authored in Main are preserved.

The first Story victory frees the Angel and enables the upgrade machine. Before
that victory its display is completely black, with no screen input, preview,
stat/effect purchase or effect removal. Every rescued NPC receives a one-time
greeting when the player first reaches that NPC's station. Winning alone does
not start the greeting or change the player's room/view.

The Angel greets the player on the collection side, the Dealer at his shop, the
Jester at the graves, and the Prisoner at the close Crypt viewpoint. Pending
greetings wait until room travel/turning, matches, other dialogs, key animations
and menus have finished. The Angel explains the upgrade machine; the Dealer
explains daily offers and Soul Coins; the Jester asks for a Chick and Harald;
the Prisoner laughs, farts and laughs again with his SFX sound.

Each greeting smoothly moves the camera toward the face, narrows the lens,
opens the small voiced dialog, then returns to the exact previous lens transform
and FOV. The room/turn rig and authored NPC transforms stay intact. Hover-focus
camera motion hands over without snapping and resumes afterward. Navigation,
journal, pause, keys and station actions stay blocked throughout both camera
moves and the dialog. `npc_intro_approach_duration` and
`npc_intro_return_duration` on Main configure the camera timing.

Finding a key does not spawn an NPC. Activating `black_market_access` queues
`DealerImprisoned`; activating `graveyard_key` queues `jesterImprisoned`. They
stay hidden during the key/door reveal. Only after the player turns back to a
settled view of Satan do they rise slightly from below/behind the table and
gradually fade into view. The fresh Angel uses the same entrance. Multiple
arrivals are slightly staggered; turning away afterward does not hide them.

The next successful Story victory commits the rescues but keeps the table
copies present throughout the result screen and pre-shot victory sequence.
`GameTable.win_shot_fired` starts their sideways departure exactly when Satan
is shot. Actors on Satan's left move left, actors on his right move right, with
a delayed fade-out. Their normal station sprites appear after departure.
The loss shot never dismisses them. Skipping the victory sequence before or
after its shot finishes pending departures and cleans up all animation tweens.

When the Jester leaves, `PrisonerImprisoned` is queued next. His entrance waits
until the victory camera finishes and the player is looking at Satan again.
The Prisoner requires another Story victory. Training, multiplayer/ordinary
wins and losses never free NPCs. Replaying a won Story level can free a waiting
NPC. `imprisoned_reveal_duration` and `imprisoned_departure_duration` on Main
configure the animations; authored positions/orientations/scales are preserved.
Only the imprisoned copies receive private alpha-blended materials for fading.

The Dealer's board shows a closed sign until he is freed. Purchases, Jester
offerings and the Prisoner's item exchange also validate rescue state in the
collection backend. Room access from keys is independent of NPC services.

`GameCurrency` saves `story.rescued_npcs` and
`story.npc_rescue_intros_pending` together with the Story rewards in the same
atomic currency save. A failed save rolls back the rescues and rewards together.
An interrupted introduction stays pending across restarts until its dialog and
return camera move finish. Revisits and later Story wins do not queue it again.
Save slots keep separate progress; resetting a profile clears rescues. For older
profiles without rescue metadata, an already completed Story level preserves
Angel/machine access. Other NPCs require a new Story victory after key activation.
The former `angel_rescue_intro_pending` field/API remains compatible. Saves from
the Angel-only introduction version retain that Angel state and queue greetings
for already-freed Dealer/Jester/Prisoner NPCs on their next station visit.

## Validation

Use `tools/documentation_audit/prepare_test.ps1 -Suite npc_rescue_test` to prepare
an isolated copy, then run `res://tests/npc_rescue_test.tscn` through Godot MCP.
Completion marker: `NPC_RESCUE_TESTS: PASS`. Add `--full-victory` to cover the
complete victory exit instead of the skip path. `--failed-save` injects an
expected write error and verifies rollback. Render mode writes captures for the
first round, black upgrade monitor and Angel introduction to the isolated copy.

`npc_rescue_intro_test.tscn` exercises all four real station visits, face framing,
navigation locks, exact camera restoration, separate pending/completed flags,
revisits, save reload, save slots, translations and an interrupted approach.
Marker: `NPC_RESCUE_INTRO_TESTS: PASS`. Render mode also writes four face/dialog
captures named `npc-intro-angel.png`, `npc-intro-dealer.png`,
`npc-intro-jester.png` and `npc-intro-prisoner.png` in the isolated project.

Local validation: all 128 introduction checks pass headlessly and in Forward+
render mode, including interrupted camera movement. The rescue suite passes
47 checks; dealer dialogue passes 36 and screen input passes 154. Rendered
face/dialog captures are in `docs/validation/npc-rescue/`. Test shutdown still
reports existing ObjectDB/resource cleanup warnings in some suites.

`npc_prisoner_animation_test.tscn` covers the actual key-door animations,
turn-triggered entrances, partial opacity/rising, result-screen holding, the
real unskipped Satan shot, both departure directions, the Prisoner successor,
loss-shot isolation, skipping before/after the shot, profile reset and reload.
Marker: `NPC_PRISONER_ANIMATION_TESTS: PASS` (55 checks). Forward+ captures of
arrivals and departure are in `docs/validation/npc-rescue/imprisoned/`.
The existing offline-exit suite also passes all 290 checks.
