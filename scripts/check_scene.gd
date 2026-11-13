extends SceneTree

# Acceptance check for the intentionally simple labeled-box demo. No rendering
# screenshot or visual observation is claimed by this headless test.
func _initialize() -> void:
	call_deferred("check_scene")

func check_scene() -> void:
	var scene_path: String = ProjectSettings.get_setting("application/run/main_scene", "")
	if scene_path.is_empty():
		push_error("Scene contract: configure application/run/main_scene")
		quit(1)
		return
	var packed = load(scene_path)
	if not packed is PackedScene:
		push_error("Scene contract: main scene must be a PackedScene")
		quit(1)
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	var title_found := false
	var rectangles := 0
	var failures: Array[String] = []
	var nodes: Array[Node] = [scene]
	nodes.append_array(scene.find_children("*", "", true, false))
	for node in nodes:
		if node is Label and "Caribbean Tradewinds" in node.text:
			title_found = true
		if node is ColorRect or node is Panel:
			rectangles += 1
			var labeled := false
			for child in node.find_children("*", "Label", true, false):
				if not child.text.strip_edges().is_empty():
					labeled = true
					if not node.get_global_rect().encloses(child.get_global_rect()):
						failures.append("Label must fit inside its rectangle; use local position Vector2.ZERO and matching size: " + str(child.name))
			if not labeled:
				failures.append("Every placeholder rectangle needs a nonempty Label inside: " + str(node.name))
		if node is Sprite2D or node is TextureRect or node is Polygon2D or node is AnimatedSprite2D or node is MeshInstance2D:
			failures.append("Only labeled boxes are allowed; remove " + node.get_class())
	if rectangles == 0:
		failures.append("Create at least one labeled ColorRect or Panel in _ready() at startup for the map/ocean placeholder. Move UI creation out of _process(), which runs every frame.")
	if not title_found:
		failures.append("Create a Label displaying Caribbean Tradewinds in _ready() at startup, not _process()")
	for failure in failures:
		push_error("Scene contract: " + failure)
	if failures.is_empty():
		print("Scene contract passed: title and labeled rectangles exist; no complex visual nodes")
	quit(0 if failures.is_empty() else 1)
