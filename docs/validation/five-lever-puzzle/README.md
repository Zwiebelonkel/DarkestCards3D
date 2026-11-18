# Five-lever basement puzzle — 2026-11-18

The five physical levers read left to right: **up, down, down, up, down**.
The existing first-trip requirement, one-time Klopapier reward, discovery
history and failed-save retry behavior are retained.

## Integration contract

- Existing prop: `Basement/PumpStation`, front along local +Z. Cabinet size,
  room transform and camera marker are preserved; bases are at local
  x = -0.9, -0.45, 0, 0.45, 0.9.
- Reuse the existing worn petrol cabinet, dark iron door, brass bases,
  metal handles and green/yellow lamps. No new lights or materials are required.
- Each 0.36-wide click box has 0.09 clearance from its neighbor. The focus
  view must expose all five controls. No room traversal or navigation changes.
- Geometry change: six added mesh instances, 288 added triangles; existing
  mesh resources remain shared. Two added click areas and animated pivots.
- The supplied `hint1.png` contains five 75-by-75 frames. Color and emission
  use that same texture. The clue is placed left of Satan for visibility.

## Validation

Godot 4.4.1, isolated saves, Steam startup disabled, Dummy audio and owned
off-desktop render jobs. The user's editor/game was left running.

- `pump_puzzle_backend_test.tscn`: **44 checks passed**, including all 31 wrong
  five-lever combinations, rejection of the old three-lever combination,
  successful reward, first-trip gate, failed-save retry and no duplicate reward.
- `basement_pump_control_test.tscn`: **95 checks passed** with real click input,
  all five independent controls, correct lamp/pose, focus, rapid clicks,
  journal/pause/turn restrictions, return travel, profile persistence and reward.
- `story_package_repeat_test.tscn`: **12 checks passed**, including puzzle
  completion stopping further automatic weed packages.
- Focused hint review: **10 checks passed**, including five-frame configuration,
  shared color/emission texture, all frame captures and looping frame 4 to 0.
- Saved basement scene reloaded through the Godot scene inspector without
  missing meshes, scene warnings or engine errors.

The save-byte assertion now examines `test-user/saves`, excluding global
playtime and diagnostic logs, which change independently of the cabinet.
All five hint frames, the hub clue, mixed/all-up/all-down cabinet states and
the reward view were visually inspected at 1280 by 720. Screenshots are beside
this report. No scripts or shaders reported errors in the final jobs. The
repeat-package and focused hint fixtures retain an ObjectDB exit leak warning.
Live Steam and exported builds were not tested.
