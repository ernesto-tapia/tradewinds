# KAN-16 — Voyage provisioning and consumption

Supplies use the running game's reserve and remain separate from commodity cargo. Dock purchases add four provisions for eight coins. The HUD, provisioning panel, and destination tooltip show required supplies; rejected departures show required and available amounts. Provision cost is ceil(distance / 100), charged once at departure.

## Executable acceptance coverage

`game/provisioning_check.gd` is attached to the main scene and automatically schedules its checks in headless mode. It creates an isolated real game and provisioning panel in a SubViewport, then sends actual mouse events to the port controls.

- Docking enables purchases; buying supplies adds exactly four and deducts eight coins.
- The real Port A-to-B route requires four provisions; the panel displays A=0/B=4, and the HUD and destination tooltip show the required amount before departure.
- Zero and three provisions reject the port click, preserve position, docking, reserves, money, cargo and voyage state, and display required/available amounts.
- Exactly four provisions allow sailing and leave zero, with four consumed displayed in the HUD and provisioning panel.
- Repeated departure, midpoint advancement and arrival do not charge again.
- Independent fixed-distance fixtures require 1, 2 and 3 provisions for 100, 100.1 and 250 units respectively.

The success marker is `KAN-16 provisioning acceptance passed:` and is emitted only after all assertions finish. Failures log `KAN-16 provisioning:` and terminate with exit 1. The configured smoke and exported-executable smoke checks execute it, alongside economy, contract, contract UI and theme checks.

Validation and full command receipts are recorded by the host for the exact committed head in `.runs/907cf6afd710/validation-<full-sha>.json`; those receipts, rather than this document, establish commit attribution, actual output and exit status. Separate disposable mutation checks confirmed that removing the shortage guard and rounding costs down each produce exit 1. Human visual approval remains separate.
