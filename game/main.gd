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
var buy_all_buttons: Dictionary = {}
var sell_all_buttons: Dictionary = {}

func box(id: String, at: Vector2, dimensions: Vector2, tint: Color, text: String, parent: Node = self) -> ColorRect:
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
    label.text = text
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
    caption(box("PricePolicy", Vector2(10, 495), Vector2(410, 35), Color("35465b"), "Quotes fixed this visit; update on departure", market_panel))
    var index := 0
    for good_id in game_state.goods:
        var y := 105.0 + index * 130.0
        market_rows[good_id] = caption(box("Row_" + good_id, Vector2(10, y), Vector2(410, 45), Color("35465b"), game_state.goods[good_id].name, market_panel))
        var controls: Array = []
        for button_index in range(4):
            var purchasing: bool = button_index < 2
            var all_units: bool = button_index % 2 == 1
            var prefix: String = "Buy" if purchasing else "Sell"
            var text: String = prefix + (" all" if all_units else " 1")
            var node_prefix: String = prefix + ("All_" if all_units else "_")
            var tint: Color = Color("46604c") if purchasing else Color("62523c")
            var button := box(node_prefix + good_id, Vector2(10 + button_index * 104, y + 50), Vector2(98, 55), tint, text, market_panel)
            button.mouse_filter = Control.MOUSE_FILTER_STOP
            button.gui_input.connect(_transaction_input.bind(good_id, purchasing, all_units))
            controls.append(button)
        buy_buttons[good_id] = controls[0]
        buy_all_buttons[good_id] = controls[1]
        sell_buttons[good_id] = controls[2]
        sell_all_buttons[good_id] = controls[3]
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

func _transaction_input(event: InputEvent, good_id: String, purchasing: bool, all_units: bool = false) -> void:
    if pressed(event):
        var accepted: bool
        if all_units:
            accepted = buy_all(good_id) if purchasing else sell_all(good_id)
        else:
            accepted = buy(good_id, 1) if purchasing else sell(good_id, 1)
        trade_feedback.text = "Trade permitted: transaction completed" if accepted else "Trade unavailable: check stock, coins, cargo and docking"

func sail_to(port: Control) -> void:
    # A current-port click has zero travel time but does not end the visit.
    if game_state.can_trade() and str(port.name) == game_state.docked_port_id:
        voyage_time = 0.0
        refresh_voyage()
        refresh_market()
        return
    if not game_state.start_voyage(str(port.name)):
        return
    voyage_time = game_state.voyage.duration
    set_meta("destination_id", str(port.name))
    if game_state.voyage.active:
        current_destination = port
        docked_port = null
        set_meta("at_sea", true)
    else:
        current_destination = null
        docked_port = get_node(game_state.docked_port_id) as Control
        set_meta("at_sea", false)
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

func buy_all(good_id: String) -> bool:
    var accepted: bool = game_state.buy_all(good_id)
    refresh_market()
    return accepted

func sell_all(good_id: String) -> bool:
    var accepted: bool = game_state.sell_all(good_id)
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
    market_title.text = "%s market | Wallet: %d coins\nPrice bounds: 1 to twice base price" % [game_state.docked_port_id, game_state.wallet.coins]
    var market = game_state.markets[game_state.docked_port_id]
    for good_id in market_rows:
        var stock: int = int(market.inventory.get(good_id, 0))
        var price: int = int(market.prices.get(good_id, 0))
        var owned: int = game_state.cargo.quantity(good_id)
        market_rows[good_id].text = "%s | Stock %d | %d coins/unit | Owned %d" % [game_state.goods[good_id].name, stock, price, owned]
        var maximum: int = game_state.max_buy_quantity(good_id)
        buy_buttons[good_id].color = Color("46604c") if maximum > 0 else Color("444444")
        buy_all_buttons[good_id].color = buy_buttons[good_id].color
        sell_buttons[good_id].color = Color("62523c") if owned > 0 else Color("444444")
        sell_all_buttons[good_id].color = sell_buttons[good_id].color
        caption(buy_buttons[good_id]).text = "Buy 1" if maximum > 0 else "Buy 1\nunavailable"
        caption(sell_buttons[good_id]).text = "Sell 1" if owned > 0 else "Sell 1\nunavailable"
        caption(buy_all_buttons[good_id]).text = "Buy all\n(%d)" % maximum
        caption(sell_all_buttons[good_id]).text = "Sell all\n(%d)" % owned
    trade_feedback.text = "Trade permitted at " + game_state.docked_port_id
