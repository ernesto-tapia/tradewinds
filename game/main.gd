extends Node2D

var destination_feedback: Label
var ship: ColorRect
var ship_speed = 200
var current_destination: Control

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

    var ocean = _box("Ocean", Vector2.ZERO, Vector2(1000, 600), Color(0.08, 0.32, 0.48))
    ocean.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var island_a = _box("Island A", Vector2(90, 130), Vector2(260, 200), Color(0.3, 0.5, 0.3))
    island_a.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var island_b = _box("Island B", Vector2(650, 240), Vector2(260, 200), Color(0.4, 0.5, 0.25))
    island_b.mouse_filter = Control.MOUSE_FILTER_IGNORE

    var port_a = _box("Port A", Vector2(290, 240), Vector2(120, 65), Color(0.55, 0.28, 0.12))
    var port_b = _box("Port B", Vector2(590, 350), Vector2(120, 65), Color(0.35, 0.2, 0.55))
    for port in [port_a, port_b]:
        port.add_to_group("ports")
        port.set_meta("destination_id", port.name)
        port.gui_input.connect(_on_port_input.bind(port))

    ship = _box("Ship", Vector2(450, 420), Vector2(100, 55), Color(0.55, 0.55, 0.55))
    ship.add_to_group("player_ship")
    ship.set_meta("selected", false)
    ship.gui_input.connect(_on_ship_input.bind(ship))

    var title = _box("Caribbean Tradewinds", Vector2(250, 15), Vector2(500, 45), Color(0.1, 0.16, 0.2))
    title.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var feedback_box = _box("Destination: click a port", Vector2(250, 520), Vector2(500, 55), Color(0.1, 0.16, 0.2))
    feedback_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    destination_feedback = feedback_box.get_child(0) as Label
    destination_feedback.add_to_group("destination_feedback")

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
        var port_id = str(port.get_meta("destination_id"))
        set_meta("destination_id", port_id)
        destination_feedback.text = "Destination: " + port_id
        current_destination = port

func _on_ship_input(event: InputEvent, ship: ColorRect) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        ship.set_meta("selected", true)
        ship.color = Color(0.2, 0.6, 0.3)
        var label = ship.get_child(0) as Label
        label.text = "Selected Ship"

func _process(delta: float) -> void:
    if current_destination:
        var ship_position = ship.position
        var destination_position = current_destination.position
        var direction = (destination_position - ship_position).normalized()
        ship_position += direction * ship_speed * delta
        ship.position = ship_position
        if ship_position.distance_to(destination_position) < 10:
            current_destination = null
            destination_feedback.text = "Docked at: " + str(current_destination.get_meta("destination_id")) if current_destination else "Destination: click a port"