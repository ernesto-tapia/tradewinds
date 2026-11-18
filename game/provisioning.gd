extends Node

const UI = preload("res://ui/menu_ui.gd")
var buy_button: Button
var feedback: Label
var balance_label: Label
var route_label: Label
var panel: PanelContainer
var game_state

func _ready() -> void:
    game_state = get_parent().game_state
    call_deferred("build_board")

func build_board() -> void:
    var main = get_parent()
    panel = UI.panel(main, "ProvisioningPanel", Vector2(10, 536), Vector2(690, 174))
    var content := UI.scroll_column(panel)
    UI.label(content, "Provisions · 2 coins each", "Heading")
    balance_label = UI.label(content, "")
    route_label = UI.label(content, "")
    buy_button = UI.button(content, "BuyProvisions", "Buy 4 provisions for 8 coins", buy_provisions, true)
    feedback = UI.label(content, "Dock at either port to purchase supplies.")
    refresh_provisioning()

func buy_provisions() -> bool:
    var bought: bool = game_state.buy_provisions(4)
    var message := "Bought 4 provisions for 8 coins."
    if not bought:
        message = "Dock at a port to buy provisions." if not game_state.can_trade() else "Requires 8 coins to buy 4 provisions."
    UI.status(feedback, message, not bought)
    get_parent().refresh_market()
    get_parent().refresh_route_requirements()
    if bought:
        get_parent().refresh_voyage()
    refresh_provisioning()
    return bought

func _process(_delta: float) -> void:
    if is_instance_valid(buy_button):
        refresh_provisioning()

func refresh_provisioning() -> void:
    balance_label.text = "Balance: %d provisions, %d coins" % [game_state.provisions, game_state.wallet.coins]
    if game_state.voyage.active:
        route_label.text = "Consumed at departure: %d provisions. No further charge during sailing." % game_state.voyage.provisions_consumed
    else:
        route_label.text = "Required: Port A %d · Port B %d provisions" % [game_state.required_provisions("Port A"), game_state.required_provisions("Port B")]
    buy_button.disabled = not game_state.can_trade() or game_state.wallet.coins < 8
