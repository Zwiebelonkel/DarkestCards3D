# Secret rarity and difficulty rewards

Secret is the eighth rarity, above Exotic. `usb_stick`, `cigarettes` and
`moewenmilch` each have a live 3D room as artwork. `dman` uses a normal static
image, with 20 attack and 20 defense and no innate effects.
`developer` and `missing_texture` use Exotic again. Existing copies retain
their instance IDs, Holo state and upgrades; display and deck data resolve
the current rarity from the catalog.

## Acquisition

The slot-machine room has a physical text panel beside the return door, on
the door-facing wall (side 2). Click its field, enter `dman`, then press Enter
to discover DMAN once per save slot. Case and surrounding spaces are ignored.
Escape or an outside click releases keyboard focus; typing does not trigger
room turns or journal shortcuts. The shared camera focuses the wall panel.
The card and permanent discovery history are saved atomically before the
same physical Secret reveal used by the three prop discoveries plays.
Re-entering the code, reloading or losing the card cannot repeat the reward.
DMAN is excluded from packs and the Jester reward pool. Its artwork currently
uses `assets/cards/images/dman_placeholder.svg` until the supplied image arrives.

The panel is authored in `scenes/props/SecretWallInput.tscn`, including its
mesh, viewport, focus marker and editable controls. A shared VCR font theme,
muted green text, command prompt and blinking caret provide a restrained
terminal appearance.

Throwing matching table props discovers each card once per save slot, after
50 USB throws, 80 cigarette throws or 150 can throws. Counts persist between
rooms and sessions; repeated input on the same already-thrown prop does not count.
Completing the Jester offering grants one of the three Secret cards. These
cards have `random_reward: false`, so ordinary packs cannot award them, even
when the rarity cheat selects Secret. With no eligible Secret in the catalog,
ordinary pack weights normalize to 100%; the journal displays those effective
base odds without a Secret line.

The generic reward machinery still supports future random-eligible Secrets.
Its configured base weights remain Basic 0.001%, Ultra 0.005% and God 0.01%,
shared across eligible Secret cards, with a small relative Lucky Coin boost.
These configuration values do not make the current discovery-only cards
eligible. Synthetic fixtures verify exact boundaries and exhausted-pool
behavior. A Secret-only catalog cannot start a normal paid pack.

World-discovery keys still respect `random_reward: false` and remain excluded.
The forge still ends at Exotic. Secret copies appear as protected inventory
and cannot be consumed or produced by fusion. Collection and journal rarity
lists include Secret.

The per-card rarity material enables a smooth, ten-second rainbow cycle around
the front rim. Other rarities retain their existing outline. Holo and special
auras remain independent, face-down stacks expose no rainbow, and death
dissolution removes the rim along with the card. Secret pack reveals play
their dedicated `assets/sounds/SFX/secret.mp3` audio asset.

## Match rewards

| Difficulty | Factor | Win coins / XP | Draw coins / XP | Loss coins / XP |
| --- | ---: | ---: | ---: | ---: |
| Easy | 0.5 | 5 / 50 | 2.5 / 25 | 1 / 13 |
| Normal | 1 | 10 / 100 | 5 / 50 | 2 / 25 |
| Hard | 1.5 | 15 / 150 | 7.5 / 75 | 3 / 38 |
| Insane | 3 | 30 / 300 | 15 / 150 | 6 / 75 |

XP rounds to the nearest whole point before existing permanent bonuses;
fractional coins remain cent-accurate. Boost remainders still persist. Separate
level-up bonuses are not multiplied by difficulty. Difficulty is captured when
the AI match starts. Online matches always use Normal, spectators earn nothing,
and the existing once-per-match award guard remains in place.

The difficulty buttons show base win rewards; journal pages explain the
probabilities and reward rules in all five supported languages.

## Verification

Run in an isolated project copy with every production script's `user://` save
path redirected to `res://test-user/`, never against player saves.

- `secret_reward_test.tscn`: authored rarity/pack exclusions, exact synthetic
  weights, deterministic interval boundaries, relative luck, exhausted pools
  and unique unlocks.
- `dman_secret_test.tscn`: wall projection, keyboard focus and shortcuts,
  saved single award, profile isolation, failed saves and the shared reveal
  using ordinary image artwork; rendered captures include the wall and card.
- `difficulty_rewards_test.tscn`: all outcomes, fractional payouts, boosts,
  save/reload, actual AI lifecycle, duplicate awards and online roles.
- `secret_visual_test.tscn` with Forward+: actual cards and rim images,
  hue movement, front/back masking, material reuse, Holo, aura and dissolve.
- `secret_integration_test.tscn`: persistence, upgrades, deck/network, forge,
  collection row, reveal audio, rejected purchase and translated menu/book.
- Regression coverage includes progression rewards/economy, fusion, pack
  quantities, collection scrolling, match features and journal localization.

The collection-scroll fixture waits for the catalog-dependent entrance stagger
instead of assuming a fixed 0.85 seconds for every future collection size.
