extends RefCounted

const DEMO_THEME: Theme = preload("res://ui/demo_theme.tres")

static func panel(parent: Node, id: String, at: Vector2, dimensions: Vector2) -> PanelContainer:
    var control := PanelContainer.new()
    control.name = id
    control.theme = DEMO_THEME
    control.position = at
    control.size = dimensions
    parent.add_child(control)
    return control

static func column(parent: Node) -> VBoxContainer:
    var control := VBoxContainer.new()
    control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    control.size_flags_vertical = Control.SIZE_EXPAND_FILL
    parent.add_child(control)
    return control

static func row(parent: Node) -> HBoxContainer:
    var control := HBoxContainer.new()
    control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    parent.add_child(control)
    return control

static func scroll_column(parent: Node) -> VBoxContainer:
    var scroll := ScrollContainer.new()
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.follow_focus = true
    parent.add_child(scroll)
    return column(scroll)

static func label(parent: Node, text: String, variation: String = "Label") -> Label:
    var control := Label.new()
    control.text = text
    control.theme_type_variation = variation
    control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    control.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(control)
    return control

static func button(parent: Node, id: String, text: String, callback: Callable, primary: bool = false) -> Button:
    var control := Button.new()
    control.name = id
    control.text = text
    control.theme_type_variation = "PrimaryButton" if primary else "Button"
    control.custom_minimum_size = Vector2(0, 56)
    control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    control.focus_mode = Control.FOCUS_ALL
    control.pressed.connect(callback)
    control.focus_entered.connect(refresh_focus.bind(control))
    control.gui_input.connect(navigate_focus.bind(control))
    parent.add_child(control)
    return control

static func refresh_focus(source: Button) -> void:
    # Menus are separate root Controls beneath the game Node2D. Explicit
    # links let Tab cross those roots and skip currently unavailable actions.
    var root: Node = source
    while root is Control and root.get_parent() != null:
        root = root.get_parent()
    var actions: Array[Button] = []
    for node in root.find_children("*", "Button", true, false):
        var action := node as Button
        if action.is_visible_in_tree() and not action.disabled and action.focus_mode == Control.FOCUS_ALL:
            actions.append(action)
    for index in range(actions.size()):
        var action: Button = actions[index]
        action.focus_next = action.get_path_to(actions[(index + 1) % actions.size()])
        action.focus_previous = action.get_path_to(actions[(index + actions.size() - 1) % actions.size()])

static func navigate_focus(event: InputEvent, source: Button) -> void:
    var backwards := event.is_action_pressed("ui_focus_prev")
    if not backwards and not event.is_action_pressed("ui_focus_next"):
        return
    # Rebuild on navigation as docking, transactions and contract actions can
    # change availability while the current button retains keyboard focus.
    refresh_focus(source)
    var target_path: NodePath = source.focus_previous if backwards else source.focus_next
    if target_path.is_empty():
        return
    var target := source.get_node_or_null(target_path) as Button
    if target != null and target.is_visible_in_tree() and not target.disabled:
        target.grab_focus()
        source.accept_event()

static func value_row(parent: Node, text: String) -> Label:
    var line := row(parent)
    label(line, text)
    var value := label(line, "0")
    value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    value.custom_minimum_size.x = 64
    return value

static func status(control: Label, text: String, warning: bool = false) -> void:
    control.text = text
    control.theme_type_variation = "Warning" if warning else "Label"
