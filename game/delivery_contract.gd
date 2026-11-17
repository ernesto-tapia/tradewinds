extends RefCounted

# One repeatable offer. Acceptance never grants cargo or payment.
const CONTRACT_ID: String = "deliver_sugar"
const ORIGIN: String = "Port A"
var state
var active: bool = false
var completed_count: int = 0

func _init(game_state) -> void:
    state = game_state

func accept_contract(contract_id: String = CONTRACT_ID) -> bool:
    if contract_id != CONTRACT_ID or active or not state.can_trade() or state.docked_port_id != ORIGIN:
        return false
    active = true
    state.contracts[CONTRACT_ID].completed = false
    return true

func complete_contract(contract_id: String = CONTRACT_ID) -> bool:
    if contract_id != CONTRACT_ID or not active or not state.can_trade():
        return false
    var contract = state.contracts[CONTRACT_ID]
    if state.docked_port_id != contract.destination_id or state.cargo.quantity(contract.good_id) < contract.quantity:
        return false
    state.cargo.quantities[contract.good_id] = state.cargo.quantity(contract.good_id) - contract.quantity
    state.wallet.coins += contract.reward
    contract.completed = true
    active = false
    completed_count += 1
    return true

func get_contract_data() -> Dictionary:
    var contract = state.contracts[CONTRACT_ID]
    return {
        "id": CONTRACT_ID,
        "origin_id": ORIGIN,
        "destination_id": contract.destination_id,
        "good_id": contract.good_id,
        "quantity": contract.quantity,
        "reward": contract.reward,
        "active": active,
        "completed": contract.completed,
        "completed_count": completed_count
    }
