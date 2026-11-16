extends Node

# Executed by the configured headless scene/smoke checks.
func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        call_deferred("check_economy")

func require_condition(value: bool, message: String) -> bool:
    if not value:
        push_error("KAN-11 economy: " + message)
        get_tree().quit(1)
    return value

func check_economy() -> void:
    var game = get_parent()
    var state = game.game_state
    var fresh = preload("res://data_models.gd").new()
    if not require_condition(state.ports.size() == 2 and state.goods.size() == 2 and state.markets.size() == 2 and state.contracts.size() == 1, "all fixed model fixtures must initialize"):
        return
    if not require_condition(state.wallet.coins == 100 and state.cargo.total() == 0 and state.ship.cargo == state.cargo and not state.voyage.active, "wallet, cargo, ship and voyage must initialize consistently"):
        return
    var contract = state.contracts["deliver_sugar"]
    if not require_condition(contract.destination_id == "Port B" and contract.good_id == "sugar" and contract.quantity == 3 and contract.reward == 30 and not contract.completed, "contract must reference seeded fixtures"):
        return
    if not require_condition(not game.buy("sugar", 1) and not game.sell("sugar", 1) and state.wallet.coins == 100, "runtime transactions must reject trading at sea"):
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
    print("KAN-11 economy passed: seeded models, scene shared-state buy/sell, voyage docking, UI balances, independent fixtures and atomic transaction rejection verified")
