extends Node

const Delivery = preload("res://delivery_contract.gd")
const UI = preload("res://ui/menu_ui.gd")
var delivery
var details: Label
var accept_button: Button
var complete_button: Button
var feedback: Label
var panel: PanelContainer

func _ready() -> void:
    call_deferred("build_board")

func build_board() -> void:
    var main = get_parent()
    delivery = Delivery.new(main.game_state)
    panel = UI.panel(main, "ContractPanel", Vector2(710, 126), Vector2(560, 584))
    panel.visible = main.active_menu == "contracts"
    var content := UI.scroll_column(panel)
    UI.label(content, "Delivery contract", "Heading")
    details = UI.label(content, "Deliver 3 Sugar to Port B for 30 coins.")
    accept_button = UI.button(content, "AcceptContract", "Accept at Port A", accept_contract, true)
    complete_button = UI.button(content, "CompleteContract", "Deliver at Port B", complete_contract, true)
    feedback = UI.label(content, "Buy cargo in the port market.")
    refresh_contract()

func accept_contract(contract_id: String = "deliver_sugar") -> bool:
    var accepted: bool = delivery.accept_contract(contract_id)
    UI.status(feedback, "Accepted: bring 3 Sugar to Port B." if accepted else "Accept at Port A with no active contract.", not accepted)
    refresh_contract()
    return accepted

func complete_contract(contract_id: String = "deliver_sugar") -> bool:
    var completed: bool = delivery.complete_contract(contract_id)
    UI.status(feedback, "Delivered! +30 coins. Return to Port A to replay." if completed else "Requires an active contract and 3 Sugar, docked at Port B.", not completed)
    get_parent().refresh_market()
    refresh_contract()
    return completed

func get_contract_data() -> Dictionary:
    return delivery.get_contract_data()

func _accept_input(event: InputEvent) -> void:
    if get_parent().pressed(event) and not accept_button.disabled:
        accept_contract()

func _complete_input(event: InputEvent) -> void:
    if get_parent().pressed(event) and not complete_button.disabled:
        complete_contract()

func _process(_delta: float) -> void:
    if delivery != null:
        refresh_contract()

func refresh_contract() -> void:
    var data: Dictionary = delivery.get_contract_data()
    var state = get_parent().game_state
    var status: String = "Active" if data.active else "Offer at Port A"
    details.text = "%s\nDeliver 3 Sugar to Port B.\nReward: 30 coins\nOwned: %d/3\nCompleted: %d" % [status, state.cargo.quantity("sugar"), data.completed_count]
    accept_button.disabled = data.active or not state.can_trade() or state.docked_port_id != "Port A"
    complete_button.disabled = not data.active or not state.can_trade() or state.docked_port_id != "Port B" or state.cargo.quantity("sugar") < 3
    accept_button.visible = not data.active
    complete_button.visible = data.active
