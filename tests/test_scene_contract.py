"""Optional live Godot acceptance checks: set GODOT_TEST_BIN to enable."""
import os
from pathlib import Path
import tempfile
import unittest

from harness.core import run_process


@unittest.skipUnless(os.environ.get('GODOT_TEST_BIN'), 'GODOT_TEST_BIN not set')
class SceneContractTests(unittest.TestCase):
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
