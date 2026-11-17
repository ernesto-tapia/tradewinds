# KAN-24: Shared demo menu theme

## Affected-screen inventory and before/after

- Port market and trading controls: fixed-position colored rectangles became a shared navy PanelContainer with headings, aligned stock/owned values and native Buy/Sell buttons. Goods scroll within the panel; bulk quantities and totals appear in button text.
- Cargo and wallet panel: a combined text block became container rows with right-aligned coin, capacity and cargo values.
- Contract board and result feedback: separate rectangles became one scrollable themed panel. The relevant Accept or Deliver action uses native disabled handling; details and feedback wrap.
- Existing title, destination status and trade status controls also inherit the shared theme. No new gameplay screens or dialogs were added.

Native Buttons now share normal, hover, pressed, disabled and gold focus styles. Prices, stock, wallet, cargo, contract rewards and voyage rules retain their existing implementations.

## Theme conventions

`game/ui/demo_theme.tres` is the reusable Theme. It uses built-in fonts, flat StyleBoxFlat rectangles, navy panels, light text and teal primary actions. Headings are 22 pixels; default body text is 18 pixels. Warning feedback uses the Warning variation; Error is available for error labels. Panel padding is 12 pixels horizontally and 8 pixels vertically. Button padding is also 12 by 8 pixels. Panel borders are 1 pixel; pressed buttons use 2-pixel borders and keyboard focus uses a 3-pixel gold outline. VBox spacing is 8 pixels, HBox spacing is 12 pixels, and grid spacing is 8 pixels in both directions.

Use `game/ui/menu_ui.gd` for future panels, rows, columns, labels and buttons. Panel roots assign the resource; descendant Controls inherit it. Use Heading, Warning, Error and PrimaryButton variations instead of per-screen color overrides. Containers place content, value rows right-align numbers, and scroll columns wrap long content and follow keyboard focus. Use native focus and disabled properties.

The shared button helper handles Tab and Shift+Tab across separate menu roots. It refreshes navigation links on focus entry and navigation keystrokes, excluding hidden and disabled actions. Enter activation uses native Button behavior.

The logical canvas is 1280x720 and scales through canvas_items at 1920x1080. World placeholders retain flat colors and labeled rectangles as a documented exception: islands, ports, ship and ocean are map objects rather than menus. No external assets or fonts were introduced.

## Review fixes

Replaced the invalid TestScene/ContractBoard global-class test with a Node script that explicitly preloads the existing main and board scripts. The test creates a real game parent, lets the board build through its deferred lifecycle, and supplies origin docking, purchased cargo and destination docking fixtures. It verifies initial inactivity, action visibility and eligibility, acceptance and delivery feedback, exact cargo consumption, the 30-coin reward and the completed count. `game/main.tscn` attaches this check as ContractBoardCheck. Fixtures use an isolated game instance.

The documented heading size and panel padding now match the shared Theme resource.

## Observed validation evidence

All four configured harness checks were executed after the reviewed test script and scene changes. The only subsequent change is this documentation update. The harness supplied the following actual results; it did not supply a commit identifier or underlying command lines, so neither is claimed here.

- `validate`: Godot Engine v4.5.1.stable.official.f62fdbde1 completed filesystem scanning, script-class registration and editor initialization. No script errors were reported.
- `scene`: the scene contract, KAN-13/14 economy and KAN-15 contract checks printed passing results. Godot also reported `WARNING: ObjectDB instances leaked at exit`. This check did not print the deferred KAN-24 test results; their execution is evidenced by smoke and export below.
- `smoke`: printed `KAN-24 contract UI passed: real game parent, initial offer, origin docking, acceptance feedback, cargo and destination gates, delivery feedback, exact cargo consumption and reward, completed controls`. It also printed passing KAN-13/14 economy, KAN-15 contract, KAN-24 theme and KAN-10 voyage interaction results.
- `export`: savepack reached DONE. The output then explicitly identified `Exported executable smoke test:` and Godot v4.5.1.stable.official.f62fdbde1. That executable run printed passing economy, contract, contract UI, theme and voyage interaction results, including the new contract UI fixtures.

Windows build path from the preserved export preset: `build/CaribbeanTradewinds.exe`.

The theme check exercises shared theme identity, five distinct flat button state resources, focus acquisition, Enter activation of Trade at sea and docked, disabled-sale keyboard rejection without wallet/cargo changes, and Tab movement. It checks panel bounds in SubViewports sized 1280x720 and 1920x1080, Trade feedback minimum height and wallet value containment. These assertions do not establish rendered visual quality or exhaustive descendant text fit. The exported executable launch was a smoke test, not a human visual playtest.

## Manual exported-build playtest checklist

Human visual approval remains required before merge. The following items remain unverified by headless testing:

- At both 1280x720 and 1920x1080, inspect every panel for hierarchy, contrast, alignment, clipped labels, hidden buttons and overlap with map interactions.
- Dock at both ports and scroll through every market good and contract feedback; verify wrapping and access to every action.
- Inspect normal, hover, pressed, disabled and focus states. Use Tab, Shift+Tab and keyboard activation, including after action availability changes; verify focus follows scrolling.
- Confirm disabled Buy/Sell and Accept/Deliver actions reject pointer and keyboard activation.
- Buy and sell single units and bulk quantities; verify wallet, cargo, stock and marginal totals.
- Accept at Port A, buy three Sugar, sail to Port B and deliver. Verify exact cargo consumption, 30-coin reward, duplicate rejection and replay after returning to Port A.
- Sail A/B/A/B, inspect progress, test trade rejection at sea and click the current port after arrival.

Human playtest and visual approval are pending. No merge or Jira Done transition was performed.
