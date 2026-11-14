extends Node2D

var destination_feedback: Label
var trade_feedback: Label
var ship: ColorRect
var ship_speed: float = 200.0
var current_destination: Control
var docked_port: Control
var voyage_distance: float = 0.0
var voyage_time: float = 0.0
var voyage_progress: float = 0.0
var remaining_time: float = 0.0

func _ready() -> void:
    print("Caribbean Tradewinds: map ready")
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
    var port_a = _box("Port A", Vector2(290, 240), Vector2(120, 65), Color(0.55, 0.28, 0.12))
    var port_b = _box("Port B", Vector2(590, 350), Vector2(120, 65), Color(0.35, 0.2, 0.55))
    for port in [port_a, port_b]:
        port.mouse_filter = Control.MOUSE_FILTER_STOP
        port.add_to_group("ports")
        port.set_meta("destination_id", port.name)
        port.gui_input.connect(_on_port_input.bind(port))

    ship = _box("Ship", Vector2(450, 420), Vector2(100, 55), Color(0.55, 0.55, 0.55))
    ship.mouse_filter = Control.MOUSE_FILTER_STOP
    ship.add_to_group("player_ship")
    ship.set_meta("selected", false)
    ship.gui_input.connect(_on_ship_input.bind(ship))
    _box("Caribbean Tradewinds", Vector2(250, 15), Vector2(500, 45), Color(0.1, 0.16, 0.2))
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
    if port == null or not port.is_in_group("ports"):
        return
    # Keep the active voyage stable until arrival; another voyage can start immediately after docking.
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

func _on_ship_input(event: InputEvent, selected_ship: ColorRect) -> void:
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
