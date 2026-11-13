# Caribbean Tradewinds

Open `game/project.godot` in Godot 4.5.1 and run the main scene.

The bounded 1000 × 600 top-down ocean map contains two labeled islands, distinct Port A and Port B rectangles, and a ship. An enabled Camera2D fits the map into the initial viewport and has finite world limits. All visuals use flat rectangles, text labels, and built-in fonts.

## Click controls

- Left-click Port A or Port B to choose that destination. The bottom feedback label displays the chosen port.
- Left-click Ship to select it. Its rectangle turns green and its label changes to Selected Ship.

Sailing and trade are not implemented yet. Final art, multiplayer, and full world simulation are outside this story.

## Windows export

Install the matching Godot 4.5.1 export templates and create the `build/` directory at the repository root. Use the existing Windows Desktop export preset to produce `build/CaribbeanTradewinds.exe`.
