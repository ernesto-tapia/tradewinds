# KAN-13: Buy and sell with money and cargo checks

The market uses the shared game state for purchases and sales. Purchases deduct coins, add cargo and decrease the docked market's stock. Sales remove owned cargo, credit coins and increase that market's stock. Each cargo unit occupies one of the ship's 20 slots. Trades require docking and reject invalid goods, nonpositive quantities, insufficient stock, insufficient funds, insufficient capacity and overselling before changing balances.

This change repairs economy_check.gd, which referenced unavailable Ship, PlayerWallet and Market types and nonexistent scene nodes. Its check_buy, check_sell and check_can_trade methods now delegate to the running scene's transaction interfaces. Independent fixtures exercise the existing transaction implementation without changing the player's state.

Observed command results on Godot 4.5.1:

- validate: completed without script parse errors.
- scene: printed the economy checks success message and passed the labeled rectangle scene contract. Reported an ObjectDB instances leaked at exit warning.
- smoke: printed the economy checks success message and passed the existing KAN-10 voyage interaction checks.
- export: completed Windows executable packaging; the exported executable smoke test printed the economy checks success message and passed the KAN-10 interaction checks.

Economy assertions cover exact purchase deductions and sale credits, cargo and stock changes, atomic rejection, mixed cargo capacity, capacity reuse after selling, independent port stocks, destination pricing, voyage restrictions, and a purchase using exactly all available coins, stock and capacity.

The observed economy results come from state assertions. Manual market interaction and visual testing were not performed. Human review and merge remain pending; this report does not mark the story Done.
