import argparse
import json
import os
from pathlib import Path
import shutil
import sys

import yaml

from .core import Store, command, request
from .integrations import Codex, GitHub, Jira
from .core import Ollama
from .workflow import Workflow


def resolve_codex(configured):
    override = os.environ.get('CODEX_BIN')
    if override:
        return override
    if configured != 'codex':
        return configured
    on_path = shutil.which('codex')
    if on_path:
        return on_path
    # Desktop installs are versioned and its private PATH is not inherited by
    # independently opened PowerShell terminals. Discover rather than pin a hash.
    local = os.environ.get('LOCALAPPDATA')
    profile = os.environ.get('USERPROFILE') or os.environ.get('HOME')
    roots = ([Path(local)] if local else []) + ([Path(profile) / 'AppData/Local'] if profile else [])
    for appdata in roots:
        folder = appdata / 'OpenAI/Codex/bin'
        candidates = [p for p in folder.glob('*/codex.exe') if p.is_file()]
        direct = folder / 'codex.exe'
        if direct.is_file():
            candidates.append(direct)
        if candidates:
            return str(max(candidates, key=lambda p: p.stat().st_mtime))
    return configured


def doctor(root, cfg):
    checks = {}
    def check(name, function):
        try:
            value = function()
            checks[name] = {'ok': True, 'detail': value}
        except Exception as error:
            checks[name] = {'ok': False, 'detail': str(error)}
    check('git', lambda: command(['git', '--version'], root).strip())
    check('remote', lambda: command(['git', 'ls-remote', 'origin'], root).strip())
    check('codex_login', lambda: command([cfg['codex'], 'login', 'status'], root).strip())
    def godot():
        version = command([cfg['godot'], '--version'], root).strip()
        if not version.startswith(cfg['godot_version'] + '.'):
            raise RuntimeError(f"Expected {cfg['godot_version']}, got {version}")
        return version
    check('godot', godot)
    def templates():
        base = Path(os.environ.get('APPDATA', str(Path.home() / '.local/share'))) / 'Godot/export_templates'
        folder = base / (cfg['godot_version'] + '.stable')
        if not all((folder / f'windows_{kind}_x86_64.exe').exists() for kind in ('debug', 'release')):
            raise RuntimeError(f'Install matching export templates in {folder}')
        return str(folder)
    check('export_templates', templates)
    def models():
        data = request(cfg['ollama']['url'] + '/api/tags')
        names = {m['name'] for m in data['models']}
        required = {cfg['ollama']['developer'], cfg['ollama']['qa']}
        if not required <= names:
            raise RuntimeError('Missing models: ' + ', '.join(required - names))
        return sorted(names)
    check('ollama', models)
    check('github', lambda: GitHub(cfg).get('')['full_name'])
    check('jira', lambda: Jira(cfg).get('/myself')['displayName'])
    def commands():
        for name, argv in cfg['commands'].items():
            if not argv or not all(isinstance(a, str) for a in argv):
                raise ValueError(f'Invalid command {name}')
            executable = argv[0].replace('{godot}', cfg['godot'])
            if not shutil.which(executable):
                raise RuntimeError(f'Command executable missing: {executable}')
        return sorted(cfg['commands'])
    check('configured_commands', commands)
    def limits():
        for name in ('turns', 'report_attempts', 'command_seconds', 'model_seconds', 'poll_seconds'):
            value = cfg['limits'].get(name, 2 if name == 'report_attempts' else None)
            if type(value) is not int or value <= 0:
                raise ValueError(f'limits.{name} must be a positive integer')
        if type(cfg['limits']['repairs']) is not int or cfg['limits']['repairs'] < 0:
            raise ValueError('limits.repairs must be a nonnegative integer')
        return cfg['limits']
    check('limits', limits)
    print(json.dumps(checks, indent=2))
    return 0 if all(c['ok'] for c in checks.values()) else 1


def main():
    parser = argparse.ArgumentParser(description='Sequential Ollama development and QA with Codex review')
    parser.add_argument('--config', default='harness.yaml')
    subs = parser.add_subparsers(dest='command', required=True)
    for name in ('doctor', 'backlog', 'status'):
        subs.add_parser(name)
    subs.add_parser('run').add_argument('issue')
    resume = subs.add_parser('resume')
    resume.add_argument('run_id')
    resume.add_argument('--visual-observation', help='Your factual observation after launching the exported build')
    subs.add_parser('watch').add_argument('--once', action='store_true')
    args = parser.parse_args()
    config_path = Path(args.config).resolve()
    root = config_path.parent
    cfg = yaml.safe_load(config_path.read_text(encoding='utf-8'))
    cfg['godot'] = os.environ.get('GODOT_BIN', cfg['godot'])
    local_godot = root / '.tools/godot/Godot_v4.5.1-stable_win64_console.exe'
    if cfg['godot'] == 'godot' and local_godot.exists():
        cfg['godot'] = str(local_godot)
    cfg['codex'] = resolve_codex(cfg['codex'])
    try:
        if args.command == 'doctor':
            return doctor(root, cfg)
        store = Store(root / '.runs')
        if args.command == 'status':
            print(json.dumps([{k: r.get(k) for k in ('id', 'key', 'stage', 'repairs', 'pr_url', 'checks_pass', 'error')} for r in store.all()], indent=2))
            return 0
        if args.command == 'backlog':
            print(json.dumps(Jira(cfg).search(cfg['jira']['jql']), indent=2))
            return 0
        with store.lock():
            github, jira = GitHub(cfg), Jira(cfg)
            workflow = Workflow(root, cfg, store, github, jira, Ollama(cfg, root / 'prompts'),
                                Codex(cfg, root / 'prompts', store.root / 'codex'))
            if args.command == 'run':
                if doctor(root, cfg):
                    raise RuntimeError('Resolve doctor failures before starting a run')
                run = workflow.start(args.issue)
            elif args.command == 'resume':
                run = store.get(args.run_id)
                if run['stage'] == 'acceptance_gap':
                    run['stage'] = 'assess'
                if args.visual_observation:
                    run['visual_observation'] = args.visual_observation
                    if run['stage'] == 'acceptance_gap':
                        run['stage'] = 'assess'
                    store.save(run)
                if run['stage'] == 'exhausted' and run['repairs'] < cfg['limits']['repairs']:
                    run['stage'] = 'develop'
                run = workflow.advance(run)
            else:
                workflow.watch(args.once)
                return 0
            print(json.dumps(run, indent=2))
            return 1 if run['stage'] in ('exhausted', 'acceptance_gap') else 0
    except (Exception, KeyboardInterrupt) as error:
        print(f'{type(error).__name__}: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
