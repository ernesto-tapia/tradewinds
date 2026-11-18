extends Node

const Main = preload("res://main.gd")
const Supplies = preload("res://provisioning.gd")
const Models = preload("res://data_models.gd")

func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        call_deferred("run_checks")

func require_condition(value: bool, message: String) -> bool:
    if not value:
        push_error("KAN-16 provisioning: " + message)
        get_tree().quit(1)
    return value

func click_port(viewport: SubViewport, port: Control) -> void:
    var point := port.get_global_transform_with_canvas() * (port.size / 2.0)
    var motion := InputEventMouseMotion.new()
    motion.position = point
    viewport.push_input(motion, true)
    for down in [true, false]:
        var event := InputEventMouseButton.new()
        event.button_index = MOUSE_BUTTON_LEFT
        event.pressed = down
        event.position = point
        viewport.push_input(event, true)
    await get_tree().process_frame

func check_rounding() -> bool:
    for fixture in [[100.0, 1], [100.1, 2], [250.0, 3]]:
        var state = Models.new()
        state.ship.position = Vector2.ZERO
        state.ports["Port A"].position = Vector2.ZERO
        state.ports["Port B"].position = Vector2(float(fixture[0]), 0)
        state.docked_port_id = "Port A"
        var expected := int(fixture[1])
        state.provisions = expected + 7
        if not require_condition(state.required_provisions("Port B") == expected, "distance %s must require %d" % [fixture[0], expected]):
            return false
        if not require_condition(state.start_voyage("Port B") and state.provisions == 7 and state.voyage.provisions_consumed == expected, "departure must consume exactly the rounded distance cost"):
            return false
        state.advance_voyage(state.voyage.duration / 2.0)
        if not require_condition(state.provisions == 7, "mid-voyage updates must not charge again"):
            return false
        state.advance_voyage(state.voyage.duration + 1.0)
        if not require_condition(state.provisions == 7 and not state.voyage.active, "arrival must not charge again"):
            return false
    return true

func run_checks() -> void:
    if not check_rounding():
        return
    var host := SubViewportContainer.new()
    host.position = Vector2(3000, 0)
    add_child(host)
    var viewport := SubViewport.new()
    viewport.size = Vector2i(1280, 720)
    viewport.handle_input_locally = true
    host.add_child(viewport)
    var game = Main.new()
    viewport.add_child(game)
    game.set_process(false)
    var supplies = Supplies.new()
    supplies.name = "Provisioning"
    game.add_child(supplies)
    await get_tree().process_frame
    await get_tree().process_frame
    supplies.set_process(false)
    if not require_condition(supplies.game_state == game.game_state and supplies.buy_button.disabled, "at-sea purchases use the real state and are disabled"):
        return
    await click_port(viewport, game.get_node("Port A"))
    game._process(game.voyage_time + 1.0)
    supplies.refresh_provisioning()
    if not require_condition(game.game_state.docked_port_id == "Port A" and not supplies.buy_button.disabled, "port click docks and enables purchases"):
        return
    var coins: int = game.game_state.wallet.coins
    var reserve: int = game.game_state.provisions
    if not require_condition(supplies.buy_provisions() and game.game_state.provisions == reserve + 4 and game.game_state.wallet.coins == coins - 8, "purchase adds four supplies and charges eight coins"):
        return
    # Actual A-to-B distance is 319.53: ceil(distance / 100) = 4.
    if not require_condition(game.game_state.required_provisions("Port B") == 4, "actual A-to-B route requires four"):
        return
    for insufficient in [0, 3]:
        game.game_state.provisions = insufficient
        game.refresh_provisioning_panel()
        game.refresh_voyage()
        if not require_condition("Port A 0" in supplies.route_label.text and "Port B 4" in supplies.route_label.text, "panel displays exact requirements before departure"):
            return
        if not require_condition("Port B requires 4" in game.destination_feedback.text and "requires 4 provisions" in game.get_node("Port B").tooltip_text, "HUD and tooltip display the required amount"):
            return
        var position_before: Vector2 = game.game_state.ship.position
        var coins_before: int = game.game_state.wallet.coins
        var cargo_before: Dictionary = game.game_state.cargo.quantities.duplicate(true)
        var voyage_before: Array = [game.game_state.voyage.destination_id, game.game_state.voyage.progress, game.game_state.voyage.provisions_consumed]
        await click_port(viewport, game.get_node("Port B"))
        if not require_condition(not game.game_state.voyage.active and game.game_state.docked_port_id == "Port A" and game.game_state.ship.position == position_before, "insufficient supplies prevent departure and preserve docking/position"):
            return
        if not require_condition(game.game_state.provisions == insufficient and game.game_state.wallet.coins == coins_before and game.game_state.cargo.quantities == cargo_before and voyage_before == [game.game_state.voyage.destination_id, game.game_state.voyage.progress, game.game_state.voyage.provisions_consumed], "rejection preserves resources and voyage state"):
            return
        if not require_condition(("requires 4 provisions; aboard %d" % insufficient) in game.destination_feedback.text, "rejection displays required and available supplies"):
            return
    game.game_state.provisions = 4
    game.refresh_provisioning_panel()
    await click_port(viewport, game.get_node("Port B"))
    if not require_condition(game.game_state.voyage.active and game.game_state.provisions == 0 and game.game_state.voyage.provisions_consumed == 4, "exactly four permits departure and deducts four once"):
        return
    supplies.refresh_provisioning()
    if not require_condition("consumed 4" in game.destination_feedback.text and "Consumed at departure: 4" in supplies.route_label.text, "sailing HUD and panel display exact consumption"):
        return
    if not require_condition(not game.game_state.start_voyage("Port B") and game.game_state.provisions == 0, "repeated departure cannot charge twice"):
        return
    game._process(game.voyage_time / 2.0)
    if not require_condition(game.game_state.voyage.active and game.game_state.provisions == 0, "midpoint consumes no additional supplies"):
        return
    game._process(game.voyage_time + 1.0)
    if not require_condition(game.game_state.docked_port_id == "Port B" and not game.game_state.voyage.active and game.game_state.provisions == 0, "arrival retains exact remaining reserve"):
        return
    host.queue_free()
    print("KAN-16 provisioning acceptance passed: real clicks reject zero/one-short supplies atomically; displayed A=0/B=4 requirements and rejection amounts; exact-four departure consumes once; no repeat/midpoint/arrival charge; 100/100.1/250-unit rounding; dock purchase +4/-8.")
