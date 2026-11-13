"""Run deterministic project validation and export, rejecting logged errors."""
import os
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
godot = os.environ.get('GODOT_BIN', 'godot')
(root / 'build').mkdir(exist_ok=True)
for args in [
    ['--editor', '--import', '--quit'],
    ['--script', str(root / 'scripts/check_scene.gd')],
    ['--quit-after', '120'],
    ['--export-release', 'Windows Desktop', '../build/CaribbeanTradewinds.exe'],
]:
    result = subprocess.run([godot, '--headless', '--path', 'game', *args], cwd=root,
                            capture_output=True, text=True, timeout=180)
    output = result.stdout + result.stderr
    print(output)
    if result.returncode or any(s in output for s in ('ERROR:', 'SCRIPT ERROR:', 'Parse Error:')):
        raise SystemExit('Godot validation failed')
exe = root / 'build/CaribbeanTradewinds.exe'
if not exe.is_file():
    raise SystemExit('Exported executable is missing')
result = subprocess.run([str(exe), '--headless', '--quit-after', '120'], cwd=exe.parent,
                        capture_output=True, text=True, timeout=60)
print(result.stdout + result.stderr)
if result.returncode or 'ERROR:' in result.stdout + result.stderr:
    raise SystemExit('Exported executable smoke test failed')
