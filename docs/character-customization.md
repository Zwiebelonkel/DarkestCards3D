# Player character customization

Open **Charakter erstellen** from the main menu. Upper arrows cycle hats;
lower preview arrows cycle faces. The separate mouth row cycles **Kein Mund**
and every imported mouth. **Augen- und Mundfarbe** opens the shared RGB picker. The
preview updates immediately. **Übernehmen** saves; **Zurück** or Escape
discards the draft. Closing the color popup with Escape leaves the editor open.
The footer remains visible in small windows; the preview section can scroll.

The first click on the table's **Mehrspieler** button opens this editor before
the lobby. Cancel/Back or Escape discards the draft and leaves creation
unconfirmed; another click opens it again. Apply confirms creation even with an
unchanged default character and continues directly into the lobby. Confirmation
is saved in `settings.cfg` as `settings/character_creation_completed`, independent
of save slots. Later Multiplayer clicks and new hub instances open the lobby
directly. Applying in the ordinary main-menu editor also confirms creation.
Older settings without the explicit confirmation flag still require Apply once.
While the first-time editor is open, the inactive hub is paused; cancel, Apply
and scene teardown release that pause. The editor renders above camera filters.

## Adding faces, hats and mouths

Place 64 x 64 transparent images in these folders and let Godot import them:

- `res://assets/characters/player/faces/`
- `res://assets/characters/player/hats/`
- `res://assets/characters/player/mouths/`

No count or list needs to be edited. `CharacterAppearance.load_catalogue()`
discovers textures through `ResourceLoader.list_directory()`, both in the
editor and in exported PCKs. The editor rescans whenever it opens. Files are
sorted naturally, so `2.png` precedes `10.png`. Counters and wraparound use
the actual catalogue size. Unsupported files and textures with different
dimensions are skipped. Empty folders have transparent fallbacks and disabled
arrows. The mouth selector always includes the empty **Kein Mund** option;
with an empty mouth folder it stays at that option. PNG is recommended;
WebP and other Godot Texture2D formats are supported.

The filename without extension is the saved/network ID. Keep filenames stable
to preserve existing selections. Missing IDs fall back to face `1` / hat
`satan`, or to the first remaining entry if a default was removed. All peers
need matching assets in their game build. Missing, removed or invalid mouth
IDs fall back to no mouth. The current export preset includes
all resources, including dynamically discovered images.

The face, optional mouth and hat canvases are blended at `(0, 0)` in that order,
without separate cropping, scaling or alignment offsets. White pixels in both
the face and mouth use the exact same RGB color; black pixels, alpha and the
hat retain their colors. Source images are copied
before processing. Each composite has a corresponding RGB emission map with
black RGB for black/transparent pixels; emission does not use alpha as a mask.
The texture cache is limited to 16 looks while dragging the color picker.

## Persistence and multiplayer

The appearance is stored in `user://settings.cfg` under
`settings/character_appearance`, independently of save slots and gameplay resets.
The payload contains only `face`, `hat`, `mouth` and six RGB hex digits in
`eye_color`. An empty `mouth` means no mouth and is the default for new
characters and older saves/payloads that have no mouth field.
NetworkManager protocol 7 sanitizes these values during admission and includes
them in the public roster. Hidden decks are not included in that roster.

The accepted opponent look is used by the table sprite and voice portrait,
including muted, speaking and loud states, hover, laugh, death and results.
These supplied templates are single-frame characters; existing cinematic
motion, sound and portrait shake continue, while Satan animation sheets cannot
replace the chosen identity. A disconnect during results preserves the last
accepted look through the final shot. After a win, the defeated avatar keeps
its look during knockback; the replacement switches to the original Satan
texture, animation frames and material while hidden below the scene, before
rising. After a loss, the same swap occurs behind the fully opaque blackout,
before wakeup and the reveal. Late roster updates cannot restore the departed
avatar while the multiplayer exit handshake is still pending. A new match
enables the selected avatar again. The lobby previews both fighters; spectators receive both looks and
see both portraits.

The microphone test shows the saved local avatar, including face, hat, optional
mouth and shared RGB color. Its composite remains a single static image in
idle, speaking and loud states; voice-level translation/rotation shake remains
active. Stopping the test resets the shake while retaining the local avatar.
Saving a character refreshes existing settings previews immediately; opening
settings also reloads the local appearance. Connected opponents never supply
the microphone-test avatar.

## Verification

`tests/multiplayer_character_creation_test.tscn` passed 28 checks in a rendered
run: actual Multiplayer button input, repeated cancel/Escape, unchanged-default
Apply, immediate lobby continuation, persistence/restart/slot independence,
legacy settings, duplicate clicks, input blocking and scene teardown. The
existing avatar (1,182 headless checks with the current asset catalogue), startup
settings and multiplayer-exit suites are also checked for regressions.

`tests/character_customization_test.tscn` runs against isolated saves using the
existing match-feature runner. With the current nine faces, eight hats and two
mouths plus the no-mouth option, 535 checks passed in the Godot 4.4.1 Forward+
render run. They cover all
216 combinations, including every mouth in two RGB colors, pixel alignment,
shared eye/mouth tinting, legacy no-mouth migration, non-emitting black bodies, bounded
caching, folder discovery, empty folders, persistence, selectors, responsive
layout, actual Main/GameTable integration and three local ENet peers using the
production roster RPC. Microphone preview checks inject deterministic voice
levels into both listening and monitoring states to verify that the image
stays static, the local identity is used, and shake continues and resets.
They do not start real microphone capture. Source images remain unchanged.

`tests/multiplayer_character_exit_test.tscn` passed 77 checks in a rendered run
of the actual win/loss cinematics
for host and guest, plus disconnected exits. It checks the selected opponent
at the shot, the hidden skin swap, the standard Satan before rising/reveal,
late roster updates during the pending session, and avatar restoration through
the next real match setup. The existing multiplayer-exit and offline-skip
suites passed as well (290 offline-skip checks), along with the 528-check
headless avatar suite. These are isolated local tests; live Steam was not run.

The headless microphone suite (101 checks), menu localization suite (55),
startup/settings suite (30), main-menu emission, multiplayer exit and network
role suites also passed. Reused fixtures must complete/reset their isolated
PlaytimeManager encounter so its short test timer cannot cover the UI.
The engine reports ObjectDB instances at shutdown in these fixture runs.

`tests/run_character_catalogue_export_test.ps1 -Godot <engine.exe>` creates a
small separate project, exports a real PCK, then starts directly from that
PCK outside the source project. It verified all nine faces, eight hats and two mouths
and composed every combination. This checks catalogue discovery in an export;
it does not verify a complete game export or live Steam connectivity.

Review captures are in `docs/validation/character-customization/`. The editor
captures retain the menu filters. Table/lobby captures disable the two
full-screen camera filters for visibility and skip the unrelated startup blur.
