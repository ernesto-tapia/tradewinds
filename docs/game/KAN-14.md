# KAN-14: deterministic local supply and demand

Accepted trades immediately refresh the affected good's local price from inventory: base price plus initial stock minus current stock, clamped between 1 coin and twice the base price. Buying raises subsequent quotes; selling lowers them, subject to bounds. Other goods and ports remain unchanged. Voyages preserve prices without a second adjustment.

Transactions settle each unit at its inventory step. Purchases use the price before removing that unit; sales use the price after adding that unit. Reversing a trade traverses the same steps and restores the wallet without profit, including at price bounds. Batch transactions use the sum of these unit prices and reject atomically when invalid or unaffordable.

Each good has Buy 1, Sell 1, Buy all and Sell all controls. The market shows separate next-unit buy and sell prices and bulk totals. Buy all accounts for rising unit prices, stock and shared cargo capacity; Sell all sells only the selected good. Visuals remain labeled flat rectangles.

## Observed harness results

All configured checks ran with Godot 4.5.1:

- validate: project import completed.
- scene: economy assertions and labeled rectangle scene contract passed. Godot reported an ObjectDB instances leaked at exit warning.
- smoke: economy assertions and voyage interaction probes passed.
- export: packing completed; exported executable smoke test passed economy and voyage interaction probes.

Economy assertions verified immediate price changes after consecutive trades, marginal batch totals, both round-trip directions without profit, local effects, minimum and maximum bounds, reversal without drift, deterministic replay, voyage persistence, bulk limits and atomic rejections. The consecutive-sale fixture bought three Sugar for 18 coins, then received 7 and 6 coins for successive single-unit sales while the subsequent quotes decreased to 7 and 6.

Voyage probes reported viewport clicks through A/B/A/B, midpoint progress, arrival stopping, at-sea trade rejection, docked trading and current-port interaction.

No manual visual playtest was performed. Human visual review and merge remain pending. No PR merge or Jira Done transition was performed.
