# KAN-11: Data models and local game state

Implemented Port, Good, Ship, Cargo, PlayerWallet, Market, Contract and Voyage in game/data_models.gd. Each state instance initializes independent fixed fixtures: two ports, two goods, two markets, one ship with capacity 20, an empty cargo hold, 100 coins, one delivery contract and an idle voyage.

The running scene creates one shared game_state. Port placement, ship position, voyage progress and docking use that state. Buy and sell operations update the shared wallet, ship cargo and current market inventory. Transactions reject trading at sea, unknown goods, invalid quantities, insufficient funds, insufficient stock and cargo capacity violations before mutating balances. Rectangle controls provide Buy 1 Sugar and Sell 1 Sugar actions with visible wallet, cargo, price and stock feedback. Contracts are seeded data; contract execution is outside this implementation.

## Observed checks

Executed using Godot 4.5.1:

- validate: completed project import without reported script errors.
- scene: printed "Scene contract passed: title and labeled rectangles exist; no complex visual nodes" and "KAN-11 economy passed". It also reported an ObjectDB instances leaked at exit warning.
- smoke: printed both "KAN-11 economy passed" and "KAN-10 interaction passed" without the scene exit warning.
- export: completed savepack; the exported executable smoke test printed both economy and voyage interaction success messages.

The economy regression exercised runtime buy/sell updates, shared cargo identity, docking state, displayed balances, independent fixtures and atomic rejection cases. The voyage regression exercised viewport clicks through A/B/A/B, midpoint progress, arrival stopping and trade availability. No manual visual testing is claimed.

No PR was merged and the story is not marked Done. Human review and merge remain required.
