# Character emission

Satan, the angel, black-market dealer, jester and prisoner use colored emission
maps for all visible, nonblack pixels. The cat is excluded. Existing silhouettes, 64 x 64 animation frames,
billboards, nearest texture filtering, world positions and interaction areas
are retained. Black bodies receive zero emission. Specular reflections are
disabled. The material multiplies emission color by the emission map so black
cannot receive an additive white glow.

The angel's halo, the prisoner's mouth and sword, and Satan's laughing mouth
all emit in their original colors. Blinks use the corresponding mask frames.
Idle, hover, laugh and death sheets each have a matching map.

`eye_glow.tres` beside each character controls `emission_energy_multiplier`
(default 3). The material is visible in the editor and duplicated per sprite
at runtime. `SpriteAnim.gd` synchronizes both textures on `texture_changed`,
including direct assignments during jumpscare recovery. Frame UVs come from
Sprite3D, so emission follows the same animation without a second animation.

Main-menu Satan explicitly uses `assets/characters/satan/menu_glow.tres`,
with emission energy 6 to remain visible through the menu's screen filters.
It shares the same colored masks and animation synchronization, while the
gameplay material retains energy 3. `tests/main_menu_emission_test.tscn`
checks the actual menu instance, black-pixel exclusion and sheet changes.

Rebuild the saved texture resources and initial materials with the owned
headless runner `res://tools/character_eyes/bake_eye_maps.tscn`. The runtime
preloads all maps so exported resource discovery does not rely on file scans.

## Asset contract

Profile: prop (material-only adjustment to existing flat billboards).
Style references: the five existing character sheets, with their original
red, cyan, purple, green and yellow/white accents. No added geometry, nodes,
lights, particles, collisions, navigation or changed clearances. Budget:
one material per participating sprite and twelve shared, baked textures.
Construction junctions and terrain routes are not applicable.

Validation covers source/mask dimensions, emitting colored details, blinks,
hover/laugh/death switching, direct texture restoration, shared-material
isolation, packed-scene integration, dark/normal renders and in-world views.

Verified in Godot 4.4.1 Forward+: 283 checks passed, including rendered black
body samples. Isolated normal/dark images and authored-room views are in
`docs/validation/character-eyes/`, with capture times and luminance diagnostics
in `review_report.json`. The four scenes containing the five actors loaded without engine
errors. Room captures disable gameplay scripts and retain authored lighting;
they do not verify a live Steam session or an exported build.
