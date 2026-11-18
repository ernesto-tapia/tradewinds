extends Node

const UI = preload("res://ui/menu_ui.gd")
const Main = preload("res://main.gd")
const Board = preload("res://contract_board.gd")
var failed: bool = false

func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        call_deferred("check_theme")

func require_condition(value: bool, message: String) -> bool:
    if not value:
        failed = true
        push_error("KAN-24 theme: " + message)
        get_tree().quit(1)
    return value

func activate(viewport: SubViewport, button: Button) -> void:
    button.grab_focus()
    if not require_condition(viewport.gui_get_focus_owner() == button, button.name + " must receive keyboard focus"):
        return
    # Deliver one complete keystroke before yielding. The concurrent voyage
    # regression sends root-window mouse clicks, which can steal GUI focus.
    for down in [true, false]:
        var event := InputEventKey.new()
        event.keycode = KEY_ENTER
        event.physical_keycode = KEY_ENTER
        event.pressed = down
        viewport.push_input(event, true)
    await get_tree().process_frame

func check_theme() -> void:
    var host := SubViewportContainer.new()
    host.position = Vector2(3000, 0)
    host.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(host)
    var viewport := SubViewport.new()
    viewport.size = Vector2i(1280, 720)
    viewport.handle_input_locally = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    host.add_child(viewport)
    viewport.gui_disable_input = false
    var game = Main.new()
    viewport.add_child(game)
    var board = Board.new()
    game.add_child(board)
    await get_tree().process_frame
    await get_tree().process_frame
    for id in ["Title", "Destination", "Economy", "Market", "ContractPanel"]:
        require_condition(game.get_node(id).theme == UI.DEMO_THEME, id + " must use the shared theme")
    var buttons: Array[Button] = [game.trade_button, board.accept_button, board.complete_button]
    for good_id in game.buy_buttons:
        buttons.append(game.buy_buttons[good_id])
        buttons.append(game.buy_all_buttons[good_id])
        buttons.append(game.sell_buttons[good_id])
        buttons.append(game.sell_all_buttons[good_id])
    buttons.append(game.commodity_selector)
    for choice in game.commodity_choices.values():
        buttons.append(choice)
    for button in buttons:
        require_condition(button.focus_mode == Control.FOCUS_ALL, button.name + " must support keyboard focus")
        var styles: Array[StyleBox] = []
        for state in ["normal", "hover", "pressed", "disabled", "focus"]:
            var style: StyleBox = button.get_theme_stylebox(state)
            require_condition(style is StyleBoxFlat, button.name + " needs a flat " + state + " style")
            require_condition(not styles.has(style), button.name + " needs distinct " + state + " styling")
            styles.append(style)
    var activations: Array[int] = [0]
    game.trade_button.pressed.connect(func(): activations[0] += 1)
    game.trade_feedback.text = "Awaiting keyboard permission query"
    await activate(viewport, game.trade_button)
    if not require_condition(activations[0] == 1 and "unavailable" in game.trade_feedback.text and not game.can_trade(), "Enter must activate Trade and report rejection at sea; activations=%d, feedback=%s" % [activations[0], game.trade_feedback.text]):
        return
    game.sail_to(game.get_node("Port A"))
    game._process(game.voyage_time + 1.0)
    game.set_process(false)
    game.trade_feedback.text = "Awaiting docked keyboard permission query"
    await activate(viewport, game.trade_button)
    if not require_condition(activations[0] == 2 and "permitted" in game.trade_feedback.text and game.can_trade(), "Enter must activate Trade while docked"):
        return
    var disabled_button: Button = game.sell_buttons["sugar"]
    require_condition(disabled_button.disabled, "selling empty cargo must remain disabled")
    var coins: int = game.game_state.wallet.coins
    var sales: Array[int] = [0]
    disabled_button.pressed.connect(func(): sales[0] += 1)
    await activate(viewport, disabled_button)
    require_condition(sales[0] == 0 and game.game_state.wallet.coins == coins and game.game_state.cargo.quantity("sugar") == 0, "keyboard input must not activate disabled sales")
    game.trade_button.grab_focus()
    var tab := InputEventKey.new()
    tab.keycode = KEY_TAB
    tab.physical_keycode = KEY_TAB
    tab.pressed = true
    viewport.push_input(tab, true)
    require_condition(viewport.gui_get_focus_owner() != null and viewport.gui_get_focus_owner() != game.trade_button, "Tab must navigate from Trade to another enabled control")
    tab = tab.duplicate()
    tab.pressed = false
    viewport.push_input(tab, true)
    for menu in ["contracts", "cargo", "market"]:
        game.menu_buttons[menu].grab_focus()
        await activate(viewport, game.menu_buttons[menu])
        require_condition(game.active_menu == menu, "navigation must open " + menu)
        require_condition(game.market_panel.visible == (menu == "market"), "market must not compete with another panel")
        require_condition(board.panel.visible == (menu == "contracts"), "contracts must not compete with another panel")
        require_condition(game.get_node("Economy").visible == (menu == "cargo"), "cargo must not compete with another panel")
    game.select_commodity("coffee")
    for good_id in game.commodity_sections:
        require_condition(game.commodity_sections[good_id].visible == (good_id == "coffee"), "only the selected commodity should be shown")
    game.select_commodity("sugar")
    for resolution in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
        viewport.size = resolution
        await get_tree().process_frame
        await get_tree().process_frame
        var bounds := Rect2(Vector2.ZERO, Vector2(resolution))
        for id in ["Title", "Destination", "Trade", "Economy", "Market", "ContractPanel"]:
            var panel: Control = game.get_node(id)
            require_condition(bounds.encloses(panel.get_global_rect()), "%s %s must fit at %s" % [id, panel.get_global_rect(), resolution])
        require_condition(game.trade_feedback.size.y >= game.trade_feedback.get_minimum_size().y, "Trade feedback must fit its button")
        require_condition(game.wallet_value.get_global_rect().end.x <= game.get_node("Economy").get_global_rect().end.x, "wallet values must fit the cargo panel")
        for menu in ["contracts", "cargo", "market"]:
            game.show_menu(menu)
            await get_tree().process_frame
            await get_tree().process_frame
            var panel_id: String = {"contracts": "ContractPanel", "cargo": "Economy", "market": "Market"}[menu]
            var detail: Control = game.get_node(panel_id)
            require_condition(bounds.encloses(detail.get_global_rect()), menu + " content must fit when opened")
        require_condition(not game.commodity_selector is OptionButton and game.commodity_selector.icon == null, "chooser must be a text-only button with no native arrow")
        require_condition(UI.DEMO_THEME.get_stylebox("panel", "PopupMenu") is StyleBoxFlat, "PopupMenu must have shared flat panel styling")
        require_condition(UI.DEMO_THEME.get_stylebox("hover", "PopupMenu") is StyleBoxFlat, "PopupMenu must have shared flat hover styling")
        await activate(viewport, game.commodity_selector)
        await get_tree().process_frame
        require_condition(game.commodity_chooser.is_visible_in_tree(), "Enter must open the chooser")
        require_condition(game.commodity_chooser.theme == UI.DEMO_THEME, "opened chooser must use shared theme")
        require_condition(not game.commodity_content.is_visible_in_tree(), "opened chooser must replace transaction details")
        require_condition(game.market_panel.get_global_rect().encloses(game.commodity_chooser.get_global_rect()), "opened chooser must fit inside market")
        for choice in game.commodity_choices.values():
            require_condition(choice.icon == null and choice.is_visible_in_tree(), "choices must be visible text-only buttons")
            require_condition(bounds.encloses(choice.get_global_rect()), "opened choice must fit viewport")
        await activate(viewport, game.commodity_choices["coffee"])
        require_condition(game.selected_good == "coffee" and not game.commodity_chooser.visible, "Enter must select commodity and close chooser")
        require_condition(viewport.gui_get_focus_owner() == game.commodity_selector, "selection must restore chooser focus")
        await activate(viewport, game.commodity_selector)
        for down in [true, false]:
            var escape := InputEventKey.new()
            escape.keycode = KEY_ESCAPE
            escape.pressed = down
            viewport.push_input(escape, true)
        require_condition(not game.commodity_chooser.visible and game.selected_good == "coffee", "Escape must close without changing selection")
        game.select_commodity("sugar")
    host.queue_free()
    if not failed:
        print("KAN-24 theme passed: shared panels and flat popup styles; five button states; keyboard Trade and tab navigation; disabled sale rejection; exclusive menu tabs; text-only opened chooser, commodity selection, Escape and focus restoration; opened bounds at 1280x720 and 1920x1080. Human visual approval remains pending.")
