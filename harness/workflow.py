import json
from pathlib import Path
import re
import time
import uuid

from .core import Tools, command


class Workflow:
    def __init__(self, root, config, store, github, jira, ollama, codex):
        self.root, self.config, self.store = Path(root).resolve(), config, store
        self.github, self.jira, self.ollama, self.codex = github, jira, ollama, codex

    def git(self, *args, cwd=None):
        return command(['git', *args], cwd or self.root).strip()

    def start(self, key):
        if not re.fullmatch(r'[A-Z][A-Z0-9_]*-\d+', key):
            raise ValueError('Invalid issue key')
        existing = next((r for r in self.store.all() if r['key'] == key and r['stage'] not in ('done', 'closed')), None)
        if existing:
            return self.advance(existing)
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

    def agent(self, run, role):
        log = lambda value: self.store.log(run['id'], role, value)
        tools = Tools(run['worktree'], role, self.config, log)
        return self.ollama.run(role, {'issue': run['task'], 'feedback': run['feedback'],
                                     'files': tools.call('list_files', {})}, tools)

    def commit(self, run):
        cwd = run['worktree']
        # Agents cannot modify the harness, CI, credentials or their own policy.
        paths = sorted(set(self.config['permissions']['developer'] + self.config['permissions']['qa']))
        for path in paths:
            if (Path(cwd) / path).exists():
                self.git('add', '--', path, cwd=cwd)
        if self.git('diff', '--cached', '--name-only', cwd=cwd):
            self.git('commit', '-m', f"{run['key']}: implement and validate story", cwd=cwd)
        return self.git('rev-parse', 'HEAD', cwd=cwd)

    def advance(self, run):
        try:
            while True:
                stage, cwd = run['stage'], run['worktree']
                print(f"{run['id']} {run['key']}: {stage}", flush=True)
                if stage == 'prepare':
                    self.git('fetch', 'origin', self.config['github']['base'])
                    if not Path(cwd).exists():
                        Path(cwd).parent.mkdir(parents=True, exist_ok=True)
                        branches = self.git('branch', '--list', run['branch'])
                        args = ['worktree', 'add']
                        args += [cwd, run['branch']] if branches else ['-b', run['branch'], cwd, 'origin/' + self.config['github']['base']]
                        self.git(*args)
                    self.jira.transition(run['key'], 'developing')
                    run['stage'] = 'develop'
                elif stage == 'develop':
                    run['developer'] = self.agent(run, 'developer')
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
                    body = f"## {run['key']}\n{self.config['jira']['url']}/browse/{run['key']}\n\n" + json.dumps(run['qa'], indent=2)
                    pr = self.github.ensure_pr(run['branch'], f"{run['key']}: {run['task']['fields']['summary']}", body)
                    run['pr'], run['pr_url'] = pr['number'], pr['html_url']
                    self.jira.comment(run['key'], run['id'] + '-pr', 'Implementation ready for review: ' + run['pr_url'])
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
                        if pr['head']['sha'] != run.get('review_sha') or pr['head']['sha'] != run.get('qa_sha') or not run.get('review', {}).get('passed'):
                            run['merge_gap'] = 'Merged head lacks matching QA and passing Codex review'
                        if not self.github.checks_pass(pr['head']['sha']):
                            run['merge_gap'] = 'Merged head checks are missing, pending, or unsuccessful'
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
                    self.git('fetch', 'origin', self.config['github']['base'])
                    self.git('checkout', '--detach', run['merge_sha'], cwd=cwd)
                    evidence = {'qa': run.get('qa'), 'review': run.get('review'),
                                'merge_sha': run['merge_sha'], 'visual_observation': run.get('visual_observation'),
                                'merge_gap': run.get('merge_gap'), 'feature_sha': run.get('qa_sha')}
                    value = self.codex.review(cwd, run['task'], run['merge_sha'], 'assessment', evidence)
                    if run['key'] == 'KAN-8' and not run.get('visual_observation'):
                        value = {**value, 'passed': False, 'gaps': value.get('gaps', []) + ['Record a human observation of the exported desktop build with resume --visual-observation.']}
                    run['assessment'] = value
                    run['stage'] = 'complete' if value['passed'] and not run.get('merge_gap') else 'acceptance_gap'
                elif stage == 'complete':
                    pr = self.github.pr(run['pr'])
                    if not pr['merged'] or pr['merge_commit_sha'] != run['merge_sha']:
                        raise RuntimeError('Merge evidence changed; refusing Jira completion')
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
        self.git('checkout', run['branch'], cwd=cwd)
        self.git('merge', '--ff-only', sha, cwd=cwd)
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
