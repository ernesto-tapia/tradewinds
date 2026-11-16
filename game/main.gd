extends Node2D

const Models = preload("res://data_models.gd")
var game_state = Models.new()
var ship: ColorRect
var current_destination: Control = null
var docked_port: Control = null
var voyage_time: float = 0.0
var voyage_progress: float = 0.0
var remaining_time: float = 0.0
var destination_feedback: Label
var trade_feedback: Label
var economy_feedback: Label
var market_panel: ColorRect
var market_title: Label
var market_rows: Dictionary = {}
var buy_buttons: Dictionary = {}
var sell_buttons: Dictionary = {}

func box(id: String, at: Vector2, dimensions: Vector2, tint: Color, caption: String, parent: Node = self) -> ColorRect:
    var control := ColorRect.new()
    control.name = id
    control.position = at
    control.size = dimensions
    control.color = tint
    control.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(control)
    var label := Label.new()
    label.position = Vector2.ZERO
    label.size = dimensions
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.text = caption
    control.add_child(label)
    return control

func caption(control: Control) -> Label:
    return control.get_child(0) as Label

func _ready() -> void:
    box("Ocean", Vector2.ZERO, Vector2(1152, 648), Color("163e58"), "Ocean")
    box("Title", Vector2(10, 10), Vector2(680, 40), Color("253447"), "Caribbean Tradewinds")
    box("Island", Vector2(220, 170), Vector2(140, 130), Color("476445"), "Island")
    box("Island B", Vector2(530, 300), Vector2(150, 120), Color("476445"), "Island")
    for port_id in game_state.ports:
        var port := box(port_id, game_state.ports[port_id].position, Vector2(90, 45), Color("815a39"), port_id)
        port.mouse_filter = Control.MOUSE_FILTER_STOP
        port.add_to_group("ports")
        port.set_meta("destination_id", port_id)
        port.gui_input.connect(_port_input.bind(port))
    ship = box("Ship", game_state.ship.position, Vector2(70, 35), Color("7c667d"), "Ship")
    ship.mouse_filter = Control.MOUSE_FILTER_STOP
    ship.add_to_group("player_ship")
    ship.set_meta("selected", false)
    ship.gui_input.connect(_ship_input)
    destination_feedback = caption(box("Destination", Vector2(10, 65), Vector2(680, 45), Color("253447"), "Choose Port A or Port B to sail"))
    destination_feedback.add_to_group("destination_feedback")
    var trade := box("Trade", Vector2(10, 470), Vector2(680, 40), Color("253447"), "Trade unavailable at sea")
    trade.mouse_filter = Control.MOUSE_FILTER_STOP
    trade.gui_input.connect(_trade_input)
    trade_feedback = caption(trade)
    economy_feedback = caption(box("Economy", Vector2(10, 520), Vector2(680, 90), Color("253447"), "Wallet"))
    market_panel = box("Market", Vector2(710, 65), Vector2(430, 540), Color("253447"), "Port market")
    caption(market_panel).vertical_alignment = VERTICAL_ALIGNMENT_TOP
    market_title = caption(box("MarketTitle", Vector2(10, 35), Vector2(410, 60), Color("35465b"), "Dock to open market", market_panel))
    var index := 0
    for good_id in game_state.goods:
        var y := 110.0 + index * 130.0
        var row := box("Row_" + good_id, Vector2(10, y), Vector2(410, 55), Color("35465b"), game_state.goods[good_id].name, market_panel)
        market_rows[good_id] = caption(row)
        var buy_button := box("Buy_" + good_id, Vector2(10, y + 60), Vector2(195, 40), Color("46604c"), "Buy 1", market_panel)
        var sell_button := box("Sell_" + good_id, Vector2(225, y + 60), Vector2(195, 40), Color("62523c"), "Sell 1", market_panel)
        buy_button.mouse_filter = Control.MOUSE_FILTER_STOP
        sell_button.mouse_filter = Control.MOUSE_FILTER_STOP
        buy_button.gui_input.connect(_transaction_input.bind(good_id, true))
        sell_button.gui_input.connect(_transaction_input.bind(good_id, false))
        buy_buttons[good_id] = buy_button
        sell_buttons[good_id] = sell_button
        index += 1
    var camera := Camera2D.new()
    camera.position = Vector2(576, 324)
    camera.limit_left = 0
    camera.limit_top = 0
    camera.limit_right = 1152
    camera.limit_bottom = 648
    camera.position_smoothing_enabled = false
    add_child(camera)
    set_meta("at_sea", true)
    refresh_market()

func pressed(event: InputEvent) -> bool:
    return event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed

func _port_input(event: InputEvent, port: Control) -> void:
    if pressed(event):
        sail_to(port)

func _ship_input(event: InputEvent) -> void:
    if pressed(event):
        ship.set_meta("selected", true)
        ship.color = Color("b68a43")
        caption(ship).text = "Ship selected"

func _trade_input(event: InputEvent) -> void:
    if pressed(event):
        request_trade()

func _transaction_input(event: InputEvent, good_id: String, purchasing: bool) -> void:
    if pressed(event):
        var accepted: bool = buy(good_id, 1) if purchasing else sell(good_id, 1)
        trade_feedback.text = "Trade permitted: transaction completed" if accepted else "Trade unavailable: check stock, coins, cargo and docking"

func sail_to(port: Control) -> void:
    if not game_state.start_voyage(str(port.name)):
        return
    current_destination = port
    docked_port = null
    voyage_time = game_state.voyage.duration
    set_meta("destination_id", str(port.name))
    set_meta("at_sea", true)
    refresh_voyage()
    refresh_market()

func _process(delta: float) -> void:
    if game_state.voyage.active:
        game_state.advance_voyage(delta)
        refresh_voyage()
        if not game_state.voyage.active:
            docked_port = get_node(game_state.docked_port_id) as Control
            current_destination = null
            set_meta("at_sea", false)
            refresh_market()

func refresh_voyage() -> void:
    ship.position = game_state.ship.position
    voyage_progress = game_state.voyage.progress
    remaining_time = game_state.voyage.remaining_time
    if game_state.voyage.active:
        destination_feedback.text = "Sailing to %s: %d%% | %.1f seconds remaining" % [game_state.voyage.destination_id, roundi(voyage_progress * 100.0), remaining_time]
    else:
        destination_feedback.text = "Docked at %s: 100%% | 0 seconds remaining" % game_state.docked_port_id

func can_trade() -> bool:
    return game_state.can_trade()

func request_trade() -> bool:
    trade_feedback.text = "Trade permitted at " + game_state.docked_port_id if can_trade() else "Trade unavailable at sea"
    return can_trade()

func buy(good_id: String, quantity: int) -> bool:
    var accepted: bool = game_state.buy(good_id, quantity)
    refresh_market()
    return accepted

func sell(good_id: String, quantity: int) -> bool:
    var accepted: bool = game_state.sell(good_id, quantity)
    refresh_market()
    return accepted

func get_market_data(port_id: String) -> Dictionary:
    if not game_state.markets.has(port_id):
        return {}
    var market = game_state.markets[port_id]
    return {"port_id": port_id, "inventory": market.inventory.duplicate(true), "prices": market.prices.duplicate(true), "wallet_coins": game_state.wallet.coins}

func refresh_market() -> void:
    if not is_instance_valid(market_panel):
        return
    var cargo_text := ""
    for good_id in game_state.goods:
        cargo_text += "%s %d  " % [game_state.goods[good_id].name, game_state.cargo.quantity(good_id)]
    economy_feedback.text = "Coins: %d | Cargo: %d/%d\n%s" % [game_state.wallet.coins, game_state.cargo.total(), game_state.ship.capacity, cargo_text]
    market_panel.visible = can_trade()
    if not can_trade():
        trade_feedback.text = "Trade unavailable at sea"
        return
    market_title.text = "%s market | Wallet: %d coins\nGood | Stock | Unit price | Owned" % [game_state.docked_port_id, game_state.wallet.coins]
    var market = game_state.markets[game_state.docked_port_id]
    for good_id in market_rows:
        var stock: int = int(market.inventory.get(good_id, 0))
        var price: int = int(market.prices.get(good_id, 0))
        var owned: int = game_state.cargo.quantity(good_id)
        market_rows[good_id].text = "%s | Stock %d | %d coins/unit | Owned %d" % [game_state.goods[good_id].name, stock, price, owned]
        var can_buy: bool = price > 0 and stock > 0 and game_state.wallet.coins >= price and game_state.cargo.total() < game_state.ship.capacity
        buy_buttons[good_id].color = Color("46604c") if can_buy else Color("444444")
        sell_buttons[good_id].color = Color("62523c") if owned > 0 else Color("444444")
        caption(buy_buttons[good_id]).text = "Buy 1" if can_buy else "Buy 1 unavailable"
        caption(sell_buttons[good_id]).text = "Sell 1" if owned > 0 else "Sell 1 unavailable"
    trade_feedback.text = "Trade permitted at " + game_state.docked_port_id
