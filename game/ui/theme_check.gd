extends Node

const UI = preload("res://ui/menu_ui.gd")

func _ready() -> void:
    if DisplayServer.get_name() == "headless":
        call_deferred("run_checks")

func require_condition(value: bool, message: String) -> bool:
    if not value:
        push_error("KAN-24: " + message)
        get_tree().quit(1)
    return value

func run_checks() -> void:
    # Let deferred construction and existing voyage regression finish first.
    for frame in range(40):
        await get_tree().process_frame
    var main = get_parent()
    var board = main.get_node("ContractBoard")
    for panel in [main.market_panel, board.panel, main.get_node("Economy"), main.get_node("Trade"), main.get_node("Title"), main.get_node("Destination")]:
        if not require_condition(panel.theme == UI.DEMO_THEME, "every existing panel must use the shared resource"):
            return
        for resolution in [Vector2(1280, 720), Vector2(1920, 1080)]:
            if not require_condition(Rect2(Vector2.ZERO, resolution).encloses(panel.get_rect()), "panel must fit target viewport: " + str(panel.name)):
                return
    var actions: Array = [board.accept_button, board.complete_button]
    for collection in [main.buy_buttons, main.buy_all_buttons, main.sell_buttons, main.sell_all_buttons]:
        actions.append_array(collection.values())
    for action in actions:
        if not require_condition(action is Button and action.focus_mode == Control.FOCUS_ALL, "actions must use keyboard accessible native buttons"):
            return
        for state in ["normal", "hover", "pressed", "disabled", "focus"]:
            if not require_condition(action.has_theme_stylebox(state), "missing shared button state: " + state):
                return
        if not require_condition(action.get_theme_stylebox("normal") != action.get_theme_stylebox("hover") and action.get_theme_stylebox("normal") != action.get_theme_stylebox("disabled") and action.get_theme_stylebox("pressed") != action.get_theme_stylebox("hover"), "button states must have distinct styles"):
            return
    # Exercise native disabled handling without changing gameplay fixtures.
    var fixture := UI.panel(self, "ThemeStateFixture", Vector2.ZERO, Vector2(400, 160))
    var column := UI.column(fixture)
    var counter := [0]
    var first := UI.button(column, "First", "First action", func(): counter[0] += 1)
    var second := UI.button(column, "Second", "Second action", func(): counter[0] += 1)
    await get_tree().process_frame
    first.disabled = true
    var point := first.get_global_rect().get_center()
    for down in [true, false]:
        var click := InputEventMouseButton.new()
        click.button_index = MOUSE_BUTTON_LEFT
        click.pressed = down
        click.position = point
        get_viewport().push_input(click, true)
    if not require_condition(counter[0] == 0, "disabled buttons must reject pointer activation"):
        fixture.queue_free()
        return
    first.disabled = false
    first.grab_focus()
    if not require_condition(first.has_focus() and first.find_next_valid_focus() == second, "focus and Tab navigation must reach the next action"):
        fixture.queue_free()
        return
    fixture.queue_free()
    print("KAN-24 theme passed: shared panel resource, bounds at both target resolutions, native button state resources, disabled pointer rejection and focus navigation; human visual review remains required")
