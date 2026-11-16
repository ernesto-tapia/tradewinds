extends Node

const Models = preload("res://data_models.gd")

# Public probes use the same transaction and refresh path as the market controls.
func check_buy(good_id: String, quantity: int) -> bool:
    return get_parent().buy(good_id, quantity)

func check_sell(good_id: String, quantity: int) -> bool:
    return get_parent().sell(good_id, quantity)

func check_can_trade() -> bool:
    return get_parent().can_trade()

func snapshot(state) -> Dictionary:
    var inventories: Dictionary = {}
    var prices: Dictionary = {}
    for port_id in state.markets:
        inventories[port_id] = state.markets[port_id].inventory.duplicate(true)
        prices[port_id] = state.markets[port_id].prices.duplicate(true)
    return {
        "coins": state.wallet.coins,
        "cargo": state.cargo.quantities.duplicate(true),
        "inventories": inventories,
        "prices": prices
    }

func require_condition(value: bool, message: String) -> bool:
    if not value:
        push_error("Economy: " + message)
        get_tree().quit(1)
    return value

func check_price_response() -> bool:
    var state = Models.new()
    state.docked_port_id = "Port A"
    var market = state.markets["Port A"]
    var other_port: Dictionary = state.markets["Port B"].prices.duplicate(true)
    if not require_condition(state.buy("sugar", 3) and market.prices["sugar"] == 8 and state.wallet.coins == 85, "buy must settle at displayed quote then raise subsequent price with reduced supply"):
        return false
    if not require_condition(state.sell("sugar", 1) and state.wallet.coins == 93 and market.inventory["sugar"] == 18 and market.prices["sugar"] == 7, "sale must credit current quote then lower subsequent sell price"):
        return false
    if not require_condition(state.sell("sugar", 1) and state.wallet.coins == 100 and market.prices["sugar"] == 6, "next sale must use the reduced quote"):
        return false
    if not require_condition(market.prices["rum"] == 10 and market.prices["coffee"] == 12 and state.markets["Port B"].prices == other_port, "price response must remain local to the traded port and good"):
        return false
    # Test upper saturation through accepted purchases, then reverse supply.
    state = Models.new()
    state.docked_port_id = "Port A"
    state.wallet.coins = 10000
    market = state.markets["Port A"]
    if not require_condition(state.buy("sugar", 20) and market.prices["sugar"] == market.maximum_prices["sugar"] and market.prices["sugar"] == 10, "scarcity must clamp at maximum price"):
        return false
    if not require_condition(state.sell("sugar", 20) and market.prices["sugar"] == 5, "restoring initial stock must restore base price without clamp drift"):
        return false
    # Cargo fixture represents supply brought from elsewhere.
    state.cargo.quantities["sugar"] = 20
    if not require_condition(state.sell("sugar", 20) and market.prices["sugar"] == market.minimum_prices["sugar"] and market.prices["sugar"] == 1, "abundant supply must clamp at positive minimum price"):
        return false
    if not require_condition(state.buy("sugar", 20) and market.prices["sugar"] == 5, "reversing abundant supply must restore base price"):
        return false
    # Identical accepted and rejected trade sequences must produce identical state.
    var first = Models.new()
    var second = Models.new()
    for fixture in [first, second]:
        fixture.docked_port_id = "Port B"
        if not require_condition(fixture.buy("rum", 2) and fixture.sell("rum", 1) and not fixture.buy("missing", 1), "determinism sequence must exercise successful and rejected trades"):
            return false
    if not require_condition(snapshot(first) == snapshot(second), "same initial state and trades must give identical prices and balances"):
        return false
    return true

func _ready() -> void:
    if DisplayServer.get_name() != "headless":
        return
    # Independent fixtures leave the player's initial state and voyage checks intact.
    var state = Models.new()
    var before: Dictionary = snapshot(state)
    if not require_condition(not state.buy("sugar", 1) and not state.sell("sugar", 1) and snapshot(state) == before, "at-sea trades must be rejected atomically"):
        return
    state.docked_port_id = "Port A"
    if not require_condition(state.can_trade(), "docking must enable trade"):
        return
    if not require_condition(state.buy("sugar", 3), "purchase must succeed"):
        return
    if not require_condition(state.wallet.coins == 85 and state.cargo.quantity("sugar") == 3 and state.markets["Port A"].inventory["sugar"] == 17, "purchase must deduct cost and update cargo and stock exactly once"):
        return
    if not require_condition(state.sell("sugar", 2), "sale must succeed"):
        return
    if not require_condition(state.wallet.coins == 101 and state.cargo.quantity("sugar") == 1 and state.markets["Port A"].inventory["sugar"] == 19, "sale must credit the updated quote and update cargo and stock exactly once"):
        return
    for good_id in ["sugar", "missing"]:
        for quantity in [-1, 0, 100]:
            before = snapshot(state)
            if not require_condition(not state.buy(good_id, quantity) and snapshot(state) == before, "invalid purchase must preserve balances and prices"):
                return
            if not require_condition(not state.sell(good_id, quantity) and snapshot(state) == before, "invalid sale must preserve balances and prices"):
                return
    before = snapshot(state)
    if not require_condition(not state.buy("coffee", 9) and snapshot(state) == before, "insufficient funds must reject purchase atomically"):
        return
    if not require_condition(not state.sell("sugar", 2) and snapshot(state) == before, "overselling must be rejected atomically"):
        return
    state.wallet.coins = 1000
    if not require_condition(state.buy("rum", 10) and state.buy("coffee", 9) and state.cargo.total() == 20, "mixed cargo must fill shared capacity"):
        return
    before = snapshot(state)
    if not require_condition(not state.buy("sugar", 1) and snapshot(state) == before, "full cargo must reject purchase atomically"):
        return
    if not require_condition(state.sell("rum", 1) and state.buy("sugar", 1) and state.cargo.total() == 20, "selling must release reusable cargo capacity"):
        return
    var port_a_stock: Dictionary = state.markets["Port A"].inventory.duplicate(true)
    var port_a_prices: Dictionary = state.markets["Port A"].prices.duplicate(true)
    state.docked_port_id = "Port B"
    var coins: int = state.wallet.coins
    if not require_condition(state.sell("sugar", 1) and state.wallet.coins == coins + 8 and state.markets["Port B"].inventory["sugar"] == 11, "destination sale must use destination price and stock"):
        return
    if not require_condition(state.markets["Port A"].inventory == port_a_stock and state.markets["Port A"].prices == port_a_prices, "trading at B must preserve A stock and prices"):
        return
    state.start_voyage("Port A")
    before = snapshot(state)
    if not require_condition(not state.can_trade() and not state.buy("sugar", 1) and not state.sell("rum", 1) and snapshot(state) == before, "voyage must block all transactions atomically"):
        return
    state = Models.new()
    state.docked_port_id = "Port A"
    if not require_condition(state.buy("sugar", 20), "exact funds, stock and capacity purchase must succeed"):
        return
    if not require_condition(state.wallet.coins == 0 and state.cargo.total() == 20 and state.markets["Port A"].inventory["sugar"] == 0, "boundary purchase must leave zero coins and stock without negative balances"):
        return
    before = snapshot(state)
    if not require_condition(not state.buy("sugar", 1) and snapshot(state) == before, "purchase beyond exhausted limits must preserve balances and prices"):
        return
    if not check_price_response():
        return
    print("KAN-13/14 economy passed: exact settlement, atomic rejection including prices, capacity, voyage restrictions, local supply response, deterministic replay and both price bounds")
