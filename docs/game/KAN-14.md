# KAN-14: deterministic local supply and demand

Quotes remain fixed throughout each port visit. Accepted trades update inventory, cargo and coins immediately. Departing for another port recalculates the departing market's quotes from net inventory: initial price plus initial inventory minus current inventory, clamped between 1 coin and twice the initial price. Quotes persist for the next visit. Clicking the current port does not settle prices or end the visit.

Buying and immediately selling the same quantity during a visit uses the same quote and produces no profit. Each port and good responds independently; there is no global simulation.

Buy all and Sell all controls appear for each good alongside single-unit controls. Buy all respects stock, funds and shared cargo capacity. Sell all sells only the selected good. Controls display bulk quantities, and the market explains departure pricing. Visuals remain labeled flat rectangles.

## Observed harness results

The latest executed checks all passed with Godot 4.5.1:

- validate: project import completed.
- scene: economy probes and the labeled rectangle scene contract passed. Godot reported an ObjectDB instances leaked at exit warning.
- smoke: economy probes and viewport voyage interaction probes passed.
- export: packing completed, and the exported executable smoke test passed both economy and voyage interaction probes. The earlier temporary-file rename failure did not recur in this attempt.

Economy probes verified fixed visit quotes, no same-visit round-trip profit, departure settlement, return visits, local deterministic bounded prices, reversal without drift, bulk limits and atomic rejection. Voyage probes verified viewport clicks through A/B/A/B, midpoint progress, arrival stopping, at-sea trade rejection, docked trading and current-port interaction.

No manual visual playtest was performed. Automated checks do not establish manual visual approval. No PR merge or Jira Done transition was performed; human review and merge remain pending.
