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
    if not state.buy("sugar", 1):
        print("Buying at sea must fail")
        return
    if not state.sell("sugar", 1):
        print("Selling at sea must fail")
        return
    if snapshot(state) != before:
        print("Rejected trades must preserve state")
        return
    state.docked_port_id = "Port A"
    if not state.buy("sugar", 3):
        print("Affordable purchase must succeed")
        return
    if state.wallet.coins != 85:
        print("Purchase must deduct exactly once")
        return
    if state.cargo.quantity("sugar") != 3:
        print("Purchase must add cargo")
        return
    if state.markets["Port A"].inventory["sugar"] != 17:
        print("Purchase must remove stock")
        return
    if not state.sell("sugar", 2):
        print("Owned cargo must be sellable")
        return
    if state.wallet.coins != 95:
        print("Sale must credit exactly once")
        return
    if state.cargo.quantity("sugar") != 1:
        print("Sale must remove cargo")
        return
    if state.markets["Port A"].inventory["sugar"] != 19:
        print("Sale must restore stock")
        return
    before = snapshot(state)
    if state.sell("sugar", 2):
        print("Overselling must fail")
        return
    if state.buy("coffee", 8):
        print("Insufficient funds must block purchase")
        return
    if state.buy("rum", 11):
        print("Insufficient stock must block purchase")
        return
    for quantity in [0, -1]:
        if state.buy("sugar", quantity):
            print("Nonpositive purchase must fail")
            return
        if state.sell("sugar", quantity):
            print("Nonpositive sale must fail")
            return
    if state.buy("unknown", 1):
        print("Unknown goods must fail")
        return
    if state.sell("unknown", 1):
        print("Unknown goods must fail")
        return
    if snapshot(state) != before:
        print("Invalid transactions must be atomic")
        return
    state.ship.capacity = 2
    if not state.buy("rum", 1):
        print("Mixed cargo may fill remaining capacity")
        return
    before = snapshot(state)
    if state.buy("sugar", 1):
        print("Full cargo must block purchase")
        return
    if snapshot(state) != before:
        print("Capacity rejection must preserve state")
        return
    if not state.sell("rum", 1):
        print("Selling must release capacity")
        return
    if not state.buy("sugar", 1):
        print("Released capacity must be reusable")
        return
    state.docked_port_id = "Port B"
    if not state.sell("sugar", 2):
        print("Cargo must sell at the destination price")
        return
    if state.wallet.coins != 106:
        print("Destination sale must use Port B price")
        return
    if state.markets["Port B"].inventory["sugar"] != 12:
        print("Destination stock must increase")
        return
    if state.markets["Port A"].inventory["sugar"] != 18:
        print("Other port stock must remain independent")
        return
    if not state.start_voyage("Port A"):
        print("Voyage fixture must start")
        return
    before = snapshot(state)
    if state.buy("sugar", 1):
        print("Voyage must block purchasing")
        return
    if state.sell("sugar", 1):
        print("Voyage must block selling")
        return
    if snapshot(state) != before:
        print("Voyage rejection must preserve state")
        return
    var exact = Models.new()
    exact.docked_port_id = "Port A"
    if not exact.buy("sugar", 20):
        print("Exact funds, stock and capacity must be accepted")
        return
    if exact.wallet.coins != 0 or exact.cargo.total() != 20:
        print("Exact boundary must not go negative")
        return
    if exact.markets["Port A"].inventory["sugar"] != 0:
        print("Exact purchase must exhaust stock")
        return
    before = snapshot(exact)
    if exact.buy("sugar", 1):
        print("Exhausted resources must reject another purchase")
        return
    if snapshot(exact) != before:
        print("Repeated rejected purchase must preserve balances")
        return
    print("Economy checks passed: atomic buy/sell, funds, stock, capacity and voyage restrictions")
