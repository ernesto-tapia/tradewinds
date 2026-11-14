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

Run the configured checks in dependency order: `validate`, `scene`, `smoke`, then `export`. These checks establish import, scene structure, startup, and export results. They do not by themselves verify voyage behavior or constitute visual testing.
