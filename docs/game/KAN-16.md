# KAN-16 — Voyage provisioning and consumption

Supplies use the running game's reserve and remain separate from commodity cargo. Dock purchases add four provisions for eight coins. Departure costs ceil(distance / 100), charged once when sailing starts. Insufficient reserves block departure and display required and available amounts.

While sailing, both port tooltips state that departure is unavailable and show the fixed amount already charged. They do not quote a decreasing cost from the moving ship. Docking restores departure quotes from the arrival port. The sailing HUD rebuilds its accepted departure summary from voyage data, so transient rejected clicks cannot erase the required and consumed amounts on subsequent refreshes.

## Executable regression coverage

`game/provisioning_check.gd` is attached to `game/main.tscn` and automatically schedules its checks in headless mode. Its isolated real game and provisioning panel receive viewport mouse events.

- Docking enables the actual Buy Provisions button. A pointer click activates it exactly once, adds four provisions, deducts eight coins, and updates purchase feedback and displayed balance.
- The Port A-to-B route requires four provisions. Before departure, the panel displays A=0/B=4 and the HUD and tooltip show the requirement.
- Zero and three provisions reject port clicks atomically, preserving docking, position, reserves, money, cargo and voyage state while displaying required and available amounts.
- Exactly four provisions allow departure, consume four once, and display the zero remaining balance.
- Rejected underway clicks do not charge again. The refreshed midpoint HUD retains the accepted required/consumed summary.
- Both port tooltips show the fixed four-provision charge at departure, midpoint and 75% progress. Arrival restores A=4/B=0 departure quotes and panel requirements.
- Midpoint and arrival updates do not charge again. Independent fixtures verify rounding at 100, 100.1 and 250 units.

The pointer fixture waits for the theme and voyage input fixtures to finish. Initial attempts using an offscreen SubViewportContainer failed the purchase assertion with zero button activations. The fixture now uses a standalone SubViewport with injected local pointer coordinates and one mouse-entry notification. It retains the resource, activation, feedback and visibility assertions; it does not call the purchase handler directly.

`game/voyage_check.gd` retains the KAN-10 interaction regression. Its isolated game is seeded with 40 provisions for repeated A/B/A/B voyages. Assertions cover midpoint position and displayed progress, arrival docking, stopped position, trade permission, and current-port clicks preserving reserves and docking while resetting scene voyage duration to zero.

## Recorded checks

After the final source and fixture edits, the host ran `validate`, `scene`, `smoke` and `export` successfully. Smoke and export returned both the KAN-10 interaction and KAN-16 provisioning acceptance markers. Earlier smoke attempts failed the pointer purchase assertion; those failures were resolved by correcting viewport input delivery without weakening assertions.

The host retains actual command receipts. Human visual approval remains pending; headless checks do not establish visual quality. Independent QA and exact-head review remain the host's responsibility. Human merges the PR; this document does not mark the story Done.
