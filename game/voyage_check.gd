extends Node

# Headless interaction regression, executed by the configured smoke launch.
# Uses viewport mouse events for ports and keyboard activation for Trade.
var test_viewport: SubViewport

func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        call_deferred("check_voyages")

func click_control(control: Control) -> void:
    if control is Button:
        control.grab_focus()
        for down in [true, false]:
            var key := InputEventKey.new()
            key.keycode = KEY_ENTER
            key.physical_keycode = KEY_ENTER
            key.pressed = down
            test_viewport.push_input(key, true)
        await get_tree().process_frame
        return
    var point = control.get_global_transform_with_canvas() * (control.size * 0.5)
    var motion := InputEventMouseMotion.new()
    motion.position = point
    test_viewport.push_input(motion, true)
    await get_tree().process_frame
    for pressed in [true, false]:
        var event = InputEventMouseButton.new()
        event.button_index = MOUSE_BUTTON_LEFT
        event.pressed = pressed
        event.position = point
        event.global_position = point
        test_viewport.push_input(event, true)
        await get_tree().process_frame
    await get_tree().process_frame

func require_condition(value: bool, message: String) -> bool:
    if not value:
        push_error("KAN-10 interaction: " + message)
        get_tree().quit(1)
    return value

func check_voyages() -> void:
    # Native GUI focus is shared across embedded viewports. Let the theme
    # keyboard fixture finish before this fixture activates Trade.
    await get_tree().process_frame
    var theme_check := get_parent().get_node_or_null("ThemeStateCheck")
    for frame in range(60):
        if theme_check == null or theme_check.get_child_count() == 0:
            break
        await get_tree().process_frame
    if not require_condition(theme_check == null or theme_check.get_child_count() == 0, "theme keyboard fixture must finish before voyage input"):
        return
    var host := SubViewportContainer.new()
    host.position = Vector2(3000, 0)
    add_child(host)
    test_viewport = SubViewport.new()
    test_viewport.size = Vector2i(1280, 720)
    test_viewport.handle_input_locally = true
    test_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    host.add_child(test_viewport)
    test_viewport.gui_disable_input = false
    var game = preload("res://main.gd").new()
    test_viewport.add_child(game)
    game.set_process(false)
    # Four actual voyages cost 3+4+4+4; seed only this isolated fixture.
    game.game_state.provisions = 40
    game.refresh_route_requirements()
    await get_tree().process_frame
    await get_tree().process_frame
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
        if not require_condition("unavailable" in game.trade_feedback.text and not game.request_trade(), "trade activation and requests must be rejected at sea"):
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
        if not require_condition("permitted" in game.trade_feedback.text and game.market_panel.visible, "trade activation must open the market while docked"):
            return
        # The ship overlaps the port center while docked; click its exposed corner.
        var provisions_before: int = game.game_state.provisions
        var event := InputEventMouseButton.new()
        event.button_index = MOUSE_BUTTON_LEFT
        event.pressed = true
        event.position = port.get_global_transform_with_canvas() * (port.size - Vector2(5, 5))
        event.global_position = event.position
        test_viewport.push_input(event, true)
        event = event.duplicate()
        event.pressed = false
        test_viewport.push_input(event, true)
        await get_tree().process_frame
        if not require_condition(game.game_state.provisions == provisions_before, "current-port click must not consume provisions"):
            return
        if not require_condition(game.voyage_time == 0.0 and not game.game_state.voyage.active, "current-port click must complete a zero-distance voyage immediately"):
            return
        if not require_condition(game.docked_port == port and game.current_destination == null and not game.get_meta("at_sea"), "current-port click must preserve docked scene state immediately"):
            return
        if not require_condition(game.game_state.docked_port_id == str(port.name) and game.can_trade() and game.market_panel.visible, "current-port click must preserve docking and the market (menu=%s, dock=%s, trade=%s, market=%s)" % [game.active_menu, game.game_state.docked_port_id, game.can_trade(), game.market_panel.visible]):
            return
        if not require_condition(game.ship.position == stopped and game.voyage_progress == 1.0 and game.remaining_time == 0.0, "current-port click must preserve completed voyage state"):
            return
        game._process(10.0)
        if not require_condition(game.docked_port == port and game.current_destination == null and not game.get_meta("at_sea") and game.ship.position == stopped, "current-port docking must remain stable on subsequent frames"):
            return
        await click_control(trade)
        if not require_condition("permitted" in game.trade_feedback.text and game.request_trade(), "trade must remain permitted after clicking the current port"):
            return
        if not require_condition(game.get_child_count() == node_count, "travel must not recreate static UI"):
            return
    host.queue_free()
    print("KAN-10 interaction passed: viewport clicks sailed A/B/A/B; midpoint progress, arrival stop, at-sea trade rejection, docked trade and current-port immediate arrival verified")
