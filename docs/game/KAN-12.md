# KAN-12: Port market screen and commodity prices

Implemented a dock-only market with Sugar, Rum and Coffee. Each row shows the good, current stock, unit price and owned quantity, with Buy 1 and Sell 1 controls. The market heading shows the current port and wallet. Transactions refresh displayed balances and stock. Departing hides the market; arrival displays the destination's values. Static controls are created once in _ready(). All visuals use labeled rectangles, flat colors and built-in fonts.

Initial fixtures:

| Good | Port A stock | Port A coins/unit | Port B stock | Port B coins/unit |
| --- | ---: | ---: | ---: | ---: |
| Sugar | 20 | 5 | 10 | 8 |
| Rum | 10 | 10 | 20 | 7 |
| Coffee | 15 | 12 | 8 | 18 |

Restored the scene's shared data_models.gd integration, resolving the reported unresolved model types in main.gd. Existing voyage and atomic transaction behavior remain covered by regression checks. Updated the economy regression's previous two-good expectation to three goods and extended it to verify both markets, displayed rows and wallet, every buy/sell control signal, independent snapshots and static UI reuse.

Observed command results using Godot 4.5.1:

- validate: completed import without reported script errors.
- scene: passed the labeled rectangle scene contract, KAN-11 economy regression and KAN-12 market regression. Reported an ObjectDB instances leaked at exit warning.
- smoke: printed KAN-11 economy, KAN-12 market and KAN-10 voyage interaction success messages, without the scene exit warning.
- export: completed savepack. The exported executable smoke test printed all three regression success messages.

Market controls were exercised through emitted gui_input signals; voyage controls were exercised through viewport mouse events. No manual visual testing or market viewport hit-testing is claimed.

No PR was merged and the story is not marked Done. Human review and merge remain required.
