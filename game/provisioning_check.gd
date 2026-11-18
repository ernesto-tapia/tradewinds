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

func click_port(viewport: SubViewport, control: Control) -> void:
    var point := control.get_global_transform_with_canvas() * (control.size / 2.0)
    var motion := InputEventMouseMotion.new()
    motion.position = point
    motion.global_position = point
    viewport.push_input(motion, true)
    for down in [true, false]:
        var event := InputEventMouseButton.new()
        event.button_index = MOUSE_BUTTON_LEFT
        event.pressed = down
        event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
        event.position = point
        event.global_position = point
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

func check_sailing_tooltips(game) -> bool:
    for port_id in ["Port A", "Port B"]:
        var tooltip: String = game.get_node(port_id).tooltip_text
        if not require_condition("departure unavailable while sailing to Port B" in tooltip and "charged 4 provisions at departure" in tooltip and "aboard 0" in tooltip and not "requires" in tooltip, "underway tooltips show fixed charge and unavailable departure for " + port_id):
            return false
    return true

func run_checks() -> void:
    if not check_rounding():
        return
    await get_tree().process_frame
    for check_name in ["ThemeStateCheck", "VoyageInteractionCheck"]:
        var other := get_parent().get_node_or_null(NodePath(check_name))
        for frame in range(90):
            if other == null or other.get_child_count() == 0:
                break
            await get_tree().process_frame
        if not require_condition(other == null or other.get_child_count() == 0, check_name + " must finish before provisioning pointer input"):
            return
    # A standalone viewport uses its injected local mouse coordinates. A
    # SubViewportContainer instead derives hover from the native window mouse,
    # which is outside an offscreen container. Keep all purchase assertions.
    var host := Node.new()
    add_child(host)
    var viewport := SubViewport.new()
    viewport.size = Vector2i(1280, 720)
    viewport.handle_input_locally = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    host.add_child(viewport)
    viewport.gui_disable_input = false
    viewport.notify_mouse_entered()
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
    var scroll := supplies.buy_button.get_parent().get_parent() as ScrollContainer
    scroll.ensure_control_visible(supplies.buy_button)
    await get_tree().process_frame
    await get_tree().process_frame
    var button_rect: Rect2 = supplies.buy_button.get_global_rect()
    var visible_rect: Rect2 = scroll.get_global_rect().intersection(button_rect)
    if not require_condition(visible_rect.has_point(button_rect.get_center()), "purchase button center must be visible; button=%s scroll=%s" % [button_rect, scroll.get_global_rect()]):
        return
    var activations: Array[int] = [0]
    supplies.buy_button.pressed.connect(func(): activations[0] += 1)
    await click_port(viewport, supplies.buy_button)
    if not require_condition(activations[0] == 1 and game.game_state.provisions == reserve + 4 and game.game_state.wallet.coins == coins - 8 and "Bought 4 provisions" in supplies.feedback.text, "purchase button adds four supplies, charges eight coins and shows feedback; activations=%d reserve=%d coins=%d feedback=%s hovered=%s button=%s scroll=%s" % [activations[0], game.game_state.provisions, game.game_state.wallet.coins, supplies.feedback.text, viewport.gui_get_hovered_control(), button_rect, scroll.get_global_rect()]):
        return
    if not require_condition(("Balance: %d provisions" % (reserve + 4)) in supplies.balance_label.text, "purchase updates displayed reserve"):
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
    if not require_condition("consumed 4" in game.destination_feedback.text and "Consumed at departure: 4" in supplies.route_label.text and "Balance: 0 provisions" in supplies.balance_label.text, "sailing HUD and panel display exact consumption and remaining balance"):
        return
    if not check_sailing_tooltips(game):
        return
    await click_port(viewport, game.get_node("Port B"))
    if not require_condition(game.game_state.voyage.active and game.game_state.provisions == 0 and "Already sailing" in game.destination_feedback.text, "repeated port click rejects departure without another charge"):
        return
    if not require_condition(not game.game_state.start_voyage("Port B") and game.game_state.provisions == 0, "repeated departure cannot charge twice"):
        return
    game._process(game.voyage_time / 2.0)
    if not require_condition(game.game_state.voyage.active and game.game_state.provisions == 0, "midpoint consumes no additional supplies"):
        return
    if not require_condition("50%" in game.destination_feedback.text and "requires 4 provisions; consumed 4" in game.destination_feedback.text, "midpoint HUD retains accepted departure summary after rejected clicks"):
        return
    if not check_sailing_tooltips(game):
        return
    game._process(game.voyage_time / 4.0)
    if not check_sailing_tooltips(game):
        return
    game._process(game.voyage_time + 1.0)
    if not require_condition(game.game_state.docked_port_id == "Port B" and not game.game_state.voyage.active and game.game_state.provisions == 0, "arrival retains exact remaining reserve"):
        return
    if not require_condition("Port A requires 4 provisions; aboard 0" in game.get_node("Port A").tooltip_text and "Port B requires 0 provisions; aboard 0" in game.get_node("Port B").tooltip_text, "arrival restores departure quotes from docked position"):
        return
    if not require_condition("Port A 4" in supplies.route_label.text and "Port B 0" in supplies.route_label.text, "arrival restores panel departure requirements"):
        return
    host.queue_free()
    print("KAN-16 provisioning acceptance passed: pointer purchase +4/-8 and displayed balance; real clicks reject zero/one-short supplies atomically; displayed A=0/B=4 requirements and rejection amounts; exact-four departure consumes once; rejected underway clicks preserve refreshed summary; fixed-charge tooltips at departure/midpoint/75%, dock quotes restored on arrival; no repeat/midpoint/arrival charge; 100/100.1/250-unit rounding.")
