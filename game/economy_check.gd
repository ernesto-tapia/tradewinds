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

func check_price_response() -> bool:
    var state = Models.new()
    state.docked_port_id = "Port A"
    state.ship.position = state.ports["Port A"].position
    var market = state.markets["Port A"]
    var remote: Dictionary = state.markets["Port B"].prices.duplicate(true)
    if not require_condition(state.buy("sugar", 3) and state.wallet.coins == 82 and market.prices["sugar"] == 8, "buy batch must charge 5+6+7 and immediately raise subsequent quote"):
        return false
    if not require_condition(state.sell("sugar", 1) and state.wallet.coins == 89 and market.prices["sugar"] == 7, "first sale must receive 7 and lower subsequent quote"):
        return false
    if not require_condition(state.sell("sugar", 1) and state.wallet.coins == 95 and market.prices["sugar"] == 6, "second sale must receive 6 and lower subsequent quote again"):
        return false
    if not require_condition(state.sell("sugar", 1) and state.wallet.coins == 100 and market.prices["sugar"] == 5, "reversing purchase must restore balances without profit"):
        return false
    state.cargo.quantities["sugar"] = 3
    var original: Dictionary = snapshot(state)
    if not require_condition(state.sell_all("sugar") and market.prices["sugar"] == 2 and state.wallet.coins == 109, "sales must immediately increase supply and reduce quote"):
        return false
    if not require_condition(state.buy("sugar", 3) and snapshot(state) == original, "selling then buying must not create round-trip profit"):
        return false
    state.cargo.quantities["sugar"] = 0
    state.wallet.coins = 10000
    if not require_condition(state.buy_all("sugar") and market.prices["sugar"] == 10 and state.cargo.total() == 20, "scarcity must clamp immediately at maximum"):
        return false
    if not require_condition(state.sell_all("sugar") and market.prices["sugar"] == 5 and state.wallet.coins == 10000, "reversing saturated scarcity must restore price and wallet"):
        return false
    state.cargo.quantities["sugar"] = 20
    if not require_condition(state.sell_all("sugar") and market.prices["sugar"] == 1, "abundance must clamp immediately at positive minimum"):
        return false
    if not require_condition(state.buy_all("sugar") and market.prices["sugar"] == 5 and state.wallet.coins == 10000, "reversing saturated abundance must restore price and wallet"):
        return false
    if not require_condition(market.prices["rum"] == 10 and market.prices["coffee"] == 12 and state.markets["Port B"].prices == remote, "response must remain local to traded port and good"):
        return false
    var before: Dictionary = snapshot(state)
    if not require_condition(not state.start_voyage("Port A") and not state.start_voyage("missing") and snapshot(state) == before, "invalid departures must preserve economy"):
        return false
    if not require_condition(state.start_voyage("Port B") and snapshot(state) == before, "departure must not apply a second price adjustment"):
        return false
    state.advance_voyage(100.0)
    if not require_condition(state.start_voyage("Port A"), "return voyage must start"):
        return false
    state.advance_voyage(100.0)
    if not require_condition(snapshot(state) == before, "voyages must retain local inventory and quotes"):
        return false
    var first = Models.new()
    var second = Models.new()
    for fixture in [first, second]:
        fixture.docked_port_id = "Port B"
        if not require_condition(fixture.buy("rum", 2) and fixture.sell("rum", 1), "deterministic replay fixture"):
            return false
    return require_condition(snapshot(first) == snapshot(second), "identical trades must produce identical balances and quotes")

func _ready() -> void:
    if DisplayServer.get_name() != "headless":
        return
    var state = Models.new()
    var before: Dictionary = snapshot(state)
    if not require_condition(not state.buy_all("sugar") and not state.sell_all("sugar") and snapshot(state) == before, "at-sea bulk trades must reject atomically"):
        return
    state.docked_port_id = "Port A"
    for good_id in ["sugar", "missing"]:
        for quantity in [-1, 0, 100]:
            before = snapshot(state)
            if not require_condition(not state.buy(good_id, quantity) and not state.sell(good_id, quantity) and snapshot(state) == before, "invalid trades must preserve balances and quotes"):
                return
    before = snapshot(state)
    if not require_condition(not state.buy("coffee", 7) and not state.sell("sugar", 1) and snapshot(state) == before, "cumulative unaffordable batch and overselling must reject atomically"):
        return
    if not require_condition(state.max_buy_quantity("coffee") == 6 and state.buy_all("coffee") and state.wallet.coins == 13 and state.cargo.quantity("coffee") == 6, "buy all must account for rising marginal prices: 12 through 17"):
        return
    state.wallet.coins = 10000
    if not require_condition(state.buy_all("rum") and state.cargo.quantity("rum") == 10 and state.buy_all("sugar") and state.cargo.total() == 20, "buy all must respect stock and shared capacity"):
        return
    before = snapshot(state)
    if not require_condition(not state.buy_all("sugar") and snapshot(state) == before, "full hold must reject atomically"):
        return
    if not require_condition(state.sell_all("coffee") and state.cargo.quantity("coffee") == 0 and state.cargo.quantity("rum") == 10, "sell all must affect only selected cargo"):
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
    state.wallet.coins = 185
    if not require_condition(state.buy_all("sugar") and state.wallet.coins == 0 and state.cargo.total() == 20 and state.markets["Port A"].inventory["sugar"] == 0, "exact cumulative funds, stock and capacity must succeed"):
        return
    if not check_price_response():
        return
    print("KAN-13/14 economy passed: immediate local bounded price response, marginal batch pricing, no round-trip profit, deterministic replay, bulk limits and atomic rejections")
