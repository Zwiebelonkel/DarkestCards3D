# Identical event stacks — 2026-11-18

Validated with Godot 4.4.1 in a temporary project with redirected saves and the
existing test network adapter. The player's saves and running editor were not used.

- `event_cards_test.tscn`: PASS, 99 checks, including 12 new stack assertions.
  Covers interleaved duplicates, exact effect equality, separate strength variants,
  selection/cancellation of a specific copy, single-copy consumption, remaining
  stack order/count, and the existing one-event-per-turn gate.
- `event_cards_visual_test.tscn`: PASS, 27 layout/presentation checks. Rendered and
  inspected at 1280×720 and 800×600; captures are in this directory. Covers exposed
  stack edges, hover, physical hand count, stack pagination and match cleanup.
- `starting_events_test.tscn`: PASS, 52 checks.
- `event_cards_network_test.tscn`: 44 passed, one existing failure:
  “opening events are available on the first host turn without a next-turn notice”.
  Reproduced the same failure with the original `EventHandUI.gd` from HEAD in the
  same isolated project. Event RPCs, consumption, targeting and barriers passed.
- `git diff --check` passed for the changed source, tests and event documentation.

No live Steam or exported-build test was performed.
