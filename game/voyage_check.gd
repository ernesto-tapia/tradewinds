extends Node

# Headless interaction regression, executed by the configured smoke launch.
# Uses viewport mouse events for destinations and the trade rectangle.
func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        call_deferred("check_voyages")

func click_control(control: Control) -> void:
    var point = control.get_global_transform_with_canvas() * (control.size * 0.5)
    for pressed in [true, false]:
        var event = InputEventMouseButton.new()
        event.button_index = MOUSE_BUTTON_LEFT
        event.pressed = pressed
        event.position = point
        event.global_position = point
        get_viewport().push_input(event, true)
    await get_tree().process_frame

func require_condition(value: bool, message: String) -> bool:
    if not value:
        push_error("KAN-10 interaction: " + message)
        get_tree().quit(1)
    return value

func check_voyages() -> void:
    await get_tree().process_frame
    var game = get_parent()
    game.set_process(false)
    var port_a = game.get_node("Port A") as Control
    var port_b = game.get_node("Port B") as Control
    var trade = game.trade_feedback.get_parent() as Control
    var node_count = game.get_child_count()
    for port in [port_a, port_b, port_a, port_b]:
        await click_control(port)
        if not require_condition(game.current_destination == port, "destination center click must start sailing to " + str(port.name)):
            return
        if not require_condition(not game.can_trade() and game.get_meta("at_sea"), "departure must disable trade"):
            return
        await click_control(trade)
        if not require_condition("unavailable" in game.trade_feedback.text and not game.request_trade(), "trade clicks and requests must be rejected at sea"):
            return
        var start: Vector2 = game.ship.position
        var duration: float = game.voyage_time
        if not require_condition(duration > 0.0, "voyage must have a positive travel time"):
            return
        game._process(duration * 0.5)
        if not require_condition(game.ship.position != start and is_equal_approx(game.voyage_progress, 0.5), "half the travel time must move the ship to 50 percent"):
            return
        if not require_condition("50%" in game.destination_feedback.text and game.remaining_time > 0.0, "visible progress and remaining time must update"):
            return
        game._process(duration)
        if not require_condition(game.current_destination == null and game.docked_port == port and game.can_trade(), "arrival must dock and restore trading"):
            return
        if not require_condition(game.voyage_progress == 1.0 and game.remaining_time == 0.0, "arrival must complete progress"):
            return
        var stopped: Vector2 = game.ship.position
        game._process(10.0)
        if not require_condition(game.ship.position == stopped, "ship must remain stopped after arrival"):
            return
        await click_control(trade)
        if not require_condition("permitted" in game.trade_feedback.text, "trade click must succeed while docked"):
            return
        if not require_condition(game.get_child_count() == node_count, "travel must not recreate static UI"):
            return
    game.set_process(true)
    print("KAN-10 interaction passed: viewport clicks sailed A/B/A/B; midpoint progress, arrival stop, at-sea trade rejection and docked trade verified")
