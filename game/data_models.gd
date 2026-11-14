extends Node2D

var port_a = Control.new()
port_a.name = "Port A"
port_a.position = Vector2(290, 240)
port_a.size = Vector2(120, 65)
port_a.color = Color(0.55, 0.28, 0.12)
port_a.mouse_filter = Control.MOUSE_FILTER_STOP
port_a.add_to_group("ports")
port_a.set_meta("destination_id", "Port A")
port_a.gui_input.connect(_on_port_input.bind(port_a))

var port_b = Control.new()
port_b.name = "Port B"
port_b.position = Vector2(590, 350)
port_b.size = Vector2(120, 65)
port_b.color = Color(0.35, 0.2, 0.55)
port_b.mouse_filter = Control.MOUSE_FILTER_STOP
port_b.add_to_group("ports")
port_b.set_meta("destination_id", "Port B")
port_b.gui_input.connect(_on_port_input.bind(port_b))

var ship = Control.new()
ship.name = "Ship"
ship.position = Vector2(450, 420)
ship.size = Vector2(100, 55)
ship.color = Color(0.55, 0.55, 0.55)
ship.mouse_filter = Control.MOUSE_FILTER_STOP
ship.add_to_group("player_ship")
ship.set_meta("selected", false)
ship.gui_input.connect(_on_ship_input.bind(ship))

func _on_port_input(event: InputEvent, port: Control) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        sail_to(port)

func sail_to(port: Control) -> void:
    if port == null or not port.is_in_group("ports"):
        return
    if current_destination != null:
        return
    current_destination = port
    docked_port = null
    set_meta("destination_id", str(port.get_meta("destination_id")))
    voyage_distance = ship.position.distance_to(port.position)
    voyage_time = voyage_distance / maxf(ship_speed, 0.001)
    voyage_progress = 0.0
    remaining_time = voyage_time
    trade_feedback.text = "Trade unavailable: at sea"
    _sync_state()
    if is_zero_approx(voyage_distance):
        _dock()
    else:
        _update_voyage_feedback()

func _on_ship_input(event: InputEvent, selected_ship: Control) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        selected_ship.set_meta("selected", true)
        selected_ship.color = Color(0.2, 0.6, 0.3)
        var label = selected_ship.get_child(0) as Label
        label.text = "Selected Ship"

func _process(delta: float) -> void:
    if current_destination == null:
        return
    ship.position = ship.position.move_toward(current_destination.position, maxf(ship_speed, 0.0) * maxf(delta, 0.0))
    var remaining_distance = ship.position.distance_to(current_destination.position)
    remaining_time = remaining_distance / maxf(ship_speed, 0.001)
    voyage_progress = clampf(1.0 - remaining_distance / maxf(voyage_distance, 0.001), 0.0, 1.0)
    if remaining_distance <= 0.001:
        _dock()
    else:
        _update_voyage_feedback()

func _update_voyage_feedback() -> void:
    destination_feedback.text = "Destination: %s | %.0f%% | %.1f s remaining" % [str(current_destination.get_meta("destination_id")), voyage_progress * 100.0, remaining_time]

func _dock() -> void:
    docked_port = current_destination
    ship.position = docked_port.position
    var port_id = str(docked_port.get_meta("destination_id"))
    current_destination = null
    voyage_progress = 1.0
    remaining_time = 0.0
    destination_feedback.text = "Docked at: %s | 100%% | click a port to sail" % port_id
    trade_feedback.text = "Trade available at %s: click to check" % port_id
    _sync_state()

func can_trade() -> bool:
    return docked_port != null and current_destination == null

func request_trade() -> bool:
    if not can_trade():
        trade_feedback.text = "Trade unavailable: dock at a port first"
        return false
    trade_feedback.text = "Trade permitted at %s" % str(docked_port.get_meta("destination_id"))
    return true

func _on_trade_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        request_trade()

func _sync_state() -> void:
    set_meta("at_sea", current_destination != null or docked_port == null)
    set_meta("can_trade", can_trade())
    set_meta("docked_port_id", str(docked_port.get_meta("destination_id")) if docked_port != null else "")
