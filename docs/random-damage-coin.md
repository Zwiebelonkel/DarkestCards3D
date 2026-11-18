# Random Damage coin

Selecting an attack target with Random Damage now tosses the existing
`assets/effects/coin/coin.glb` onto the center of the table. Each strike rolls
exactly 0.75× or 2× with equal probability. Saved effects with old ranges are
normalized when read. Catalog values and localized tooltips use the same rule.
Ordinary counterattacks retain their original damage.

The scripted flip takes 0.42 seconds, settles for 0.12 seconds, then holds the
result for 0.16 seconds. Only then does the attack start. The coin dissolves over
the following 1.15 seconds using the existing dissolve shader, independently of
turn progression. Double/triple strikes roll one coin per actual strike.
Clearing or retiring a match cancels its pending coins and attacks.

The model's +Y face is red 0.75; the -Y face is green 2. The reusable scene
scales the model to a 0.72m diameter and raises its embedded number meshes just
above the body. The source GLB is untouched. The body uses lit metal with
metallic=1, roughness=0.55 and a darker silver color tuned against the real table
lighting. Every surface has emission disabled, including the dissolve edge.
Three private materials allow independent dissolves without changing shared
imported materials. The asset has five nodes, three surfaces and 1,168 triangles,
with no lights or collision.

The host rolls before sending the attack presentation. Its multiplier travels
with that reliable RPC; remote fighters and spectators display the supplied
face before moving their local card. Damage uses the exact original roll.
The network protocol is now 10 to separate incompatible attack RPC versions.

Validation lives in `docs/validation/random-damage-coin/`. The focused coin,
card-effect unit and production combat audit suites cover the behavior. The
rendered review uses the real Main scene, normal match camera and environment;
only the startup wake-up blur is allowed to finish immediately. Both result
faces, edge views, flight and half-dissolve were reviewed. The report includes
small 30-frame before/after performance samples, not a general FPS guarantee.

The older lower-rarity suite still fails its placeholder/static-artwork and
armor-text expectations against the current card catalog. Its updated coin
damage assertions pass; unrelated assertions were left unchanged. Test exits
may report the existing ObjectDB leak warning. Live Steam multiplayer and an
exported build were not tested; remote presentation was exercised locally.
