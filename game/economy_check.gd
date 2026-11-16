extends Node

const Models = preload("res://data_models.gd")

# Delegate to the same state and refresh path used by the market controls.
func check_buy(good_id: String, quantity: int) -> bool:
    return get_parent().buy(good_id, quantity)

func check_sell(good_id: String, quantity: int) -> bool:
    return get_parent().sell(good_id, quantity)

func check_can_trade() -> bool:
    return get_parent().can_trade()

func snapshot(state) -> Dictionary:
    var inventories: Dictionary = {}
    for port_id in state.markets:
        inventories[port_id] = state.markets[port_id].inventory.duplicate(true)
    return {
        "coins": state.wallet.coins,
        "cargo": state.cargo.quantities.duplicate(true),
        "inventories": inventories
    }

func _ready() -> void:
    # Independent fixtures exercise transactions without changing the player's game.
    var state = Models.new()
    var before: Dictionary = snapshot(state)
    assert(not state.buy("sugar", 1), "Buying at sea must fail")
    assert(not state.sell("sugar", 1), "Selling at sea must fail")
    assert(snapshot(state) == before, "Rejected trades must preserve state")
    state.docked_port_id = "Port A"
    assert(state.buy("sugar", 3), "Affordable purchase must succeed")
    assert(state.wallet.coins == 85, "Purchase must deduct exactly once")
    assert(state.cargo.quantity("sugar") == 3, "Purchase must add cargo")
    assert(state.markets["Port A"].inventory["sugar"] == 17, "Purchase must remove stock")
    assert(state.sell("sugar", 2), "Owned cargo must be sellable")
    assert(state.wallet.coins == 95, "Sale must credit exactly once")
    assert(state.cargo.quantity("sugar") == 1, "Sale must remove cargo")
    assert(state.markets["Port A"].inventory["sugar"] == 19, "Sale must restore stock")
    before = snapshot(state)
    assert(not state.sell("sugar", 2), "Overselling must fail")
    assert(not state.buy("coffee", 8), "Insufficient funds must block purchase")
    assert(not state.buy("rum", 11), "Insufficient stock must block purchase")
    for quantity in [0, -1]:
        assert(not state.buy("sugar", quantity), "Nonpositive purchase must fail")
        assert(not state.sell("sugar", quantity), "Nonpositive sale must fail")
    assert(not state.buy("unknown", 1), "Unknown goods must fail")
    assert(not state.sell("unknown", 1), "Unknown goods must fail")
    assert(snapshot(state) == before, "Invalid transactions must be atomic")
    state.ship.capacity = 2
    assert(state.buy("rum", 1), "Mixed cargo may fill remaining capacity")
    before = snapshot(state)
    assert(not state.buy("sugar", 1), "Full cargo must block purchase")
    assert(snapshot(state) == before, "Capacity rejection must preserve state")
    assert(state.sell("rum", 1), "Selling must release capacity")
    assert(state.buy("sugar", 1), "Released capacity must be reusable")
    state.docked_port_id = "Port B"
    assert(state.sell("sugar", 2), "Cargo must sell at the destination price")
    assert(state.wallet.coins == 106, "Destination sale must use Port B price")
    assert(state.markets["Port B"].inventory["sugar"] == 12, "Destination stock must increase")
    assert(state.markets["Port A"].inventory["sugar"] == 18, "Other port stock must remain independent")
    assert(state.start_voyage("Port A"), "Voyage fixture must start")
    before = snapshot(state)
    assert(not state.buy("sugar", 1), "Voyage must block purchasing")
    assert(not state.sell("sugar", 1), "Voyage must block selling")
    assert(snapshot(state) == before, "Voyage rejection must preserve state")
    var exact = Models.new()
    exact.docked_port_id = "Port A"
    assert(exact.buy("sugar", 20), "Exact funds, stock and capacity must be accepted")
    assert(exact.wallet.coins == 0 and exact.cargo.total() == 20, "Exact boundary must not go negative")
    assert(exact.markets["Port A"].inventory["sugar"] == 0, "Exact purchase must exhaust stock")
    before = snapshot(exact)
    assert(not exact.buy("sugar", 1), "Exhausted resources must reject another purchase")
    assert(snapshot(exact) == before, "Repeated rejected purchase must preserve balances")
    print("Economy checks passed: atomic buy/sell, funds, stock, capacity and voyage restrictions")
