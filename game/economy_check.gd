extends Node

const Models = preload("res://data_models.gd")

func check_buy(good_id: String, quantity: int) -> bool:
    return get_parent().buy(good_id, quantity)

func check_sell(good_id: String, quantity: int) -> bool:
    return get_parent().sell(good_id, quantity)

func check_can_trade() -> bool:
    return get_parent().can_trade()

func snapshot(state) -> Dictionary:
    var markets: Dictionary = {}
    for port_id in state.markets:
        markets[port_id] = {
            "inventory": state.markets[port_id].inventory.duplicate(true),
            "prices": state.markets[port_id].prices.duplicate(true)
        }
    return {"coins": state.wallet.coins, "cargo": state.cargo.quantities.duplicate(true), "markets": markets}

func require_condition(value: bool, message: String) -> bool:
    if not value:
        push_error("Economy: " + message)
        get_tree().quit(1)
    return value

func depart_and_return(state) -> bool:
    var origin: String = state.docked_port_id
    var destination: String = "Port B" if origin == "Port A" else "Port A"
    if not state.start_voyage(destination):
        return false
    state.advance_voyage(100.0)
    if not state.start_voyage(origin):
        return false
    state.advance_voyage(100.0)
    return state.docked_port_id == origin

func check_price_response() -> bool:
    var state = Models.new()
    state.docked_port_id = "Port A"
    state.ship.position = state.ports["Port A"].position
    var market = state.markets["Port A"]
    var other_prices: Dictionary = state.markets["Port B"].prices.duplicate(true)
    if not require_condition(state.buy("sugar", 3) and market.prices["sugar"] == 5 and state.wallet.coins == 85, "purchase must retain the visit quote"):
        return false
    if not require_condition(state.sell("sugar", 3) and state.wallet.coins == 100 and market.prices["sugar"] == 5, "same-visit round trip must not generate profit"):
        return false
    if not require_condition(state.buy("sugar", 3), "net purchase fixture"):
        return false
    var before: Dictionary = snapshot(state)
    if not require_condition(not state.start_voyage("Port A") and not state.start_voyage("missing") and snapshot(state) == before, "current-port and invalid destinations must not settle prices"):
        return false
    if not require_condition(depart_and_return(state) and market.prices["sugar"] == 8, "departure must apply net scarcity and retain it on return"):
        return false
    if not require_condition(state.sell("sugar", 3) and market.prices["sugar"] == 8 and depart_and_return(state) and market.prices["sugar"] == 5, "sale must lower the next visit quote only after departure"):
        return false
    if not require_condition(market.prices["rum"] == 10 and market.prices["coffee"] == 12 and state.markets["Port B"].prices == other_prices, "supply response must remain local to port and good"):
        return false
    state.wallet.coins = 10000
    if not require_condition(state.buy_all("sugar") and market.prices["sugar"] == 5 and depart_and_return(state) and market.prices["sugar"] == 10, "scarcity must clamp at maximum on departure"):
        return false
    if not require_condition(state.sell_all("sugar") and depart_and_return(state) and market.prices["sugar"] == 5, "reversing saturated scarcity must restore base price"):
        return false
    state.cargo.quantities["sugar"] = 20
    if not require_condition(state.sell_all("sugar") and depart_and_return(state) and market.prices["sugar"] == 1, "abundance must clamp at positive minimum"):
        return false
    if not require_condition(state.buy_all("sugar") and depart_and_return(state) and market.prices["sugar"] == 5, "reversing abundance must restore base price without drift"):
        return false
    var first = Models.new()
    var second = Models.new()
    for fixture in [first, second]:
        fixture.docked_port_id = "Port B"
        if not require_condition(fixture.buy("rum", 2) and fixture.sell("rum", 1) and not fixture.buy("missing", 1) and depart_and_return(fixture), "deterministic replay fixture"):
            return false
    return require_condition(snapshot(first) == snapshot(second), "identical trades and voyages must produce identical balances and quotes")

func _ready() -> void:
    if DisplayServer.get_name() != "headless":
        return
    var state = Models.new()
    var before: Dictionary = snapshot(state)
    if not require_condition(not state.buy_all("sugar") and not state.sell_all("sugar") and snapshot(state) == before, "at-sea bulk trades must reject atomically"):
        return
    state.docked_port_id = "Port A"
    if not require_condition(state.buy("sugar", 3) and state.sell("sugar", 2) and state.wallet.coins == 95 and state.cargo.quantity("sugar") == 1 and state.markets["Port A"].inventory["sugar"] == 19, "single and batch trades must settle at the unchanged visit quote"):
        return
    for good_id in ["sugar", "missing"]:
        for quantity in [-1, 0, 100]:
            before = snapshot(state)
            if not require_condition(not state.buy(good_id, quantity) and not state.sell(good_id, quantity) and snapshot(state) == before, "invalid trades must preserve all balances and quotes"):
                return
    before = snapshot(state)
    if not require_condition(not state.buy("coffee", 9) and not state.sell("sugar", 2) and snapshot(state) == before, "insufficient funds and overselling must reject atomically"):
        return
    if not require_condition(state.max_buy_quantity("coffee") == 7 and state.buy_all("coffee") and state.wallet.coins == 11 and state.cargo.quantity("coffee") == 7, "buy all must floor affordable quantity"):
        return
    state.wallet.coins = 10000
    if not require_condition(state.buy_all("rum") and state.cargo.quantity("rum") == 10 and state.buy_all("sugar") and state.cargo.total() == 20, "buy all must respect stock and shared cargo capacity"):
        return
    before = snapshot(state)
    if not require_condition(not state.buy_all("sugar") and snapshot(state) == before, "full hold bulk purchase must reject atomically"):
        return
    if not require_condition(state.sell_all("coffee") and state.cargo.quantity("coffee") == 0 and state.cargo.quantity("rum") == 10, "sell all must sell only the selected good"):
        return
    before = snapshot(state)
    if not require_condition(not state.sell_all("coffee") and not state.buy_all("missing") and not state.sell_all("missing") and snapshot(state) == before, "empty and unknown bulk trades must reject atomically"):
        return
    if not require_condition(state.start_voyage("Port B"), "departure fixture"):
        return
    before = snapshot(state)
    if not require_condition(not state.buy("sugar", 1) and not state.sell("rum", 1) and not state.buy_all("sugar") and not state.sell_all("rum") and snapshot(state) == before, "voyage must block all trades"):
        return
    state = Models.new()
    state.docked_port_id = "Port A"
    if not require_condition(state.buy_all("sugar") and state.wallet.coins == 0 and state.cargo.total() == 20 and state.markets["Port A"].inventory["sugar"] == 0, "exact funds, stock and capacity must succeed"):
        return
    if not check_price_response():
        return
    print("KAN-13/14 economy passed: fixed visit quotes, no same-visit round-trip profit, departure settlement, local deterministic bounded prices, bulk limits and atomic rejections")
