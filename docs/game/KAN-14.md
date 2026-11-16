# KAN-14: deterministic local supply and demand

Implemented inventory-driven prices independently for each port and good. The next quote is the initial price plus initial inventory minus current inventory, clamped between 1 coin and twice the initial price. Buying reduces supply and raises the next quote; selling increases supply and lowers it until a bound is reached. Restoring initial inventory restores the initial price without clamp drift.

Each transaction batch settles at its displayed pre-trade unit price. Only accepted transactions update inventory and subsequent quotes. The existing market rows refresh after trades and display the updated coins per unit. Rejected transactions preserve prices and balances. There is no global simulation or time-driven price change.

Expanded the headless economy probes to verify successive sale proceeds, buying and selling price responses, isolation between ports and goods, both bounds, reversal from saturation, deterministic replay, and atomic rejection including prices. Updated earlier settlement expectations for dynamic quotes.

## Observed harness results

- validate: Godot 4.5.1 completed project import and script registration.
- scene: economy probes and labeled rectangle scene contract passed. Godot reported an ObjectDB instances leaked at exit warning.
- smoke: economy probes passed, including local supply response, deterministic replay and both price bounds. Voyage interaction probes also passed.
- export: Windows export completed; the exported executable smoke test passed the economy and voyage interaction probes.

No manual visual testing was performed. No PR merge or Jira Done transition was performed; human review and merge remain required.
