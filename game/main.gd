extends Node2D

const DataModels = preload("res://data_models.gd")
var game_state = DataModels.new()
var destination_feedback: Label
var trade_feedback: Label
var economy_feedback: Label
var ship: ColorRect
var ship_speed: float = 200.0
var current_destination: Control
var docked_port: Control
var voyage_distance: float = 0.0
var voyage_time: float = 0.0
var voyage_progress: float = 0.0
var remaining_time: float = 0.0

func _ready() -> void:
    print("Caribbean Tradewinds: fixed local state ready")
    var camera = Camera2D.new()
    camera.name = "MapCamera"
    camera.position = Vector2(500, 300)
    camera.limit_left = 0
    camera.limit_top = 0
    camera.limit_right = 1000
    camera.limit_bottom = 600
    camera.enabled = true
    var viewport_size = get_viewport_rect().size
    var fit_scale = minf(viewport_size.x / 1000.0, viewport_size.y / 600.0)
    camera.zoom = Vector2.ONE * fit_scale
    add_child(camera)
    camera.make_current()

    _box("Ocean", Vector2.ZERO, Vector2(1000, 600), Color(0.08, 0.32, 0.48))
    _box("Island A", Vector2(90, 130), Vector2(260, 200), Color(0.3, 0.5, 0.3))
    _box("Island B", Vector2(650, 240), Vector2(260, 200), Color(0.4, 0.5, 0.25))
    for port_id in ["Port A", "Port B"]:
        var fixture = game_state.ports[port_id]
        var port = _box(fixture.id, fixture.position, Vector2(120, 65), Color(0.55, 0.28, 0.12))
        port.mouse_filter = Control.MOUSE_FILTER_STOP
        port.add_to_group("ports")
        port.set_meta("destination_id", fixture.id)
        port.gui_input.connect(_on_port_input.bind(port))

    ship_speed = game_state.ship.speed
    ship = _box("Ship", game_state.ship.position, Vector2(100, 55), Color(0.55, 0.55, 0.55))
    ship.mouse_filter = Control.MOUSE_FILTER_STOP
    ship.add_to_group("player_ship")
    ship.set_meta("selected", false)
    ship.gui_input.connect(_on_ship_input.bind(ship))
    _box("Caribbean Tradewinds", Vector2(250, 15), Vector2(500, 45), Color(0.1, 0.16, 0.2))
    var economy_box = _box("Local economy", Vector2(100, 65), Vector2(800, 35), Color(0.1, 0.16, 0.2))
    economy_feedback = economy_box.get_child(0) as Label
    var buy_box = _box("Buy 1 Sugar", Vector2(350, 110), Vector2(145, 40), Color(0.1, 0.16, 0.2))
    var sell_box = _box("Sell 1 Sugar", Vector2(505, 110), Vector2(145, 40), Color(0.1, 0.16, 0.2))
    buy_box.mouse_filter = Control.MOUSE_FILTER_STOP
    sell_box.mouse_filter = Control.MOUSE_FILTER_STOP
    buy_box.gui_input.connect(_on_transaction_input.bind(true))
    sell_box.gui_input.connect(_on_transaction_input.bind(false))
    var feedback_box = _box("Destination: click a port", Vector2(200, 520), Vector2(600, 55), Color(0.1, 0.16, 0.2))
    destination_feedback = feedback_box.get_child(0) as Label
    destination_feedback.add_to_group("destination_feedback")
    var trade_box = _box("Trade: dock at a port first", Vector2(250, 465), Vector2(500, 40), Color(0.1, 0.16, 0.2))
    trade_box.mouse_filter = Control.MOUSE_FILTER_STOP
    trade_box.gui_input.connect(_on_trade_input)
    trade_feedback = trade_box.get_child(0) as Label
    _sync_state()

func _box(text: String, at: Vector2, dimensions: Vector2, tint: Color) -> ColorRect:
    var box = ColorRect.new()
    box.name = text
    box.position = at
    box.size = dimensions
    box.color = tint
    box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var label = Label.new()
    label.text = text
    label.position = Vector2.ZERO
    label.size = dimensions
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_child(label)
    add_child(box)
    return box

func _on_port_input(event: InputEvent, port: Control) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        sail_to(port)

func sail_to(port: Control) -> void:
    if port == null or not port.is_in_group("ports") or current_destination != null:
        return
    game_state.ship.speed = ship_speed
    if not game_state.start_voyage(str(port.get_meta("destination_id"))):
        return
    current_destination = port
    docked_port = null
    set_meta("destination_id", str(port.get_meta("destination_id")))
    _sync_voyage()
    trade_feedback.text = "Trade unavailable: at sea"
    if not game_state.voyage.active:
        _dock()
    else:
        _update_voyage_feedback()
        _sync_state()

func _on_ship_input(event: InputEvent, selected_ship: ColorRect) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        selected_ship.set_meta("selected", true)
        selected_ship.color = Color(0.2, 0.6, 0.3)
        var label = selected_ship.get_child(0) as Label
        label.text = "Selected Ship"

func _process(delta: float) -> void:
    if current_destination == null:
        return
    game_state.ship.speed = ship_speed
    game_state.advance_voyage(delta)
    _sync_voyage()
    if not game_state.voyage.active:
        _dock()
    else:
        _update_voyage_feedback()

func _sync_voyage() -> void:
    ship.position = game_state.ship.position
    voyage_distance = game_state.voyage.distance
    voyage_time = game_state.voyage.duration
    voyage_progress = game_state.voyage.progress
    remaining_time = game_state.voyage.remaining_time

func _update_voyage_feedback() -> void:
    destination_feedback.text = "Destination: %s | %.0f%% | %.1f s remaining" % [game_state.voyage.destination_id, voyage_progress * 100.0, remaining_time]

func _dock() -> void:
    docked_port = current_destination
    current_destination = null
    _sync_voyage()
    var port_id: String = game_state.docked_port_id
    destination_feedback.text = "Docked at: %s | 100%% | click a port to sail" % port_id
    trade_feedback.text = "Trade available at %s: click to check" % port_id
    _sync_state()

func can_trade() -> bool:
    return game_state.can_trade()

func request_trade() -> bool:
    if not can_trade():
        trade_feedback.text = "Trade unavailable: dock at a port first"
        return false
    trade_feedback.text = "Trade permitted at %s" % game_state.docked_port_id
    return true

func buy(good_id: String, quantity: int) -> bool:
    var success: bool = game_state.buy(good_id, quantity)
    trade_feedback.text = "Bought %d %s" % [quantity, good_id] if success else "Buy unavailable: check dock, coins, stock and capacity"
    _sync_state()
    return success

func sell(good_id: String, quantity: int) -> bool:
    var success: bool = game_state.sell(good_id, quantity)
    trade_feedback.text = "Sold %d %s" % [quantity, good_id] if success else "Sell unavailable: check dock and cargo"
    _sync_state()
    return success

func _on_transaction_input(event: InputEvent, buying: bool) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        if buying:
            buy("sugar", 1)
        else:
            sell("sugar", 1)

func _on_trade_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        request_trade()

func _sync_state() -> void:
    set_meta("at_sea", not game_state.can_trade())
    set_meta("can_trade", can_trade())
    set_meta("docked_port_id", game_state.docked_port_id)
    var market_text: String = "Market: dock to trade"
    if can_trade():
        var market = game_state.markets[game_state.docked_port_id]
        market_text = "%s Sugar: %d coins, %d stock" % [market.port_id, market.prices["sugar"], market.inventory["sugar"]]
    economy_feedback.text = "Coins: %d | Cargo: %d/%d (Sugar %d) | %s" % [game_state.wallet.coins, game_state.cargo.total(), game_state.ship.capacity, game_state.cargo.quantity("sugar"), market_text]
