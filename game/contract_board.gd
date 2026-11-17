extends Node

const Delivery = preload("res://delivery_contract.gd")
var delivery
var details: Label
var accept_button: ColorRect
var complete_button: ColorRect
var feedback: Label

func _ready() -> void:
    # Parent builds the existing map and market before this overlay is added.
    call_deferred("build_board")

func build_board() -> void:
    var main = get_parent()
    delivery = Delivery.new(main.game_state)
    details = main.caption(main.box("ContractDetails", Vector2(10, 115), Vector2(680, 55), Color("253447"), "Delivery contract"))
    accept_button = main.box("AcceptContract", Vector2(10, 180), Vector2(195, 45), Color("46604c"), "Accept at Port A")
    complete_button = main.box("CompleteContract", Vector2(10, 235), Vector2(195, 45), Color("46604c"), "Deliver at Port B")
    feedback = main.caption(main.box("ContractFeedback", Vector2(10, 290), Vector2(195, 100), Color("253447"), ""))
    feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    accept_button.mouse_filter = Control.MOUSE_FILTER_STOP
    complete_button.mouse_filter = Control.MOUSE_FILTER_STOP
    accept_button.gui_input.connect(_accept_input)
    complete_button.gui_input.connect(_complete_input)
    refresh_contract()

func accept_contract(contract_id: String = "deliver_sugar") -> bool:
    var accepted: bool = delivery.accept_contract(contract_id)
    feedback.text = "Accepted: bring 3 Sugar to Port B." if accepted else "Accept at Port A with no active contract."
    refresh_contract()
    return accepted

func complete_contract(contract_id: String = "deliver_sugar") -> bool:
    var completed: bool = delivery.complete_contract(contract_id)
    feedback.text = "Delivered! +30 coins. Return to Port A to replay." if completed else "Requires an active contract and 3 Sugar, docked at Port B."
    get_parent().refresh_market()
    refresh_contract()
    return completed

func get_contract_data() -> Dictionary:
    return delivery.get_contract_data()

func _accept_input(event: InputEvent) -> void:
    if get_parent().pressed(event):
        accept_contract()

func _complete_input(event: InputEvent) -> void:
    if get_parent().pressed(event):
        complete_contract()

func _process(_delta: float) -> void:
    if delivery != null:
        refresh_contract()

func refresh_contract() -> void:
    var data: Dictionary = delivery.get_contract_data()
    var state = get_parent().game_state
    var status: String = "Active" if data.active else "Offer at Port A"
    details.text = "%s: deliver 3 Sugar to Port B | Reward 30 coins\nOwned: %d/3 | Completed: %d | Buy cargo in the market" % [status, state.cargo.quantity("sugar"), data.completed_count]
    var can_accept: bool = not data.active and state.can_trade() and state.docked_port_id == "Port A"
    var can_complete: bool = data.active and state.can_trade() and state.docked_port_id == "Port B" and state.cargo.quantity("sugar") >= 3
    accept_button.color = Color("46604c") if can_accept else Color("444444")
    complete_button.color = Color("46604c") if can_complete else Color("444444")
