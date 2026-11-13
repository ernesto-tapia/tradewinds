extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("check_feature")

func click_control(control: Control) -> void:
	var point: Vector2 = control.get_global_transform_with_canvas() * (control.size / 2.0)
	if not root.get_visible_rect().has_point(point):
		failures.append("Keep clickable map items visible in the initial camera view: " + str(control.name))
		return
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	await process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		root.push_input(event, true)
		await process_frame

func finish() -> void:
	for failure in failures:
		push_error("KAN-9 feature: " + failure)
	if failures.is_empty():
		print("KAN-9 feature passed: two distinct ports clicked, destination feedback changed, ship selected, bounded camera present")
	quit(0 if failures.is_empty() else 1)

func check_feature() -> void:
	# Script-mode headless windows may default to 64x64. Match the game's
	# configured viewport before exercising actual Control hit-testing.
	var width := int(ProjectSettings.get_setting("display/window/size/viewport_width", 1152))
	var height := int(ProjectSettings.get_setting("display/window/size/viewport_height", 648))
	root.size = Vector2i(width if width > 0 else 1152, height if height > 0 else 648)
	var scene_path: String = ProjectSettings.get_setting("application/run/main_scene", "")
	var packed = load(scene_path)
	if not packed is PackedScene:
		failures.append("Configure a runnable main scene")
		finish()
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var ports := get_nodes_in_group("ports")
	var ships := get_nodes_in_group("player_ship")
	var feedback := get_nodes_in_group("destination_feedback")
	if ports.size() != 2 or ships.size() != 1 or feedback.size() != 1:
		failures.append("Add two real port Controls in group ports, one selectable ship in group player_ship, and one feedback Label in group destination_feedback. Ocean and Island scenery are not ports.")
		finish()
		return
	var camera := root.get_camera_2d()
	if camera == null or not camera.enabled or camera.limit_right <= camera.limit_left or camera.limit_bottom <= camera.limit_top or camera.limit_right - camera.limit_left > 100000 or camera.limit_bottom - camera.limit_top > 100000:
		failures.append("Add an enabled Camera2D with finite, meaningful map limits")
		finish()
		return
	var bounds := Rect2(camera.limit_left, camera.limit_top, camera.limit_right - camera.limit_left, camera.limit_bottom - camera.limit_top)
	var ids: Array[String] = []
	for port in ports:
		var id: String = str(port.get_meta("destination_id", ""))
		if not port is Control or id.is_empty() or id in ids:
			failures.append("Each port must be a Control with a distinct nonempty destination_id metadata string")
			continue
		ids.append(id)
		var identifiable := false
		for label in port.find_children("*", "Label", true, false):
			if id in label.text:
				identifiable = true
		if not identifiable or not port.is_visible_in_tree() or not bounds.encloses(port.get_global_rect()):
			failures.append("Each port needs its own interior identity label and must be visible inside map bounds")
		await click_control(port)
		if str(scene.get_meta("destination_id", "")) != id or not feedback[0] is Label or not id in feedback[0].text:
			failures.append("Clicking " + id + " must set the scene destination_id and update the destination_feedback Label")
	var ship = ships[0]
	if not ship is Control or not ship.is_visible_in_tree() or not bounds.encloses(ship.get_global_rect()):
		failures.append("The ship must be a visible clickable Control inside map bounds")
		finish()
		return
	if bool(ship.get_meta("selected", false)):
		failures.append("Ship should start unselected so selection can be exercised")
	var before_color = ship.color if ship is ColorRect else null
	var before_text := ""
	for label in ship.find_children("*", "Label", true, false):
		before_text += label.text
	await click_control(ship)
	var after_text := ""
	for label in ship.find_children("*", "Label", true, false):
		after_text += label.text
	var color_changed: bool = ship is ColorRect and ship.color != before_color
	if not bool(ship.get_meta("selected", false)) or (not color_changed and before_text == after_text):
		failures.append("Click the ship to set selected=true and visibly change its color or label")
	finish()
