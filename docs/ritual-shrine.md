# Underground ritual shrine

The independent `scenes/props/RitualShrine.tscn` is instanced in the independent
`scenes/rooms/UndergroundVault.tscn`, at local `(0,0,13)`, five meters in front
of the arrival camera anchor. It uses the hall's pale/dark stone, brass details,
three recessed sockets and two ember cups without adding lights or particles.

Hovering the altar uses the existing `ScreenCameraFocus` system to swing Main's
shared camera to `FocusCamera`. The normal view returns when the pointer leaves.
The contextual hand extends the station's hover surface only while focused,
keeping the camera stable when selecting a card. Fog and the room environment
remain unchanged by focus.

The hand shows owned, unplaced **Holy Water, Crucifix and Silver Bullet** cards
using the normal Card3D visuals and localized text. Press and hold left mouse on
a card, drag it over any empty socket and release. The destination frame turns
yellow, then the card snaps flat into its anchor. There is no automatic placement
and no required socket order. Outside/occupied drops return the card. The three
distinct cards can each be placed once. Pause cancels a held card; dragging,
snapping, the reward fall and collection block turns and other room actions.

After the third snap completes, the supplied shotgun falls 3.4 meters onto the
rear altar ledge and settles with a small bounce. It becomes collectable only
after landing. Hover outlines the actual gun meshes in yellow; left-click saves
ownership and brings the model toward the camera before hiding it. The supplied
shotgun scene's obsolete resource paths were repaired and its texture uses a
rough, nearest-filtered material consistent with the project.

CollectionManager stores independent per-profile progress in:

```
metadata.vault_ritual = {
  "slots": ["crucifix", "holy_water", "silver_bullet"],
  "shotgun_collected": true
}
```

Each placement and pickup commits an atomic snapshot before changing the visible
state. Failed writes remain retryable. Unknown/duplicate stored card IDs are
filtered; training cannot commit progress. Placement retains the unique story
cards in the collection as mementos. Partial socket positions survive reload.
A complete, uncollected ritual restores the gun at rest; a collected reward
never respawns. Existing story-item return dialogue flags remain independent.

`scripts/rooms/RitualShrine.gd` handles the contextual hand, pointer projection,
snap/fall/pickup animations and outlines. Main supplies the shared camera, focus
registration and room/modal gates. Static geometry is saved in the prop scene;
`tools/vault/build_ritual_shrine.tscn` rebuilds it and re-instances it into the
current hall. `tools/vault/build_vault.tscn` preserves this shrine instance when
rebuilding the hall. Instanced scene ownership is retained for direct editing.
The five-language instructions/status catalog is rebuilt through
`tools/vault/build_ritual_localization.tscn`.

See [validation evidence](validation/ritual-shrine/README.md) for actual mouse
dragging, pause, occupied drops, both reload states, gun hover/click and resource
budgets.
