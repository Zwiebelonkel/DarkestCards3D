# Boiler puzzle validation — 2026-11-17

Godot 4.4.1, isolated project copies with redirected saves and fake networking.
Unrelated greeting/playtime encounters were disabled in the regression fixture;
the new puzzle suite explicitly suppresses the global playtime encounter.

| Suite | Checks | Result |
| --- | ---: | --- |
| New puzzle and Jester trade, rendered | 69 | PASS |
| Existing boiler input, focus and travel | 91 | PASS |
| Existing Prisoner trade | 25 | PASS |
| Existing Jester offerings | 49 | PASS |
| Existing cocaine reward | 40 | PASS |
| Existing repeated packages, rendered | 12 | PASS |

All 286 assertions passed. No final run reported script or shader errors.
Some existing full-scene checks report an ObjectDB leak warning at exit.
The headless repeat-package run additionally reported a resource still in use
at shutdown; its rendered run passed without that resource error.

Visually reviewed:

- [Jester Eye reward](jester-eye-reward.png): correct name, image and description.
- [Item tray at the Jester](jester-eye-tray.png): both eye and toilet paper,
  with the action hint for the locally usable eye.
- [Crucifix reward](crucifix-reward.png): correct name, image and Story Card
  description; remains visible during the camera's station refocus.

Completion and consumed-item history survive reload. Failed saves leave both
sides of a transaction unchanged. Existing saves are compatible; no new wallet
field is required. No live Steam or exported-build validation was performed.

## Crucifix return sequence

The first return with the Jester's Crucifix now plays a separate Satan
conversation about the cross. Merely obtaining the eye leaves this sequence
pending. Its flag is independent of the Holy Water sequence.

- `crucifix_return_test`: 74 checks, zero failures; rendered and visually reviewed.
- `holy_water_return_test`: 60 checks, zero failures; original sequence preserved.
- Updated `boiler_puzzle_test`: 70 checks passed, including real eye acquisition,
  return without a cross sequence, Jester trade and subsequent Crucifix return.

The dialogue contains no reference to the eye. All four sentences were checked
in all five languages. Camera position, lens, music, laughter, input locks,
one-time persistence, training and failed-save retry were verified. The full
scene runs retain the existing ObjectDB leak warning on shutdown and report
no script or shader errors.

[Crucifix return dialogue screenshot](crucifix-return-dialogue.png)

## Locked graveyard and settled pressures

The updated puzzle fixture starts with only basement access, the graveyard
locked, and the Jester imprisoned. All four boilers are set through actual
pointer drags from 2.8, ending with boiler 4. Releasing a valve settles its
internal value to exactly the displayed tenth. The final release callback is
deliberately disconnected: the independent settled-state check still grants
and saves the eye. Only the subsequent Jester exchange is blocked until his
rescue. The fixture then unlocks the graveyard, rescues him and verifies the
trade and Crucifix return sequence.

- Updated puzzle suite: 86 checks passed headlessly, including the missed
  callback. The rendered run preceding that extra assertion passed 88 checks.
- Existing boiler interaction suite: all 91 assertions passed. Its headless
  shutdown reported the existing ObjectDB/resource-in-use warnings.

No script or shader errors were reported. Player saves were inspected read-only;
all automated game input used isolated copies and redirected test saves.

## Returns face away from the entrance

Ordinary hub returns and both item sequences now finish facing into the hub,
opposite the entrance used: basement → pack shop, graveyard → game table.
The position remains the usual hub turning center. The turn index, target
angle and active side are updated together so subsequent A/D turns agree
with the visible direction.

The fixtures deliberately leave while facing the collection, then verify
the destination depends on the return entrance, stability during idle
frames, a normal turn away and back, and a later return without a dialogue.
The normal room-travel suite also performs two complete round trips under
the new rule.

- Basement item return: 81 checks, rendered.
- Graveyard Crucifix return: 81 checks, rendered.
- Graveyard Holy Water return: 67 checks, headless.
- Normal room travel: 71 checks, headless.

All 300 checks passed, with no script or shader errors and the existing
ObjectDB exit warning. The final [pack shop view](basement-return-packshop.png)
and [game table view](graveyard-return-table.png) were visually reviewed.
