# Graveyard secret vault

Solving the existing MDMA grave-name puzzle still grants the unique Silver Bullet
story card. After its reveal has had 3.9 seconds to read, the two screen-left
graves move left and the two screen-right graves move right over 2.8 seconds.
They rock with staggered phases while sliding; the shake eases in and out.
Stone, soil and name inscriptions fade together during the last part of the
movement and are fully transparent before the roots are hidden. The ground opens with the animation
and exposes an orange-lit staircase. Pause freezes the opening; navigation and
grave picks are disabled while it runs.

Hovering the revealed stair outlines its stone rim in yellow. Left-click follows
the actual shared Main camera down the stair shaft into a large underground
vault. The default journey lasts 5.5 seconds with the existing walking bob and
footsteps. All four normal A/D directions work in the new room. Facing back and
clicking its outlined entrance portal climbs the same stairs to the saved
graveyard position and facing. Pause, menus and an active journey block repeat
activation. The original graveyard camera environment is restored on return.
The hall inherits all regular and volumetric fog settings from the effective
graveyard camera/world environment, preserving fog throughout descent, arrival
and ascent. Its lighting uses an instance copy, leaving both source resources
unchanged.

The hall is 32 by 63 meters, with a 13.56-meter roof apex above its floor: a
barrel vault, nine transverse ribs, eighteen columns, side aisles, sarcophagi,
warm lamps and an empty far plinth. A [three-card ritual shrine](ritual-shrine.md)
stands directly ahead of the arriving player and unlocks the collectable shotgun.
It is an independent saved PackedScene, editable directly in Godot:

- `scenes/rooms/UndergroundVault.tscn`: hall, primitive floor/perimeter collision,
  entrance markers, exit picking area and exported underground environment.
- `scenes/props/RitualShrine.tscn`: independently editable altar, three sockets,
  focus marker, story-card hand, supplied shotgun model and pickup area.
- `scenes/props/GraveSecretStairs.tscn`: 64 visible steps, continuous collision
  ramp, bottom landing, shaft walls, roof, ribs, lamps and travel markers.
- `scripts/rooms/GraveVaultEntrance.gd`: grave motion, ground opening and stair
  interaction. The ground cut uses default-disabled per-instance parameters on
  only the overlapping original earth, grass and path meshes.
- `scripts/rooms/UndergroundVault.gd`: return-portal hover and activation.
- `scripts/main/Main.gd`: camera route, room 5, ambience and interaction gates.

The stairs inherit the authored graveyard scale of 1.825. Their local 12.8-meter
run and 8.96-meter drop become approximately 23.36 and 16.35 world meters. The
hall is positioned from the bottom landing, at unit scale; its entire roof sits
below the graveyard. Its own entrance aligns with the shaft rather than using a
destination screen or a second camera. Normal graveyard/crypt geometry remains
in its authored place.

The permanent unlock derives from Silver Bullet acquisition history. Reloading
an already-solved save restores the fully open passage immediately. Removing
the owned card cannot close it or strand a visitor. The entrance needs no extra
progress flag. The shrine records its own socket/pickup progress separately.
Entering the vault does not consume the separate one-time Satan
conversation; that still happens only on the next return to the main room.

Geometry is saved in the PackedScenes, with no runtime mesh generation.
`tools/vault/build_vault.tscn` deterministically rebuilds both scenes if needed;
doing so replaces manual architecture edits. Repeated columns, steps and props
use shared meshes and complete serialized MultiMesh transform buffers. The
builder reloads both resources to verify buffers and bounds after saving.

See [validation evidence](validation/underground-vault/README.md) for the real
viewport solve, stair round trip, saved-profile restore, collision samples,
asset budgets and reviewed images.
