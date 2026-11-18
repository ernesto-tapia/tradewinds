extends Node

const UI = preload("res://ui/menu_ui.gd")
var supplies: Label
var routes: Label
var feedback: Label
var purchase: Button
var last_departure_feedback: String = ""

func _ready() -> void:
    # Parent builds the map and wallet before this deferred UI construction.
    call_deferred("build_panel")

func build_panel() -> void:
    var panel := UI.panel(get_parent(), "ProvisionsPanel", Vector2(10, 540), Vector2(690, 170))
    var content := UI.column(panel)
    var row := UI.row(content)
    supplies = UI.label(row, "Provisions")
    purchase = UI.button(row, "BuyProvisions", "Buy 1 provision · 2 coins", buy_one)
    routes = UI.label(content, "")
    feedback = UI.label(content, "Buy provisions at either dock. Each 100 route units costs 1, rounded up.")
    refresh()

func buy_one() -> void:
    var main = get_parent()
    var accepted: bool = main.game_state.buy_provisions(1)
    UI.status(feedback, "Purchased 1 provision for 2 coins." if accepted else "Requires docking and 2 coins.", not accepted)
    main.refresh_market()
    refresh()

func _process(_delta: float) -> void:
    if is_instance_valid(supplies):
        refresh()

func refresh() -> void:
    var state = get_parent().game_state
    supplies.text = "Provisions aboard: %d" % state.provisions
    purchase.disabled = not state.can_trade() or state.wallet.coins < state.PROVISION_PRICE
    if state.voyage.active:
        routes.text = "This voyage consumed %d provisions at departure." % state.voyage.provisions_consumed
    else:
        var quotes: PackedStringArray = []
        for port_id in state.ports:
            if port_id != state.docked_port_id:
                quotes.append("%s requires %d" % [port_id, state.required_provisions(port_id)])
        routes.text = "Departure provisions: " + " · ".join(quotes)
    if state.departure_feedback != last_departure_feedback:
        last_departure_feedback = state.departure_feedback
        UI.status(feedback, last_departure_feedback, last_departure_feedback.begins_with("Cannot"))
