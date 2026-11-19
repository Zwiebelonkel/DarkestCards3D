# Yellow puddles on concealed card stats

Piss now shows small irregular yellow puddles on the attack and HP fields,
replacing their former question marks. The numeric labels are emptied while
concealed, so no value can show through the shader's transparent edges. The
existing hiding of descriptions, effect icons, status indicators and popups is
preserved. Names and the underlying combat values are unchanged.

`CardStatPuddles.gd` adds two small card-local quads only when a combat card first
needs concealment. A shared per-card shader material draws organic wet-looking
patches with uneven rims, a highlight and detached droplets. Per-instance seeds
come from the card identity and field index, keeping shapes stable through HP
updates, localization changes and repeated snapshots without consuming RNG.
There are no collision/input objects, lights, particles, animations or textures.
The root follows the card and hides immediately on expiry or confirmed death.
An HP update during death cannot reveal it again.

The existing viewer-only `stats_hidden` state controls presentation. The caster
and spectators retain their usual view; the affected fighter sees puddles on
both rows, including newly drawn cards. Passing/ticking the existing two-turn
duration restores the latest attack and HP labels. No RPC, snapshot field, save
data or event rule changed.

Validation: `piss_event_test.tscn` passes 38 checks and `event_cards_test.tscn`
passes 132, including hidden healing, actual stat changes, snapshots, locale
changes, new cards, passing two affected turns, spectator view, cleanup and
death during concealment. Results are in `docs/validation/piss-puddles/`.
Headless checks retain the existing ObjectDB exit warning. The owned rendered
review exits without engine errors and covers normal/covered/restored table
views plus close-ups before and after a hidden HP change. All six images were
reviewed. It uses the real Main scene and match camera; lamp flicker is held at
authored base energy and startup blur finishes immediately. The report contains
short matched 30-frame samples, not a general FPS claim. Live Steam and exported
builds were not tested.
