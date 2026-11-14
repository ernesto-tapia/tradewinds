# Caribbean Tradewinds

Open `game/project.godot` in Godot 4.5.1 and run the main scene.

The bounded 1000 × 600 ocean map contains two labeled islands, Port A, Port B, and a ship. All visuals use flat rectangles, interior labels, and built-in fonts.

## Sailing and docking (KAN-10)

- Left-click either port to sail there at 200 map units per second. The feedback shows the destination, percentage completed, and remaining seconds, calculated from distance and speed.
- The active destination stays fixed until arrival. Movement clamps to the destination so large frame steps do not overshoot.
- Arrival stops the ship and displays the docked port. Click the other port to repeat the voyage; clicking the current port keeps the ship docked.
- Left-click Ship to select it. Its rectangle turns green and its label changes to Selected Ship.
- The Trade rectangle checks permission. Trade is blocked before docking and during every voyage, and permitted only while docked. This story provides the permission gate; it does not implement a goods market.

The scene exposes `sail_to(port)`, `can_trade()`, and `request_trade()` for behavioral checks. Voyage state is available through `current_destination`, `docked_port`, `voyage_distance`, `voyage_time`, `voyage_progress`, and `remaining_time`. Scene metadata includes `destination_id`, `at_sea`, `can_trade`, and `docked_port_id`.

Final art, multiplayer, and full world simulation are outside this story.

## Windows export

Install the matching Godot 4.5.1 export templates and create the `build/` directory at the repository root. Use the existing Windows Desktop export preset to produce `build/CaribbeanTradewinds.exe`.

## Verification

Run the configured checks in dependency order: `validate`, `scene`, `smoke`, then `export`.

The following results were returned by actual harness executions during this review:

| Check | Configured command | Observed result |
| --- | --- | --- |
| validate | `godot --headless --path game --editor --import --quit` | Godot `v4.5.1.stable.official.f62fdbde1`; project initialization and editor loading completed. |
| scene | `godot --headless --path game --script {harness_root}/scripts/check_scene.gd` | `Scene contract passed: title and labeled rectangles exist; no complex visual nodes`. Also emitted `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).` |
| smoke | `godot --headless --path game --quit-after 120` | Printed the voyage regression completion output below. |
| export | `godot --headless --path game --export-release "Windows Desktop" ../build/CaribbeanTradewinds.exe` | Packing completed; the harness then ran an exported executable smoke test, which printed the same voyage regression completion output. |

Both source and exported executable smoke runs printed:

```text
KAN-10 interaction passed: viewport clicks sailed A/B/A/B; midpoint progress, arrival stop, at-sea trade rejection and docked trade verified
```

The regression sends viewport mouse events to the destination and trade rectangles. It checks four voyages, positive travel duration, midpoint movement and displayed progress, remaining time, docking, stopped position after arrival, trade rejection at sea, trade permission while docked, and unchanged static UI node count. It advances movement using explicit delta values; this is headless behavioral evidence, not visual testing or a real-time voyage timing measurement.

The supplied harness responses contain command output but do not expose numeric exit codes or a checked commit identifier. Those details cannot be established from this transcript and must be supplied by the host execution record before claiming exact-commit validation with exit codes. No merge or Done transition is recorded here.
