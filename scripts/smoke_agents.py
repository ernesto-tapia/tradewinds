"""Opt-in live Ollama tool-loop test; creates no commits, PRs or Jira updates."""
import json
from pathlib import Path
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import yaml
from harness.core import Ollama, Tools


def main():
    root = Path(__file__).resolve().parents[1]
    cfg = yaml.safe_load((root / 'harness.yaml').read_text())
    cfg['permissions'] = {'developer': ['game/'], 'qa': ['tests/game/']}
    cfg['commands'] = {'validate': [sys.executable, '-c', "from pathlib import Path; assert Path('game/probe.txt').read_text() == 'tradewinds'"]}
    cfg['limits']['turns'] = 8
    cfg.pop('export_artifact', None)
    artifacts = root / '.runs'
    artifacts.mkdir(exist_ok=True)
    def log(value):
        with (artifacts / 'model-smoke.jsonl').open('a', encoding='utf-8') as stream:
            stream.write(json.dumps(value) + '\n')
    with tempfile.TemporaryDirectory(dir=artifacts) as folder:
        worktree = Path(folder)
        prompts = worktree / 'prompts'
        prompts.mkdir()
        (prompts / 'developer.md').write_text('Use write_file to create game/probe.txt containing exactly tradewinds (no newline). Run validate. Then finish. Do not just describe the change. Report passed, summary, evidence, gaps.')
        (prompts / 'qa.md').write_text('Independently read game/probe.txt and run validate. Do not edit implementation. Then finish. Report passed, summary, evidence, gaps.')
        ollama = Ollama(cfg, prompts)
        for role in ('developer', 'qa'):
            print('Testing ' + role, flush=True)
            task = 'Write game/probe.txt containing exactly tradewinds and run validate.' if role == 'developer' else 'Read the existing game/probe.txt and run validate. Verify it contains exactly tradewinds. Do not write or change files.'
            value = ollama.run(role, {'task': task}, Tools(worktree, role, cfg, log))
            print(json.dumps(value), flush=True)
            if not value['passed'] or not (worktree / 'game/probe.txt').is_file():
                raise SystemExit('Live agent smoke test failed; inspect .runs/model-smoke.jsonl')


if __name__ == '__main__':
    main()
