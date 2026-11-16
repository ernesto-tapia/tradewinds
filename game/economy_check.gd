extends Node

# Executed by the configured headless scene/smoke checks.
func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        call_deferred("check_economy")

func require_condition(value: bool, message: String) -> bool:
    if not value:
        push_error("KAN-11/KAN-12 economy: " + message)
        get_tree().quit(1)
    return value

func check_economy() -> void:
    var game = get_parent()
    var state = game.game_state
    var fresh = preload("res://data_models.gd").new()
    if not require_condition(state.ports.size() == 2 and state.goods.size() == 3 and state.markets.size() == 2 and state.contracts.size() == 1, "two ports, three current-story goods, two markets and one contract must initialize"):
        return
    if not require_condition(state.wallet.coins == 100 and state.cargo.total() == 0 and state.ship.cargo == state.cargo and not state.voyage.active, "wallet, cargo, ship and voyage must initialize consistently"):
        return
    var contract = state.contracts["deliver_sugar"]
    if not require_condition(contract.destination_id == "Port B" and contract.good_id == "sugar" and contract.quantity == 3 and contract.reward == 30 and not contract.completed, "contract must reference seeded fixtures"):
        return
    if not require_condition(not game.buy("sugar", 1) and not game.sell("sugar", 1) and state.wallet.coins == 100, "runtime transactions must reject trading at sea"):
        return
    if not require_condition(not game.market_panel.visible and game.market_rows.size() == 3 and game.buy_buttons.size() == 3 and game.sell_buttons.size() == 3, "market must create three rows and buy/sell controls once and remain hidden at sea"):
        return
    for good_id in state.goods:
        var a = fresh.markets["Port A"]
        var b = fresh.markets["Port B"]
        if not require_condition(a.inventory.has(good_id) and b.inventory.has(good_id) and int(a.inventory[good_id]) > 0 and int(b.inventory[good_id]) > 0 and int(a.prices[good_id]) > 0 and int(b.prices[good_id]) > 0 and a.prices[good_id] != b.prices[good_id] and a.inventory[good_id] != b.inventory[good_id], "each good needs positive stock and distinct initial prices and stock across ports"):
            return
    var port = game.get_node("Port B") as Control
    game.sail_to(port)
    game._process(game.voyage_time + 1.0)
    if not require_condition(game.can_trade() and state.docked_port_id == "Port B" and state.ship.position == port.position and not state.voyage.active, "scene arrival must update shared voyage and ship state"):
        return
    var market = state.markets["Port B"]
    if not require_condition(game.buy("sugar", 3) and state.wallet.coins == 76 and state.cargo.quantity("sugar") == 3 and market.inventory["sugar"] == 7, "buy must update shared wallet, cargo and market stock"):
        return
    if not require_condition(game.sell("sugar", 2) and state.wallet.coins == 92 and state.ship.cargo.quantity("sugar") == 1 and market.inventory["sugar"] == 9, "sell must update the same shared objects"):
        return
    for quantity in [0, -1, 1000000]:
        if not require_condition(not game.buy("sugar", quantity) and not game.sell("sugar", quantity), "invalid quantities must be rejected"):
            return
    if not require_condition(not game.buy("unknown", 1) and not game.sell("unknown", 1) and not game.sell("sugar", 2), "unknown goods and insufficient cargo must be rejected"):
        return
    if not require_condition(state.wallet.coins == 92 and state.cargo.quantity("sugar") == 1 and market.inventory["sugar"] == 9, "rejected transactions must leave all balances unchanged"):
        return
    if not require_condition("Coins: 92" in game.economy_feedback.text and "Sugar 1" in game.economy_feedback.text, "runtime feedback must reflect economic changes"):
        return
    if not require_condition(fresh.wallet.coins == 100 and fresh.cargo.total() == 0 and fresh.markets["Port B"].inventory["sugar"] == 10, "new fixture instances must be independent"):
        return
    fresh.docked_port_id = "Port A"
    fresh.wallet.coins = 1000
    fresh.ship.capacity = 1
    if not require_condition(not fresh.buy("sugar", 2) and fresh.wallet.coins == 1000 and fresh.cargo.total() == 0, "capacity rejection must be atomic"):
        return
    fresh.ship.capacity = 100
    if not require_condition(not fresh.buy("sugar", 21) and fresh.markets["Port A"].inventory["sugar"] == 20, "insufficient stock must be rejected"):
        return
    fresh.wallet.coins = 4
    if not require_condition(not fresh.buy("sugar", 1) and fresh.wallet.coins == 4 and fresh.cargo.total() == 0, "insufficient funds must be rejected"):
        return
    print("KAN-11 economy passed: shared-state transactions, voyage docking, UI balances, independent fixtures and atomic rejection verified")
    var node_count: int = game.get_child_count()
    for port_id in ["Port B", "Port A", "Port B"]:
        if state.docked_port_id != port_id:
            game.sail_to(game.get_node(port_id))
            if not require_condition(not game.market_panel.visible, "departure must hide the market"):
                return
            game._process(game.voyage_time + 1.0)
        if not require_condition(game.market_panel.visible and port_id in game.market_title.text and ("Wallet: %d coins" % state.wallet.coins) in game.market_title.text, "docked market must show the current port and wallet"):
            return
        for good_id in state.goods:
            var current = state.markets[port_id]
            var expected: String = "%s | Stock %d | %d coins/unit | Owned %d" % [state.goods[good_id].name, current.inventory[good_id], current.prices[good_id], state.cargo.quantity(good_id)]
            if not require_condition(game.market_rows[good_id].text == expected, "market row must display current good, stock, unit price and cargo"):
                return
            var coins_before: int = state.wallet.coins
            var stock_before: int = int(current.inventory[good_id])
            var owned_before: int = state.cargo.quantity(good_id)
            var price: int = int(current.prices[good_id])
            var event := InputEventMouseButton.new()
            event.button_index = MOUSE_BUTTON_LEFT
            event.pressed = true
            game.buy_buttons[good_id].gui_input.emit(event)
            if not require_condition(state.wallet.coins == coins_before - price and int(current.inventory[good_id]) == stock_before - 1 and state.cargo.quantity(good_id) == owned_before + 1 and ("Wallet: %d coins" % state.wallet.coins) in game.market_title.text and ("Stock %d" % (stock_before - 1)) in game.market_rows[good_id].text, "every buy control must update balances and visible market values"):
                return
            game.sell_buttons[good_id].gui_input.emit(event)
            if not require_condition(state.wallet.coins == coins_before and int(current.inventory[good_id]) == stock_before and state.cargo.quantity(good_id) == owned_before and game.market_rows[good_id].text == expected and ("Wallet: %d coins" % coins_before) in game.market_title.text, "every sell control must update balances and visible market values"):
                return
        var snapshot: Dictionary = game.get_market_data(port_id)
        snapshot["inventory"]["coffee"] = -100
        if not require_condition(int(state.markets[port_id].inventory["coffee"]) >= 0 and game.get_child_count() == node_count, "market snapshots must be independent and travel must reuse static UI"):
            return
    print("KAN-12 market passed: three goods at both ports, distinct initial stock/prices, dock-only market, wallet, all buy/sell signals, refreshed rows and static UI verified")
