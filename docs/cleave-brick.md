# Local Cleave bricks

Cleave uses the supplied `assets/effects/brick/scene.gltf` as a real local
`RigidBody3D`, one on the primary target and one on each occupied adjacent
Cleave target. Primary strikes and the later adjacent damage retain their
existing combat order. Double/triple strikes retain their existing number of
primary hits. Lava continues to supersede Cleave; ordinary attacks do not drop
bricks. Shielded hits receive a brick without inventing damage or blood.

The body falls vertically from 0.58m above its target with an initial downward
speed of 4.5m/s. Its first physics contact starts the flying blood at the captured
hit position; HP, numbers, card stains and deaths retain their original timing.
A 250ms cosmetic fallback avoids losing the burst if a brick is clicked before
landing or physics is delayed. The body briefly bounces, then freezes in a flat
resting pose after 0.30s, preventing contact-margin jitter. Left click unfreezes
the body and kicks it away from the camera. GUI controls consume their clicks
first, and the brick ray consumes its click before a card underneath can react.

After a 1.8s hold from contact, the existing dissolve shader removes the brick
over 2.0s. Its private material sweeps along the long side in body-local space,
so the breakup is visible overhead and follows a kicked/tumbling body. The
0.50 x 0.12 x 0.24m box collider is aligned to the imported silhouette. A private
table slab at the card plane supports only cosmetic bricks. Bricks do not
collide with gameplay objects, block Areas, affect damage or use gameplay RNG.
There are at most 24 concurrent bricks; match clear and online presentation
retirement immediately hide and free them and their support surface.

Every client and spectator creates its own bodies from the existing combat
presentation. Secondary damage events use `cleave_burst`/`cleave_damage` tags in
the existing reliable effect channel; packet identity/sequence checks prevent
duplicates and late effects on replacement cards. No brick position, velocity,
rotation, bounce, click, dissolve progress or random seed is synchronized or
saved. Protocol version 13 excludes peers that cannot understand these tags.

Validation in `docs/validation/cleave-brick/` includes 48 focused checks and the
283-check production combat audit. The focused checks cover both sides,
edge/empty slots, shields, Lava, real physics contact, exact particle timing,
lethal hit positions, stable resting transforms, waking/kicking, real GUI input
dispatch, independent materials, cleanup and remote fighter/spectator replay.
The structural audit passes: 8 nodes, one mesh/surface/material, 919 triangles,
one primitive collision, no extra light or particles. The original asset and
license are preserved. Headless suites retain an ObjectDB warning on exit.

Eight rendered views were reviewed on the real Main table: falling, landed,
partial dissolve, kick and four close angles. The normal room lighting and
match camera are used; diagnostic shots stop lamp flicker at its authored base
energy and finish startup blur. The render job exits without engine errors.
The report contains short matched 30-frame samples after the hit effects finish;
they are a local cost comparison, not a general FPS claim. Live Steam play and
exported builds have not been tested.

The additional damage-number suite passes all 83 assertions but reports seven
audio resources still in use during shutdown. A verbose diagnostic identifies
poison/inject, damage/kill, shield and corpse audio playback, with no brick
resource in that list. A fixture with brick creation disabled exits without
that resource error. This extra suite is therefore recorded as an assertion
pass with an unresolved audio teardown error, rather than a clean run.
