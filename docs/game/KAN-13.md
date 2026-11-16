# KAN-13: Buy and sell with money and cargo checks

Purchases deduct coins, add cargo and decrease docked market stock. Sales remove cargo, credit coins and increase stock. Each unit occupies one of 20 shared cargo slots. Transactions reject invalid goods, nonpositive quantities, insufficient stock, insufficient funds, insufficient capacity, overselling and trading at sea before changing balances.

The review repair restores a shared require_condition helper in game/economy_check.gd. Failed conditions call the built-in push_error and get_tree().quit(1); each caller returns immediately. This replaces the invalid custom push_error helper that called nonexistent Node.quit(). Headless economy checks use independent fixtures so they preserve the player's initial state and the voyage interaction checks. Public check_buy, check_sell and check_can_trade probes still delegate to the running scene.

Assertions cover exact purchase deductions and sale credits, cargo and stock changes, atomic rejection, mixed cargo capacity, capacity reuse after selling, independent port stocks, destination pricing, voyage restrictions, and a purchase exhausting funds, stock and capacity exactly.

Observed harness results on Godot 4.5.1:

- validate completed without script parse errors.
- A temporary EconomyFailureProbe attachment called require_condition(false, "deliberately failing economy condition for exit-code verification"). The configured scene check returned an error containing that condition. The harness response did not expose a numeric process exit code, so this demonstrates configured-check failure detection rather than independently proving the process exit status. Negative smoke and export runs were not performed because scene is their prerequisite.
- The probe attachment was removed and main.tscn restored before final validation. game/economy_failure_probe.gd remains available for reproducing the deliberate failure and is not attached to the normal scene.
- Final validate and scene checks passed. Scene printed the economy success message and labeled rectangle contract success, plus an ObjectDB instances leaked at exit warning.
- Final smoke passed, printing the economy success message and the KAN-10 voyage interaction success message.
- Final export completed Windows executable packaging. Its exported executable smoke test printed both the economy and voyage interaction success messages.

These results are automated headless assertions. Manual market interaction and visual testing were not performed. Human review and merge remain pending; the story is not marked Done.
