# Jester offering

The existing visible `jester` sprite and the named `Grave_27` (Chick) and
`Grave_28` (Harald) remain in the instantiated Graveyard room. On its west view,
hovering the shared station moves the existing Main camera closer, using the
same focus controller as the shops. Each station registration is scoped to its
room so another room's surface cannot steal the hover.
The Jester gently bobs 0.06 units above and below his placed height over a
2.8-second cycle, while the station's camera focus and click areas stay fixed.

Clicking the Jester swipes the dialog panel up from the bottom of the screen and
opens the authored dialog as four individual, localized sentences. Only the
first sentence is placed in the text field and typewrites initially. A click
while a sentence is still typing reveals only that current sentence. Once it is
complete, the next click clears the field and starts the next sentence; this
repeats through sentence four. Only a further click after the fourth completed
sentence swipes the panel back down and closes the conversation. The Jester uses
Satan's loss-laugh audio on the SFX bus with its pitch variation shifted six
semitones higher while text appears. The voice stops when the current sentence
finishes, is skipped, or the dialog closes.
Each completed sentence plays `sentenceEnd.mp3` once. Text reveal and the laugh
pause until that cue finishes. Skipping unfinished text plays one ending cue;
closing the conversation stops both sounds.
A left click anywhere, inside or outside the panel, reveals unfinished dialog
text or advances exactly one completed Jester sentence; it cannot reveal later
sentences or close before the fourth sentence has been read. The NPC dialogs
have no buttons.
Clicking either named grave previews one owned copy of its requested card.
The card flies up from below the viewport alongside the dialog panel, using the
same 0.24-second cubic easing. It arrives at the existing review position and
keeps its size, orientation and exact instance identity. Confirmation remains
disabled until the entry finishes, so its flight cannot conflict with sacrifice.
The offering dialog contains two localized buttons: **Opfern** (Sacrifice) and
**Nicht opfern** (Do not sacrifice). Only Sacrifice commits the reviewed exact
copy; Do not sacrifice closes without changing collection or save data.
Clicking text or outside the panel does neither and cannot reach the world
behind the modal. When no eligible copy is available, Sacrifice is disabled;
Do not sacrifice and Escape can still close the explanation. The buttons are
hidden during ordinary conversation, sacrifice animation and reward receipts.
An available normal copy is preferred over Holo; deck and starting-hand instances are protected, with
an explanation when the card first needs to be removed from the deck.

The first offering persists. Completing both grants one of the three Secret
combat cards: USB-Stick, Zigaretten or Möwenmilch. These discovery cards are
eligible here even though ordinary random rewards exclude them. The exact
rolled instance and optional Holo finish are granted once per
save slot. Consumption, progress and reward are written together through an
atomic collection snapshot. A failed save retains the input card and previous
progress. Repeated callbacks cannot duplicate the reward. Type upgrades and
unrelated collection metadata remain intact.
The reward records its discovery too, preventing a later click on the same
table prop from granting another discovery copy. Developer and Missing Texture
are Exotic and no longer belong to the Jester's reward pool.
A left click anywhere can also close the offering animation or received-reward
presentation. Closing those views leaves the already committed offering and
reward intact.

Progress lives under `collection.metadata.jester_offering`, with `offered`,
`completed` and `reward_instance`. It resets with its save slot and survives
room changes, scene reloads and interrupted cosmetic reveal animations.

Dialog and card preview hold the camera and block turning, travel and the
journal. Escape closes the interaction; pausing also closes the presentation
and restores the camera. Names, dialog, offering states and both buttons use the
five existing localization languages. This adds no room-discovery hints to the
journal or global HUD.

Validation scenes must run in an isolated project copy with all `user://`
production save paths redirected to `res://test-user/`:

- `jester_offering_test.tscn`: ownership, exact copies, protected decks, Holo,
  saved progress, one-time reward, reentrancy, rollback and slot isolation.
- `jester_station_test.tscn`: NPC dialog, explicit buttons, ignored text/outside
  clicks, disabled choices, exact-copy guards and synchronized card entry.
- `jester_focus_test.tscn`: real Main door travel, camera hover, named-grave
  clicks, real button input, five-language screenshots, card/dialog entry,
  pause and return.

Run the focus scene with Forward+ to capture the actual NPC, dialogue,
offering preview and Secret reward.

Validated 2026-11-15: 86 station checks, 76 rendered Main/focus checks and
49 offering/backend checks passed. No script or shader errors. Station/focus
jobs emitted ObjectDB cleanup warnings at shutdown. Captures of entry and all
five localized button layouts are in `docs/validation/jester-sacrifice-buttons/`.
The fixture now waits for the existing panel swipe to finish before asserting
closed state or reopening, instead of assuming an instantaneous close.
