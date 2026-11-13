"""Optional live Godot acceptance checks: set GODOT_TEST_BIN to enable."""
import os
from pathlib import Path
import tempfile
import unittest

from harness.core import run_process


@unittest.skipUnless(os.environ.get('GODOT_TEST_BIN'), 'GODOT_TEST_BIN not set')
class SceneContractTests(unittest.TestCase):
    def test_kan9_exercises_port_clicks_and_ship_selection(self):
        checker = Path(__file__).resolve().parents[1] / 'scripts/check_kan9.gd'
        script = '''extends Node2D
var feedback: Label
func box(text: String, at: Vector2) -> ColorRect:
    var item = ColorRect.new()
    item.position = at
    item.size = Vector2(140, 70)
    item.color = Color(0.1, 0.2, 0.3)
    add_child(item)
    var label = Label.new()
    label.text = text
    label.size = item.size
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    item.add_child(label)
    return item
func _ready():
    var camera = Camera2D.new()
    camera.position = Vector2(500, 300)
    camera.limit_left = 0
    camera.limit_top = 0
    camera.limit_right = 1000
    camera.limit_bottom = 600
    add_child(camera)
    feedback = Label.new()
    feedback.size = Vector2(400, 30)
    feedback.add_to_group("destination_feedback")
    add_child(feedback)
    for i in range(2):
        var port = box("Port " + str(i), Vector2(100 + i * 500, 130))
        port.set_meta("destination_id", "Port " + str(i))
        port.add_to_group("ports")
        port.gui_input.connect(port_input.bind(port))
    var ship = box("Ship", Vector2(400, 400))
    ship.add_to_group("player_ship")
    ship.set_meta("selected", false)
    ship.gui_input.connect(ship_input.bind(ship))
func port_input(event: InputEvent, port: Control):
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        set_meta("destination_id", port.get_meta("destination_id"))
        feedback.text = "Destination: " + str(port.get_meta("destination_id"))
func ship_input(event: InputEvent, ship: ColorRect):
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        ship.set_meta("selected", true)
        ship.color = Color(0.8, 0.3, 0.2)
'''
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'project.godot').write_text('config_version=5\n[application]\nrun/main_scene="res://main.tscn"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
            (root / 'main.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://main.gd" id="1"]\n[node name="Main" type="Node2D"]\nscript=ExtResource("1")\n')
            for content, success in [(script, True), (script.replace('port.gui_input.connect(port_input.bind(port))', 'pass'), False)]:
                with self.subTest(success=success):
                    (root / 'main.gd').write_text(content)
                    result = run_process([os.environ['GODOT_TEST_BIN'], '--headless', '--path', str(root), '--script', str(checker)], root, 30)
                    self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)

    def test_labeled_box_passes_and_blank_or_misaligned_scene_fails(self):
        checker = Path(__file__).resolve().parents[1] / 'scripts/check_scene.gd'
        script = '''extends Control
func _ready():
    var title = Label.new()
    title.text = "Caribbean Tradewinds"
    add_child(title)
    var box = ColorRect.new()
    box.position = Vector2(20, 60)
    box.size = Vector2(400, 180)
    add_child(box)
    var label = Label.new()
    label.text = "Ocean"
    label.position = Vector2.ZERO
    label.size = box.size
    box.add_child(label)
'''
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'project.godot').write_text('config_version=5\n[application]\nrun/main_scene="res://main.tscn"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
            (root / 'main.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://main.gd" id="1"]\n[node name="Main" type="Control"]\nscript=ExtResource("1")\n')
            for content, success, expected in [
                (script, True, 'Scene contract passed'),
                (script.replace('label.position = Vector2.ZERO', 'label.position = Vector2(300, 100)'), False, 'Label must fit inside'),
                ('extends Control\n', False, 'Create at least one labeled')]:
                with self.subTest(success=success, expected=expected):
                    (root / 'main.gd').write_text(content)
                    result = run_process([os.environ['GODOT_TEST_BIN'], '--headless', '--path', str(root), '--script', str(checker)], root, 30)
                    output = result.stdout + result.stderr
                    self.assertEqual(result.returncode == 0, success, output)
                    self.assertIn(expected, output)
