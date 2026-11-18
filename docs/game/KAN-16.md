# KAN-16 — Voyage provisioning and consumption

Implemented dock purchases at either port for 2 coins per provision, using a reserve separate from commodity cargo. The demo starts with 12 provisions. Routes consume ceil(distance / 100) provisions once at departure; Port A to Port B requires 4. Insufficient supplies block departure without changing voyage or resource state. The provisions panel shows supplies aboard, route requirements, purchase controls and departure feedback.

Added headless provisioning checks covering dock-only purchases, invalid and unaffordable purchases, separate cargo capacity, insufficient-supply rejection, required-amount feedback, exact supply consumption, repeated-departure rejection, no additional consumption during sailing or arrival, destination resupply, return voyages and distance rounding boundaries.

Fixed the existing voyage adapter's scene construction error and replaced its simulated contract mutations with calls to the real voyage state.

Observed command results using Godot 4.5.1:

- validate: passed after final code changes.
- scene: passed, including the KAN-16 provisioning assertions and existing economy and contract assertions.
- smoke: passed, including provisioning, economy, contracts, contract UI and theme checks.
- export: passed; the exported executable smoke test also passed the provisioning and existing checks.

An earlier scene run failed on the voyage adapter constructor and a repeat contract departure exhausting starter supplies. Both failures were corrected before the successful checks above.

No rendered visual inspection is claimed. Human visual approval and PR merge remain pending; the story is not marked Done.
