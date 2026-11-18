extends Node

const Models = preload("res://data_models.gd")

func require_condition(value: bool, message: String) -> bool:
    if not value:
        push_error("KAN-16 provisioning: " + message)
        get_tree().quit(1)
    return value

func snapshot(state) -> Dictionary:
    return {
        "coins": state.wallet.coins,
        "supplies": state.provisions,
        "position": state.ship.position,
        "dock": state.docked_port_id,
        "active": state.voyage.active,
        "destination": state.voyage.destination_id,
        "cargo": state.cargo.quantities.duplicate(true)
    }

func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        call_deferred("run_checks")

func run_checks() -> void:
    var state = Models.new()
    var before: Dictionary = snapshot(state)
    if not require_condition(not state.buy_provisions(1) and snapshot(state) == before, "purchases at sea reject without changing resources"):
        return
    state.docked_port_id = "Port A"
    state.ship.position = state.ports["Port A"].position
    state.provisions = 0
    if not require_condition(state.required_provisions("Port B") == 4, "319.5 unit port route rounds up to four provisions"):
        return
    before = snapshot(state)
    if not require_condition(not state.start_voyage("Port B") and snapshot(state) == before and "requires 4" in state.departure_feedback and "aboard 0" in state.departure_feedback, "insufficient departure is atomic and explains required and owned supplies"):
        return
    for quantity in [-1, 0, 51]:
        before = snapshot(state)
        if not require_condition(not state.buy_provisions(quantity) and snapshot(state) == before, "invalid and unaffordable purchases reject atomically"):
            return
    state.cargo.quantities["sugar"] = state.ship.capacity
    if not require_condition(state.buy_provisions(4) and state.provisions == 4 and state.wallet.coins == 92 and state.cargo.total() == 20, "dock purchase charges two coins each and uses a separate supply reserve"):
        return
    before = snapshot(state)
    if not require_condition(not state.start_voyage("Port A") and not state.start_voyage("missing") and snapshot(state) == before, "same-port and invalid destinations consume nothing"):
        return
    if not require_condition(state.start_voyage("Port B") and state.provisions == 0 and state.voyage.provisions_consumed == 4 and state.voyage.active and "requires 4" in state.departure_feedback, "exact supplies permit departure and are consumed immediately"):
        return
    before = snapshot(state)
    if not require_condition(not state.start_voyage("Port A") and not state.buy_provisions(1) and snapshot(state) == before, "active voyage blocks purchases and repeated departures without another charge"):
        return
    state.advance_voyage(0.5)
    if not require_condition(state.provisions == 0 and state.voyage.active, "progress never charges supplies again"):
        return
    state.advance_voyage(100.0)
    if not require_condition(state.docked_port_id == "Port B" and state.provisions == 0 and not state.voyage.active, "arrival preserves the departure charge"):
        return
    if not require_condition(state.buy_provisions(4) and state.wallet.coins == 84 and state.start_voyage("Port A"), "destination dock supports resupply and return sailing"):
        return
    state.advance_voyage(100.0)
    state.ship.position = state.ports["Port B"].position - Vector2(100, 0)
    if not require_condition(state.required_provisions("Port B") == 1, "shorter route uses one provision at the exact distance boundary"):
        return
    state.ship.position -= Vector2(0.1, 0)
    if not require_condition(state.required_provisions("Port B") == 2, "distance above a boundary rounds up deterministically"):
        return
    print("KAN-16 provisioning passed: dock purchases, price, separate reserve, atomic rejection, route rounding, required-amount feedback, exact departure consumption, no repeated charges, destination resupply and return")
