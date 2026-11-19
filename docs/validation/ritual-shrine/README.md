# Ritual shrine validation

Godot 4.4.1, 2026-11-19 (Europe/Berlin). Owned off-desktop render/headless jobs used copies from
`tools/weed/prepare_validation.ps1`, with Steam disabled and saves redirected to
the copy's `res://test-user`. The user's existing editor/game stayed open.

| Check | Result |
| --- | --- |
| `tests/ritual_shrine_test.tscn`, rendered | 60 checks passed, no engine errors |
| Existing grave animation/fog/stair suite, rendered | 59 checks passed, no engine errors |
| Shrine and combined hall resource/budget audits | Both passed, no engine errors |
| Loaded shrine inspection | 58 nodes, no structural warnings |

The real viewport tests cover manually dragging all three owned story cards,
an outside drop, an occupied socket, pausing a held card, camera focus and return,
the third-card trigger, the falling/settling reward, actual yellow gun hover,
paused collection, click-to-collect, and the return stair. Reload is checked
before pickup and after collection. Backend tests reject missing ownership,
wrong cards, invalid sockets, duplicates, overwrites, training, early pickup and
repeated pickup; failed saves preserve the pending state for retry.

Both prop and hall remain ordinary independent PackedScenes. The loaded hall
retains its complete serialized MultiMesh buffers and custom bounds. Static
architecture audits use an empty isolated profile; runtime Card3D instances are
covered by the actual interaction/performance run. Only primitive picking shapes
are added; the shrine does not add a physics obstacle to the shared-camera route.
The existing forward/reverse route probe and fog continuity suite still pass.

| Static metric | Shrine | Hall including shrine |
| --- | ---: | ---: |
| Nodes | 58 | 114 |
| Mesh instances | 33 | 60 |
| Triangles | 604 | 4864 |
| Materials | 5 | 9 |
| Primitive collision/picking shapes | 6 | 13 |
| Lights / particles | 0 / 0 | 6 / 0 |
| MultiMeshes / elements | 0 / 0 | 6 / 100 |
| Valid MultiMesh transform floats | 0 | 1200 |

The shrine's visible bounds are 5.1 x 1.993 x 3.1 meters. The base penetrates the
floor slightly; the stepped body supports the slab, socket borders overlap their
recesses and the shotgun's normalized model rests just above the slab (5 mm).
No concave collider or extra navigation requirement is introduced by this prop;
the project uses cardinal stationary views and click-to-travel.

Thirty-frame samples after six settling frames record integrated mean/p95 frame
times and draw calls in [review_report.json](review_report.json). These include
normal Card3D rarity effects, the existing postprocessing and inherited fog.
They are short local samples, not exported-build performance guarantees. Dummy
audio validates playback state; live Steam and exported builds were not tested.
The existing grave suite prints its known ObjectDB exit warning; the final ritual
suite finishes without warnings or errors.

All sixteen final images were inspected at native resolution, including
construction joins and the gun's contact with the rear ledge:

- Interaction: [approach](approach.png), [empty sockets](three-empty-sockets.png),
  [first card](first-card-seated.png), [two cards](two-cards-seated.png),
  [falling shotgun](shotgun-falling.png), [landed](shotgun-landed.png),
  [yellow hover](shotgun-hover.png), [collected](shotgun-collected.png).
- Architecture: [front](asset-front.png), [back](asset-back.png),
  [left](asset-left.png), [right](asset-right.png),
  [three-quarter](asset-three-quarter.png), [socket closeup](socket-closeup.png),
  [body/slab support](support-closeup.png), [gun/model contact](shotgun-closeup.png).

[Shrine audit](RitualShrine-audit.json), [combined hall audit](UndergroundVault-audit.json),
[ritual log](ritual-shrine.log) and [grave regression log](grave-vault-regression.log)
retain the successful results. Capture times, camera poses, image diagnostics,
scene modification time and performance samples are stored in the review report.
