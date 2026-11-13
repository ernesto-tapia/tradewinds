"""Install official pinned Godot engine and Windows export templates.

Writes .tools/ and the current user's Godot export template directory.
Release assets are verified against the SHA-512 manifest from the release.
"""
import hashlib
import io
import os
from pathlib import Path
import urllib.request
import zipfile

VERSION = '4.5.1-stable'
BASE = f'https://github.com/godotengine/godot/releases/download/{VERSION}/'


def download(name):
    print(f'Downloading {name}', flush=True)
    with urllib.request.urlopen(BASE + name, timeout=300) as response:
        data = response.read()
    with urllib.request.urlopen(BASE + 'SHA512-SUMS.txt', timeout=60) as response:
        lines = response.read().decode().splitlines()
    checksum = next(line.split()[0] for line in lines if line.split()[-1].lstrip('*') == name)
    if hashlib.sha512(data).hexdigest() != checksum:
        raise RuntimeError('Godot checksum mismatch: ' + name)
    return data


def main():
    root = Path(__file__).resolve().parents[1]
    engine = root / '.tools/godot'
    engine.mkdir(parents=True, exist_ok=True)
    executable = engine / f'Godot_v{VERSION}_win64_console.exe'
    if not executable.exists():
        with zipfile.ZipFile(io.BytesIO(download(f'Godot_v{VERSION}_win64.exe.zip'))) as archive:
            for info in archive.infolist():
                if '/' not in info.filename and info.filename.endswith('.exe'):
                    (engine / info.filename).write_bytes(archive.read(info))
    templates = Path(os.environ['APPDATA']) / 'Godot/export_templates/4.5.1.stable'
    templates.mkdir(parents=True, exist_ok=True)
    names = ['windows_debug_x86_64.exe', 'windows_release_x86_64.exe']
    if not all((templates / name).exists() for name in names):
        with zipfile.ZipFile(io.BytesIO(download(f'Godot_v{VERSION}_export_templates.tpz'))) as archive:
            for name in names:
                (templates / name).write_bytes(archive.read('templates/' + name))
    print(f'Set GODOT_BIN to {executable}')


if __name__ == '__main__':
    main()
