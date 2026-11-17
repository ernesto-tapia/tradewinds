# KAN-24: Shared demo menu theme

## Affected-screen inventory and before/after

- Port market and trading controls: fixed-position colored rectangles became a shared navy PanelContainer with a heading, aligned stock/owned values and native Buy/Sell buttons. Goods scroll within the panel; bulk quantities and totals remain visible in button text.
- Cargo and wallet panel: a combined text block became container rows with right-aligned coin, capacity and cargo values.
- Contract board and result feedback: separate rectangles became one scrollable themed panel. The relevant Accept or Deliver action is shown with native disabled handling; long details and feedback wrap.
- Existing title, destination status and trade status panels also inherit the shared theme for consistency. No new gameplay screens or dialogs were added.

Before, action rectangles only changed color and had no native keyboard focus or disabled interaction state. After, native Buttons share normal, hover, pressed, disabled and gold focus styles. Trading and contract eligibility still use the existing state and delivery services. Prices, stock, wallet, cargo, contract rewards and voyage rules were not changed.

## Theme conventions

`game/ui/demo_theme.tres` is the single reusable Theme. It uses built-in fonts, flat StyleBoxFlat rectangles, navy panels, light text and teal primary actions. Heading text is 24 pixels; body text is 18 pixels. Warning text is amber and failed-action feedback uses the Error variation. Panels share 16-pixel horizontal and 12-pixel vertical padding; container spacing and button padding are defined in the resource.

Use `game/ui/menu_ui.gd` to create future panels, rows, columns, labels and buttons. Panel roots assign the resource; descendant Controls inherit it. Use Heading, Warning, Error and PrimaryButton variations instead of per-screen color overrides. Containers own content placement, value rows right-align numbers, and scroll columns wrap long content and follow keyboard focus. Buttons use native focus and disabled properties; do not simulate disabled actions with color alone.

The logical canvas is 1280x720 and scales through canvas_items at 1920x1080. World placeholders retain their existing flat colors and labeled rectangles as a deliberate exception: islands, ports, ship and ocean are map objects rather than menu panels. No external assets, fonts or artwork were introduced.

## Observed validation evidence

Executed configured checks using Godot 4.5.1:

- `validate`: project import completed with no reported script errors.
- `scene`: scene contract passed; economy and delivery checks printed passing results. Godot reported an ObjectDB instances leaked at exit warning.
- `smoke`: economy, delivery, voyage interaction and KAN-24 theme checks printed passing results.
- `export`: savepack completed and the exported executable smoke test printed passing economy, delivery, voyage and KAN-24 theme results.

Windows build: `build/CaribbeanTradewinds.exe`.

The focused KAN-24 check verifies shared theme identity on existing panel roots, panel rectangles against both target bounds, native focusable buttons, distinct state resources, disabled pointer rejection and next-focus discovery. It runs during headless smoke and exported smoke. Its bounds assertions compare logical panel rectangles with target sizes; they do not resize and render both resolutions or prove descendant text fits. The scene check exits before the deferred theme check, so theme coverage comes from smoke/export.

## Manual exported-build playtest checklist

Human visual approval is required before merge. These items remain unverified by the headless results:

- At 1280x720 and 1920x1080, inspect every panel for readable hierarchy, contrast, alignment, clipped labels, hidden buttons and overlap with map interactions.
- Dock at each port; scroll through every market good and all contract feedback. Verify wrapped text stays readable and every action can be reached.
- Inspect normal, hover, pressed, disabled and keyboard-focus button appearance. Use Tab/Shift+Tab and keyboard activation; confirm focus follows scrolling and skips unavailable controls appropriately.
- Confirm disabled Buy/Sell and Accept/Deliver buttons cannot activate through pointer or keyboard.
- Buy and sell single units and bulk quantities; verify wallet, cargo, stock and marginal totals update as before.
- Accept at Port A, buy three Sugar, sail to Port B, deliver once and return to replay. Check exact cargo consumption, 30-coin reward and duplicate-delivery rejection.
- Sail A/B/A/B, inspect voyage progress, test trade rejection at sea and click the current port after arrival.

Ready for QA, Codex review and human exported-build playtest. Visual quality has not been established by text-only checks. No merge or Jira Done transition was performed.
