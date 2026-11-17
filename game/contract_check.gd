extends Node

const Models = preload("res://data_models.gd")
const Delivery = preload("res://delivery_contract.gd")

func require_condition(value: bool, message: String) -> bool:
    if not value:
        push_error("KAN-15: " + message)
        get_tree().quit(1)
    return value

func snapshot(state, delivery) -> Dictionary:
    return {
        "coins": state.wallet.coins,
        "cargo": state.cargo.quantities.duplicate(true),
        "contract": delivery.get_contract_data(),
        "stock_a": state.markets["Port A"].inventory.duplicate(true),
        "stock_b": state.markets["Port B"].inventory.duplicate(true)
    }

func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        call_deferred("run_checks")

func run_checks() -> void:
    var state = Models.new()
    var delivery = Delivery.new(state)
    var before: Dictionary = snapshot(state, delivery)
    if not require_condition(not delivery.accept_contract() and not delivery.complete_contract() and snapshot(state, delivery) == before, "at-sea requests must reject without mutation"):
        return
    state.docked_port_id = "Port B"
    if not require_condition(not delivery.accept_contract() and not delivery.complete_contract() and snapshot(state, delivery) == before, "offer is only at Port A; delivery requires acceptance"):
        return
    state.docked_port_id = "Port A"
    state.ship.position = state.ports["Port A"].position
    if not require_condition(not delivery.accept_contract("missing") and snapshot(state, delivery) == before, "unknown contract must reject atomically"):
        return
    if not require_condition(delivery.accept_contract() and state.wallet.coins == 100 and state.cargo.total() == 0, "acceptance must activate without granting cargo or coins"):
        return
    before = snapshot(state, delivery)
    if not require_condition(not delivery.accept_contract() and not delivery.complete_contract() and snapshot(state, delivery) == before, "duplicate acceptance and wrong destination must reject atomically"):
        return
    if not require_condition(state.buy("sugar", 3) and state.buy("rum", 1), "cargo purchase fixture"):
        return
    before = snapshot(state, delivery)
    if not require_condition(not delivery.complete_contract() and snapshot(state, delivery) == before, "sufficient cargo at origin must not complete"):
        return
    if not require_condition(state.start_voyage("Port B"), "departure must succeed"):
        return
    if not require_condition(not delivery.complete_contract() and snapshot(state, delivery) == before, "cargo cannot be delivered during voyage"):
        return
    state.advance_voyage(100.0)
    if not require_condition(state.sell("sugar", 1), "insufficient cargo fixture"):
        return
    before = snapshot(state, delivery)
    if not require_condition(not delivery.complete_contract() and snapshot(state, delivery) == before, "short cargo must reject atomically"):
        return
    if not require_condition(state.buy("sugar", 2), "surplus cargo fixture"):
        return
    before = snapshot(state, delivery)
    if not require_condition(not delivery.complete_contract("missing") and snapshot(state, delivery) == before, "unknown delivery must reject atomically"):
        return
    if not require_condition(delivery.complete_contract() and state.wallet.coins == before.coins + 30 and state.cargo.quantity("sugar") == 1 and state.cargo.quantity("rum") == 1 and not delivery.active and delivery.completed_count == 1 and state.contracts["deliver_sugar"].completed, "delivery must consume exactly three Sugar and pay once"):
        return
    if not require_condition(state.markets["Port A"].inventory == before.stock_a and state.markets["Port B"].inventory == before.stock_b, "delivery must preserve market inventory"):
        return
    before = snapshot(state, delivery)
    if not require_condition(not delivery.complete_contract() and not delivery.accept_contract() and snapshot(state, delivery) == before, "completed contract cannot pay again or restart at destination"):
        return
    if not require_condition(state.start_voyage("Port A"), "return voyage"):
        return
    state.advance_voyage(100.0)
    if not require_condition(delivery.accept_contract() and not state.contracts["deliver_sugar"].completed and state.buy("sugar", 2), "repeat offer must accept and reset completion"):
        return
    if not require_condition(state.start_voyage("Port B"), "repeat departure"):
        return
    state.advance_voyage(100.0)
    var coins: int = state.wallet.coins
    if not require_condition(delivery.complete_contract() and delivery.completed_count == 2 and state.wallet.coins == coins + 30 and state.cargo.quantity("sugar") == 0, "second delivery must consume fresh cargo and reward once"):
        return
    var board = get_parent().get_node("ContractBoard")
    if not require_condition(board.delivery != null and board.details != null and board.accept_button != null and board.complete_button != null, "scene must build contract controls"):
        return
    print("KAN-15 contracts passed: origin-only acceptance, atomic rejection, destination and cargo gates, exact consumption and reward, no duplicate payout, repeat delivery, scene controls")
