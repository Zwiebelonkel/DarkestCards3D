The ritual's saved `shotgun_collected` flag makes the supplied double-barrel
model appear in a rack below the top clicker visor. The rack follows the hinge
and remains usable without an unlocked Clicker card. Clicking the gun equips
that same model in front of the camera. Right-click returns it to the rack.

In the offline hub, while facing the table and holding the shotgun, click Satan
to fire. The first hit loops the supplied `satanPanic.png` sheet (2 frames, 8 fps)
and opens Satan's two-line conversation. Movement, the clicker and further shots
remain blocked until it closes; revealing or closing text never fires a shot.
The next click on Satan plays `satanKill.png` once (9 frames, 10 fps), holding
the final frame. Each shot has audio, muzzle light/flash and weapon recoil.

Panic and Kill own Satan's pose over hover and laughter. Ordinary click-based
jumpscares and the playtime encounter are suspended while armed or reacting.
Pause, travel, menus, training and online sessions cannot fire the weapon.
Ownership persists per profile. The two-hit presentation lasts for the current
hub instance; normal match cinematics can restore Satan, and loading another
hub instance starts a fresh encounter. This does not award match rewards or
mark an offline match as won.

Style/asset contract: reuse the 220-triangle shotgun, the clicker face material,
the existing `shot.mp3`, both supplied Satan sheets and the project's colored
eye-emission convention. The camera-mounted instance alone disables depth/fog;
the shrine's lighting/materials stay authored. No physics collision is needed:
pickup uses mesh-space ray intersection and shooting uses Satan's existing
pick area. Validate the open rack, held pose, Panic dialogue and completed Kill
at player view, plus pause, wrong-target, menu, rapid-click and reload behavior.

Validated locally on Godot 4.4.1: 46 encounter checks in the rendered player
view, 44 ritual checks, 52 Satan-jumpscare checks and 64 cat-clicker integration
checks passed (206 total). The saved prop also passed its structural/budget
contract. The legacy cat fixture required the first-entry greeting to be
disabled in the isolated test copy, matching its already-entered hub setup.
Production greeting behavior is unchanged.

Screenshots, logs, the asset audit, timing/draw observations and review metadata
are retained in `docs/validation/shotgun-encounter/`. The selected Main fixtures
report ObjectDB instances leaked at shutdown; no engine errors occurred in
the final passing runs. Live Steam and exported builds were not tested.
