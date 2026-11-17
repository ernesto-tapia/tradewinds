# KAN-15: One repeatable delivery contract

Implemented a contract board using labeled rectangles and built-in fonts. Dock at Port A and accept the offer, buy Sugar in the market, sail to Port B, then click Deliver. An active contract requires three Sugar and awards 30 coins. Delivery consumes exactly three Sugar, preserves other cargo and market stock, and prevents duplicate payment. Return to Port A to accept the offer again.

The delivery service exposes accept_contract(), complete_contract(), and get_contract_data(); the ContractBoard node exposes the same methods. Acceptance rejects requests at sea, at the wrong port, for unknown contracts, or while already active. Completion rejects requests without acceptance, during travel, at the wrong destination, or with insufficient cargo.

Observed harness results with Godot 4.5.1:

- validate: import completed without reported script errors.
- scene: scene contract passed; KAN-13/14 economy and KAN-15 contract checks printed passing results. Godot also reported an ObjectDB instances leaked at exit warning.
- smoke: KAN-15 contract checks, existing economy checks, and KAN-10 viewport interaction checks printed passing results.
- export: savepack completed; the exported executable smoke test printed passing contract, economy, and voyage interaction results.

The added headless contract checks cover atomic rejection, origin-only acceptance, destination and cargo gates, exact consumption and reward, unrelated cargo preservation, market inventory preservation, duplicate payout prevention, replay, and scene control construction. Contract button clicks and visual appearance were not manually tested.

Ready for human review; no merge or Jira Done transition performed.
