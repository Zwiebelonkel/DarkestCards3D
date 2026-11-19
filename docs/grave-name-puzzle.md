# Grave-name puzzle and Silver Bullet

The existing graveyard graves are interactive in their authored positions:
`Burials/Grave_Pablo`, `Grave_Trinity`, `Grave_Steward` and `Grave_Hannah`.
`Grave_Steward` corresponds to Stuart in the MDMA clue and uses the supplied
`steward` recording. Names/inscriptions, meshes and materials are preserved;
the authored positions remain unchanged until the puzzle is solved. Main adds
`GraveNamePuzzle` to the room; no replacement graves are built.

Hovering a named grave outlines all its meshes in the existing interaction yellow.
Each grave has one picking Area3D with primitive boxes fitted to its mesh parts.
These shapes do not block walking. Unnamed graves remain scenery. Pause, menus,
room transitions, the crypt close-up and other room modals disable interaction.

Left-click plays that grave's supplied name recording at **pitch scale 0.28**.
Only clicks made after `GameCurrency.mdma_consumed` is permanently saved can
enter an attempt. The visual effect need not still be active. Training cannot
record an attempt or award the card. Input before first MDMA use can play the
low voice and show hover, but cannot build a partial solution.

Each attempt contains exactly **four clicks**, including repeated selections.
The only valid sequence is **Pablo → Trinity → Stuart → Hannah**. A wrong
prefix does not reset early. After the fourth wrong click, the attempt clears;
the final low name finishes, then the supplied separator plays at normal pitch.
Further clicks are blocked during that indicator. Its completion starts a fresh
attempt. Four distinct graves in the wrong order fail just like repeated wrong
graves. A failed reward save follows the same reset path and remains retryable.

Pause preserves an unfinished attempt and pauses current audio. Leaving the
graveyard clears the attempt and stops the name/separator. Reloading the scene
also starts with no partial input. Room turning does not change the name order.

The backend `CollectionManager.claim_grave_puzzle_reward()` checks the saved
first-use gate, exact complete sequence, training and unique acquisition history.
It saves the collection before publishing success. The reward is **Silver Bullet /
Silberne Kugel** (`silver_bullet`), a unique legendary special card in
`card_group: story_cards`, like Holy Water and Crucifix. It has no combat values,
modifiers or access-key behavior and cannot appear in random packs. The existing
story-card reveal presents it in front of the camera. Its icon is a native pixel
SVG baked to `.res`; name, description and flavor text cover all five languages.

Acquisition history prevents duplication even after the owned copy is removed.
It also stops ordinary MDMA packages and later victory requeues. The debug
package button remains available. No card exchange is added.

After the story-card reveal, the two left graves slide left and the two right
graves slide right, then all four disappear. The original ground opens to reveal
a clickable descending staircase to the [underground vault](underground-vault.md).
Silver Bullet discovery permanently keeps this passage open, including in older
solved saves. It does not require the MDMA effect to remain active.

On the first return to the main room after discovering the Silver Bullet, Satan
uses the same camera approach, paused music, input lock and return-facing restore
as the Holy Water conversation. His three lines are **"Was willst du mit dieser
Kugel?"**, **"Hä?"**, **"Für deinen Arsch?"**. The third line starts his laugh
animation/audio and uses the existing red wobbling laughter text. The saved
`metadata.silver_bullet_return_dialogue_seen` flag is independent of Holy Water
and Crucifix and prevents replay after reload or later visits. A failed flag
save leaves the scene pending for another return. Training cannot consume it.
All three lines are localized in the five supported languages.

Implementation: `scripts/rooms/GraveNamePuzzle.gd`, `scripts/main/Main.gd`,
`scripts/autoload/CollectionManager.gd`, `scripts/GameCurrency.gd` and
`data/cards.json`. `tools/mdma/build_assets.tscn` bakes the icon/recordings and
compiles card/menu/game catalogs. The conversation script is
`scripts/main/SatanSilverBulletDialogue.gd`; `tests/silver_bullet_return_test.tscn`
validates the real return, exact lines, third-line laugh, saved gate and cleanup.
Its evidence is in [validation/silver-bullet-return/](validation/silver-bullet-return/).

Validation: `tests/grave_name_puzzle_test.tscn` checks every other four-click
combination, first-use/training gates, failed saves, acquisition history, actual
viewport hover/clicks, reset playback completion, pause, room travel and the
animated reward. Use `tools/weed/prepare_validation.ps1` for isolated saves and
run save-mutating suites separately. Evidence is in
[validation/grave-name-puzzle/](validation/grave-name-puzzle/).
