extends RefCounted

const DEMO_THEME = preload("res://ui/demo_theme.tres")

# Shared constructors; containers own all menu content positions and sizes.
static func panel(parent: Node, id: String, at: Vector2, dimensions: Vector2) -> PanelContainer:
    var result := PanelContainer.new()
    result.name = id
    result.theme = DEMO_THEME
    result.position = at
    result.size = dimensions
    parent.add_child(result)
    return result

static func column(parent: Node) -> VBoxContainer:
    var result := VBoxContainer.new()
    result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    parent.add_child(result)
    return result

static func row(parent: Node) -> HBoxContainer:
    var result := HBoxContainer.new()
    result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    parent.add_child(result)
    return result

static func label(parent: Node, text: String, variation: String = "") -> Label:
    var result := Label.new()
    result.text = text
    result.theme_type_variation = variation
    result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    result.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(result)
    return result

static func button(parent: Node, id: String, text: String, action: Callable, primary: bool = false) -> Button:
    var result := Button.new()
    result.name = id
    result.text = text
    result.theme_type_variation = "PrimaryButton" if primary else "Button"
    result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    result.custom_minimum_size.y = 48
    result.focus_mode = Control.FOCUS_ALL
    result.pressed.connect(action)
    parent.add_child(result)
    return result

static func scroll_column(parent: Node) -> VBoxContainer:
    var scroll := ScrollContainer.new()
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.follow_focus = true
    parent.add_child(scroll)
    return column(scroll)

static func value_row(parent: Node, title: String) -> Label:
    var line := row(parent)
    label(line, title)
    var value := label(line, "0")
    value.autowrap_mode = TextServer.AUTOWRAP_OFF
    value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    value.custom_minimum_size.x = 80
    return value

static func status(target: Label, text: String, failed: bool = false) -> void:
    target.text = text
    target.theme_type_variation = "Error" if failed else "Label"
