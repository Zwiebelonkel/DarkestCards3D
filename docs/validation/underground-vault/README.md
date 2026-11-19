# Underground vault validation

The architecture figures below describe the original hall. The later
[ritual-shrine validation](../ritual-shrine/README.md) records the current
combined hall/shrine budgets and reruns the grave/fog/stair suite successfully.

Validated 2026-11-18 in Godot 4.4.1 with an isolated copy prepared through
`tools/weed/prepare_validation.ps1`. Player saves were redirected to the copy's
`res://test-user`; Steam was disabled. Render checks used an owned off-desktop
process with Dummy audio, leaving the user's Godot editor and saves untouched.

| Check | Result |
| --- | --- |
| `tests/grave_vault_test.tscn`, rendered, fog/wobble follow-up | 59 checks passed |
| Existing grave-name puzzle, headless | 50 checks passed |
| Existing Silver Bullet main-room return dialogue, headless | 68 checks passed |
| Existing graveyard and basement travel, rendered | 102 checks passed |
| Hall and stair resource/budget audits | Both passed |
| Actual forward/reverse shared-camera route | 108 physics samples, 0 obstructions, 0 fog discontinuities |

The new suite consumes MDMA, solves the four graves through actual viewport
clicks, observes the reward and left/right slide, pauses the animation, checks
all original floor layers, hovers and clicks the stairs, descends, turns through
all four room sides, hovers and clicks the exit, climbs back, checks exact camera
and environment restoration, and reloads a solved profile. Locked, paused,
opening and remote-hub activation are covered. It also verifies that the room
does not duplicate the card or consume the main-room Satan dialogue.
The follow-up checks visible rocking on all four graves, pause-frozen rotation,
an intermediate fade on every stone/soil/inscription visual and full transparency
before hiding. Every sampled forward/reverse travel frame retains the complete
fog property set. A separate override check confirms copied camera fog without
mutating shared resources or changing the hall's ambient lighting.

Route checks use a radius-0.18-meter sphere at the actual camera eye against
physical bodies. This game uses stationary cardinal views and click-to-travel;
there is no free-walking player or NPC route to validate. Primitive ramps and
split perimeter colliders leave the portal clear. No concave collision mesh is
used. Full-scene puzzle/dialogue tests print an ObjectDB exit leak warning;
the final room-navigation run and both isolated architecture audits finish
without engine errors. Dummy audio tests playback state, not audible output.

The old exploration fixture was updated to suppress unrelated greeting/timed
cinematics and to expect the already-existing inward hub return facing
(graveyard -> table, basement -> pack shop). Gameplay return logic is unchanged.

## Saved architecture

| Metric | Hall | Stairs |
| --- | ---: | ---: |
| Nodes | 56 | 27 |
| Mesh instances | 27 | 15 |
| MultiMeshes / repeated elements | 6 / 100 | 1 / 64 |
| Serialized transform floats | 1200 | 768 |
| Invalid buffers / missing custom bounds | 0 / 0 | 0 / 0 |
| Triangles including repeated instances | 4260 | 1644 |
| Material resources | 4 | 4 |
| Lights | 6 | 2 |
| Primitive collision shapes | 7 | 2 |
| Bounds | 32 x 14.06 x 63 m | 3.3 x 10.108 x 13.755 local m |

The hall uses two shadowed spotlights and four fill lights. Other lamps are
shared emissive geometry; the shaft has two local lights. Nonuniform visual
box scales are intentional. Collision dimensions are stored in primitive shape
resources, with no nonuniformly scaled physics parent.

Thirty-frame local samples after six settling frames:

| View | Mean frame time | 95th percentile | Draw calls |
| --- | ---: | ---: | ---: |
| Original graveyard view | 16.67 ms | 16.70 ms | 38 |
| Revealed stair view | 16.67 ms | 16.78 ms | 38 |
| Vault nave with inherited fog | 16.67 ms | 16.75 ms | 22 |

These short rendered samples include the existing full-scene effects and local
frame scheduling; they are not exported-build performance measurements. Live
Steam and exported builds were not tested.

## Visual review

All 23 final captures were inspected. The saved architecture, complete repeated
meshes, full roof/end-wall enclosure, column/arch overlap, side aisles, portal
clearance, shaft roof and floor reveal were reviewed from both route directions.
The intended dark stone palette, warm stair lamps and cool/warm hall lighting
remain consistent with the existing graveyard and basement surface shader.

- Ground sequence: [closed](graveyard-closed.png), [sliding](graveyard-sliding.png),
  [fading before completion](graveyard-fading.png),
  [open](graveyard-open.png), [stair hover](stair-hover.png),
  [descent](stair-descent.png), [returned](graveyard-return.png).
- Player views: [nave](vault-nave.png), [side 0](vault-side-0.png),
  [side 1](vault-side-1.png), [side 2](vault-side-2.png),
  [side 3](vault-side-3.png), [exit hover](vault-exit-hover.png).
- Exterior enclosure: [front](asset-front.png), [back](asset-back.png),
  [left](asset-left.png), [right](asset-right.png), [roof](asset-roof.png).
- Construction details: [portal outside](portal-exterior.png),
  [portal inside](portal-interior.png), [capital/arch](capital-junction.png),
  [roof/end wall](roof-junction.png), [side aisle](side-aisle.png).

[review_report.json](review_report.json) records capture times, camera poses,
image luminance, route samples, final scene modification time and performance.
[Hall audit](UndergroundVault-audit.json) and
[stair audit](GraveSecretStairs-audit.json) contain the loaded resource metrics.
The accompanying logs record all four successful integration suites.
