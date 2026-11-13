import json
from pathlib import Path
import re
import time
import uuid

from .core import Tools, command, git_command


def plain_text(value):
    if isinstance(value, str):
        return value
    if not isinstance(value, dict):
        return ''
    if value.get('type') == 'text':
        return value.get('text', '')
    if value.get('type') == 'hardBreak':
        return '\n'
    text = ''.join(plain_text(child) for child in value.get('content', []))
    return text + ('\n' if value.get('type') in ('paragraph', 'heading', 'listItem') else '')


class Workflow:
    def __init__(self, root, config, store, github, jira, ollama, codex):
        self.root, self.config, self.store = Path(root).resolve(), config, store
        self.github, self.jira, self.ollama, self.codex = github, jira, ollama, codex

    def git(self, *args, cwd=None):
        directory = Path(cwd or self.root).resolve()
        if not directory.is_relative_to(self.root):
            raise PermissionError('Git worktree must remain within the selected workspace')
        return git_command(list(args), directory).strip()

    def start(self, key):
        if not re.fullmatch(r'[A-Z][A-Z0-9_]*-\d+', key):
            raise ValueError('Invalid issue key')
        existing = next((r for r in self.store.all() if r['key'] == key and r['stage'] not in ('done', 'closed')), None)
        if existing:
            return self.advance(existing)
        if any(r['key'] == key for r in self.store.all()):
            raise RuntimeError('This story already has a closed or completed run; inspect its PR and saved state before creating replacement work')
        if any(r['stage'] not in ('done', 'closed', 'exhausted') for r in self.store.all()):
            raise RuntimeError('Another story is active; resume or finish it first')
        task = self.jira.issue(key)
        if task['fields']['issuetype'].get('hierarchyLevel', 0) != 0:
            raise ValueError('Run a story, not an epic or subtask')
        slug = re.sub(r'[^a-z0-9]+', '-', task['fields']['summary'].lower()).strip('-')[:60]
        run = {'id': uuid.uuid4().hex[:12], 'key': key, 'task': task, 'stage': 'prepare',
               'branch': f'codex/{key.lower()}-{slug}', 'repairs': 0, 'feedback': [], 'pr': None}
        run['worktree'] = str(self.store.root / 'worktrees' / run['id'])
        self.store.save(run)
        return self.advance(run)

    def repair(self, run, feedback):
        run['feedback'].append(feedback)
        if run['repairs'] >= self.config['limits']['repairs']:
            run['stage'] = 'exhausted'
        else:
            run['repairs'] += 1
            run['stage'] = 'develop'
        self.store.save(run)

    def retry(self, run):
        if run['stage'] != 'exhausted':
            raise ValueError('--retry applies only to an exhausted run')
        run.setdefault('retry_history', []).append({
            'repairs': run['repairs'], 'feedback': run['feedback'],
            'developer': run.get('developer'), 'qa': run.get('qa'), 'review': run.get('review'), 'time': time.time()})
        run.update(stage='develop', repairs=0, feedback=[])
        for key in ('developer', 'qa', 'review', 'qa_sha', 'review_sha'):
            run.pop(key, None)
        run.pop('error', None)
        self.store.save(run)

    def merge_gap(self, run, pr):
        if not pr.get('merged'):
            return 'PR is not merged'
        if pr['head']['sha'] != run.get('qa_sha') or pr['head']['sha'] != run.get('review_sha') or not run.get('review', {}).get('passed'):
            return 'Merged head lacks matching QA and passing Codex review'
        if not self.github.checks_pass(pr['head']['sha']):
            return 'Merged head checks are missing, pending, or unsuccessful'
        return None

    def agent(self, run, role):
        def log(value):
            self.store.log(run['id'], role, value)
            if 'tool' in value:
                failed = isinstance(value['result'], dict) and 'error' in value['result']
                print(f"  {role}: {value['tool']} {'failed' if failed else 'ok'}", flush=True)
            elif 'check' in value:
                print(f"  {role}: {value['check']} passed", flush=True)
        tools = Tools(run['worktree'], role, self.config, log)
        fields = run['task']['fields']
        files = tools.call('list_files', {})
        existing, remaining = {}, 8000
        for name in files:
            if not name.startswith(('game/', 'docs/game/', 'tests/game/')) or Path(name).suffix not in ('.gd', '.godot', '.tscn', '.cfg', '.md'):
                continue
            content = tools.call('read_file', {'path': name})
            if len(content) <= min(4000, remaining):
                existing[name] = content
                remaining -= len(content)
        task = {'issue': {'key': run['key'], 'summary': fields['summary'],
                          'description': plain_text(fields.get('description')).strip()},
                'feedback': [{k: f[k] for k in ('summary', 'gaps') if k in f} for f in run['feedback'][-1:]],
                'files': files, 'existing_files': existing, 'configured_checks': list(self.config['commands']),
                'asset_policy': 'Use only simple rectangles with text labels inside. No generated images, sprites, external art, complex shapes, models or audio.'}
        return self.ollama.run(role, task, tools)

    def commit(self, run):
        cwd = run['worktree']
        # Agents cannot modify the harness, CI, credentials or their own policy.
        paths = sorted(set(self.config['permissions']['developer'] + self.config['permissions']['qa']))
        for path in paths:
            if (Path(cwd) / path).exists() or self.git('ls-files', '--', path, cwd=cwd):
                self.git('add', '-A', '--', path, cwd=cwd)
        if self.git('diff', '--cached', '--name-only', cwd=cwd):
            self.git('commit', '-m', f"{run['key']}: implement and validate story", cwd=cwd)
        return self.git('rev-parse', 'HEAD', cwd=cwd)

    def advance(self, run, stop_before=None):
        try:
            while True:
                stage, cwd = run['stage'], run['worktree']
                print(f"{run['id']} {run['key']}: {stage}", flush=True)
                if stage == stop_before:
                    self.store.save(run)
                    return run
                if stage == 'prepare':
                    self.git('fetch', 'origin', self.config['github']['base'])
                    if not Path(cwd).exists():
                        Path(cwd).parent.mkdir(parents=True, exist_ok=True)
                        branches = self.git('branch', '--list', run['branch'])
                        args = ['worktree', 'add']
                        args += [cwd, run['branch']] if branches else ['-b', run['branch'], cwd, 'origin/' + self.config['github']['base']]
                        self.git(*args)
                    self.jira.transition(run['key'], 'developing')
                    run.setdefault('base_sha', self.git('rev-parse', 'HEAD', cwd=cwd))
                    run['stage'] = 'develop'
                elif stage == 'develop':
                    if self.jira is not None:
                        self.jira.transition(run['key'], 'developing')
                    run['developer'] = self.agent(run, 'developer')
                    if not run['developer']['passed']:
                        self.repair(run, run['developer'])
                        continue
                    run['stage'] = 'qa'
                elif stage == 'qa':
                    value = self.agent(run, 'qa')
                    run['qa'] = value
                    if not value['passed']:
                        self.repair(run, value)
                        continue
                    run['sha'] = self.commit(run)
                    run['qa_sha'] = run['sha']
                    run['stage'] = 'publish'
                elif stage == 'publish':
                    if self.git('rev-parse', 'HEAD', cwd=cwd) != run['qa_sha'] or self.git('status', '--porcelain', '--untracked-files=normal', cwd=cwd):
                        run['stage'] = 'qa'
                        self.store.save(run)
                        continue
                    self.git('push', '--set-upstream', 'origin', run['branch'], cwd=cwd)
                    body = (f"## {run['key']}\n{self.config['jira']['url']}/browse/{run['key']}\n\n"
                            + '## Implementation\n' + run.get('developer', {}).get('summary', '')
                            + '\n\n## Acceptance evidence and tests\n```json\n' + json.dumps(run['qa'], indent=2)
                            + '\n```\n\n## Review and limitations\nCodex review follows PR creation. '
                            + 'Human merge is required; local headless checks do not establish visual quality. '
                            + 'Logs remain in the local .runs directory; CI retains the Windows build artifact.')
                    pr = self.github.ensure_pr(run['branch'], f"{run['key']}: {run['task']['fields']['summary']}", body)
                    run['pr'], run['pr_url'] = pr['number'], pr['html_url']
                    self.jira.comment(run['key'], run['id'] + '-pr', 'Implementation ready for review: ' + run['pr_url'])
                    self.jira.transition(run['key'], 'reviewing')
                    run['stage'] = 'review'
                elif stage == 'review':
                    pr = self.github.pr(run['pr'])
                    if pr['merged'] or pr['state'] == 'closed':
                        run['stage'] = 'waiting_merge'
                        self.store.save(run)
                        continue
                    sha = pr['head']['sha']
                    if sha != run.get('qa_sha'):
                        self.sync_head(run, sha)
                        run['stage'] = 'qa'
                        self.store.save(run)
                        continue
                    if self.git('rev-parse', 'HEAD', cwd=cwd) != sha or self.git('status', '--porcelain', cwd=cwd):
                        raise RuntimeError('Local worktree differs from the PR head; refusing stale review')
                    value = self.codex.review(cwd, run['task'], sha, 'review', run['qa'])
                    if self.github.pr(run['pr'])['head']['sha'] != sha:
                        continue
                    if self.git('rev-parse', 'HEAD', cwd=cwd) != sha or self.git('status', '--porcelain', cwd=cwd):
                        raise RuntimeError('Worktree changed during Codex review; report was not accepted')
                    self.github.comment(run['pr'], f"{run['id']}-review-{sha}", 'Codex review of `' + sha + '`\n```json\n' + json.dumps(value, indent=2) + '\n```')
                    run['review'], run['review_sha'] = value, sha
                    if not value['passed']:
                        self.repair(run, value)
                        continue
                    run['stage'] = 'waiting_merge'
                elif stage == 'waiting_merge':
                    pr = self.github.pr(run['pr'])
                    if pr['merged']:
                        run.pop('merge_gap', None)
                        gap = self.merge_gap(run, pr)
                        if gap:
                            run['merge_gap'] = gap
                        run['merge_sha'] = pr['merge_commit_sha']
                        run['stage'] = 'assess'
                    elif pr['state'] == 'closed':
                        run['stage'] = 'closed'
                    elif pr['head']['sha'] != run.get('review_sha'):
                        self.sync_head(run, pr['head']['sha'])
                        run['stage'] = 'qa'
                    else:
                        run['checks_pass'] = self.github.checks_pass(pr['head']['sha'])
                        self.store.save(run)
                        return run
                elif stage == 'assess':
                    pr = self.github.pr(run['pr'])
                    if not pr['merged'] or pr['merge_commit_sha'] != run['merge_sha']:
                        raise RuntimeError('Cannot assess an unconfirmed merge')
                    run.pop('merge_gap', None)
                    gap = self.merge_gap(run, pr)
                    if gap:
                        run['merge_gap'] = gap
                    self.git('fetch', 'origin', self.config['github']['base'])
                    if self.git('status', '--porcelain', cwd=cwd):
                        raise RuntimeError('Assessment worktree must be clean')
                    self.git('checkout', '--detach', run['merge_sha'], cwd=cwd)
                    evidence = {'qa': run.get('qa'), 'review': run.get('review'),
                                'merge_sha': run['merge_sha'], 'visual_observation': run.get('visual_observation'),
                                'merge_gap': run.get('merge_gap'), 'feature_sha': run.get('qa_sha')}
                    evidence['base_sha'] = run.get('base_sha')
                    value = self.codex.review(cwd, run['task'], run['merge_sha'], 'assessment', evidence)
                    if self.git('rev-parse', 'HEAD', cwd=cwd) != run['merge_sha'] or self.git('status', '--porcelain', cwd=cwd):
                        raise RuntimeError('Worktree changed during assessment; report was not accepted')
                    if run['key'] == 'KAN-8' and not run.get('visual_observation'):
                        value = {**value, 'passed': False, 'gaps': value.get('gaps', []) + ['Record a human observation of the exported desktop build with resume --visual-observation.']}
                    run['assessment'] = value
                    run['stage'] = 'complete' if value['passed'] and not run.get('merge_gap') else 'acceptance_gap'
                elif stage == 'complete':
                    pr = self.github.pr(run['pr'])
                    if not pr['merged'] or pr['merge_commit_sha'] != run['merge_sha']:
                        raise RuntimeError('Merge evidence changed; refusing Jira completion')
                    if self.merge_gap(run, pr) or not run['assessment']['passed'] or (run['key'] == 'KAN-8' and not run.get('visual_observation')):
                        raise RuntimeError('Completion evidence is no longer valid; resolve checks or acceptance gaps before resuming')
                    # External operations are reconciled from their authoritative
                    # systems, so a crash after HTTP success is safe to retry.
                    self.jira.comment(run['key'], run['id'] + '-merged', 'Merged: ' + run['pr_url'] + '\n' + json.dumps(run['assessment']))
                    self.jira.transition(run['key'], 'done')
                    run['stage'] = 'done'
                elif stage == 'acceptance_gap':
                    self.jira.comment(run['key'], run['id'] + '-gap', 'Merged but acceptance gaps remain: ' + json.dumps({
                        'assessment': run['assessment'], 'merge_gap': run.get('merge_gap')}))
                    self.store.save(run)
                    return run
                else:
                    self.store.save(run)
                    return run
                run.pop('error', None)
                self.store.save(run)
        except Exception as error:
            run['error'] = str(error)
            self.store.save(run)
            raise

    def sync_head(self, run, sha):
        cwd = run['worktree']
        if self.git('status', '--porcelain', cwd=cwd):
            raise RuntimeError('Worktree has local changes; resolve them before syncing remote head')
        self.git('fetch', 'origin', run['branch'])
        old_sha = self.git('rev-parse', 'HEAD', cwd=cwd)
        self.git('update-ref', f"refs/tradewinds/backups/{run['id']}/{old_sha}", old_sha)
        self.git('checkout', '-B', run['branch'], sha, cwd=cwd)
        run.pop('review_sha', None)
        run.pop('qa_sha', None)

    def watch(self, once=False):
        while True:
            for run in self.store.all():
                if run['stage'] in ('waiting_merge', 'review', 'assess', 'complete'):
                    try:
                        self.advance(run)
                    except Exception as error:
                        print(f"{run['id']}: {error}", flush=True)
            if once:
                return
            time.sleep(self.config['limits']['poll_seconds'])
