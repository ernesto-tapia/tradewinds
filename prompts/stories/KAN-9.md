Implement KAN-9: a bounded top-down sea map with TWO distinct, clickable ports, an enabled Camera2D, and a selectable ship. Preserve the title, startup logging, project settings and Windows export. Ocean and Island are scenery, not ports. Add real Port A and Port B labeled rectangles. Do not implement sailing, trade or later stories. No images: use ColorRect boxes with Label children.

Keep the scene small: a Node2D root with Camera2D and simple rectangular Control children is sufficient. If changing the root to Node2D, update both main.tscn and main.gd's extends line. Configure finite camera limits (for example left/top=0, right=1000, bottom=600); keep the port and ship rectangles inside those world bounds and initially visible. Create nodes only once in _ready().

The feature check exercises these minimal interfaces:
- Each port is a visible Control in group "ports", with a unique metadata "destination_id" string ("Port A" / "Port B") and an interior Label displaying that ID.
- One visible ship Control is in group "player_ship", initially metadata "selected"=false. Clicking it sets selected=true and changes its rectangle color or label text so selection is visible.
- One Label in group "destination_feedback" displays the chosen port after clicking it. On a port click set metadata "destination_id" on the scene root to the clicked port's ID, and update the feedback label text to include that ID.
- The root viewport has an enabled Camera2D with meaningful finite limits.

Connect ColorRect.gui_input to handlers. For left-click presses use `if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:`. Label children need mouse_filter=Control.MOUSE_FILTER_IGNORE so clicks reach the box. Root metadata is `set_meta("destination_id", port_id)`; ship metadata is `ship.set_meta("selected", true)`; groups use `add_to_group("ports")`, etc. Control positions are world coordinates; child labels use local zero and matching size.

Run validate, scene, feature, smoke, export. The feature check injects actual viewport click events for both ports and the ship. It must fail on the unchanged KAN-8 scene. Passing baseline checks or merely renaming scenery is insufficient. Update docs/game/README.md with click controls and the fact that sailing is not implemented yet.

Godot 4 signal connection reference (do NOT use the obsolete three-argument connect("gui_input", self, "method") API):

```gdscript
port.gui_input.connect(_on_port_input.bind(port))
ship.add_to_group("player_ship")
ship.set_meta("selected", false)
ship.gui_input.connect(_on_ship_input.bind(ship))
```

Handlers receive ONE event plus the bound Control, not a viewport argument:

```gdscript
func _on_port_input(event: InputEvent, port: Control) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        var id = str(port.get_meta("destination_id"))
        set_meta("destination_id", id)
        var feedback = get_tree().get_first_node_in_group("destination_feedback") as Label
        feedback.text = "Destination: " + id

func _on_ship_input(event: InputEvent, ship: ColorRect) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        ship.set_meta("selected", true)
        ship.color = Color(0.2, 0.6, 0.3)
```

`set_meta` in the port handler means the current scene script (self), NOT get_tree().root (the engine Window). Use groups to find feedback; do not invent /root/ship or /root/destination_feedback paths. Existing local variables in _ready() are not visible inside callbacks unless passed with bind(). Set mouse_filter=Control.MOUSE_FILTER_IGNORE on the EXISTING ship label as well as the new port labels. Ensure feedback and title use separate positions so text does not overlap.
