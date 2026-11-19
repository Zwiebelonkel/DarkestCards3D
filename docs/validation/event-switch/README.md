# Switch exchange validation

Validated on 2026-11-18 with Godot 4.4.1 in isolated project copies and isolated
save files. Steam initialization was disabled for these local checks.

- `event-cards.log`: all 132 event checks pass, including the actual hand click,
  random complete-instance exchange, flight movement, pile reconciliation,
  cleanup, and the attack remaining available after the reveal.
- `event-network.log`: the existing ENet event suite passes, with Switch checks
  for both casters, snapshot privacy, duplicate-snapshot idempotence, and flight
  completion before the action barrier releases. The two-peer fixture also
  exercises the receiving table's spectator view; it shares the authority's
  network manager and retains its opponent role for the ACK barrier.
- `visual.log` and `01-before.png` through `06-landed.png`: Forward+ captures
  using the real Main scene, room lighting, original match camera, eight cards
  in each pile, and a visible Switch reveal. The paused exchange tween is stepped
  through its actual path for reproducible captures. Both lanes, their opposing
  destinations, unchanged pile sizes, and leaving mid-flight are checked.

The runs report an ObjectDB cleanup warning at shutdown. No script errors were
reported by the passing runs. Live Steam and exported builds were not tested.
