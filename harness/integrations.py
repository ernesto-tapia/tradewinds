import base64
import json
import os
from pathlib import Path
from urllib.parse import urlencode

from .core import REPORT_SCHEMA, command, report, request


def pages(url, headers, key=None):
    values, page = [], 1
    while True:
        data = request(url + ('&' if '?' in url else '?') + f"per_page=100&page={page}", headers=headers)
        batch = data[key] if key else data
        values.extend(batch)
        if len(batch) < 100:
            return values
        page += 1


class GitHub:
    def __init__(self, config):
        self.repo = config["github"]["repository"]
        self.base = config["github"]["base"]
        token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
        if not token:
            raise RuntimeError("Set GITHUB_TOKEN in this terminal")
        self.headers = {"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json",
                        "X-GitHub-Api-Version": "2022-11-28"}
        self.url = f"https://api.github.com/repos/{self.repo}"

    def get(self, path):
        return request(self.url + path, headers=self.headers)

    def pr(self, number):
        return self.get(f"/pulls/{number}")

    def ensure_pr(self, branch, title, body):
        query = urlencode({"state": "all", "head": self.repo.split('/')[0] + ':' + branch, "base": self.base})
        existing = self.get('/pulls?' + query)
        if existing:
            return existing[0]
        return request(self.url + '/pulls', {"title": title, "body": body, "head": branch, "base": self.base}, self.headers)

    def comment(self, number, marker, text):
        tag = f"<!-- tradewinds:{marker} -->"
        comments = pages(self.url + f"/issues/{number}/comments", self.headers)
        existing = next((c for c in comments if tag in c["body"]), None)
        if existing:
            return existing
        return request(self.url + f"/issues/{number}/comments", {"body": tag + '\n' + text}, self.headers)

    def checks_pass(self, sha):
        runs = pages(self.url + f"/commits/{sha}/check-runs?filter=latest", self.headers, 'check_runs')
        status = self.get(f"/commits/{sha}/status")
        if not runs and not status.get('statuses'):
            return False
        return all(r['status'] == 'completed' and r['conclusion'] in ('success', 'neutral', 'skipped') for r in runs) and (
            not status.get('statuses') or status['state'] == 'success')


def adf(text):
    return {"version": 1, "type": "doc", "content": [{"type": "paragraph", "content": [
        {"type": "text", "text": text}]}]}


class Jira:
    def __init__(self, config):
        email, token = os.environ.get('JIRA_EMAIL'), os.environ.get('JIRA_API_TOKEN')
        if not email or not token:
            raise RuntimeError('Set JIRA_EMAIL and JIRA_API_TOKEN in this terminal')
        self.url = config['jira']['url'].rstrip('/')
        self.stages = config['jira']['stages']
        self.headers = {'Authorization': 'Basic ' + base64.b64encode(f'{email}:{token}'.encode()).decode()}

    def get(self, path):
        return request(self.url + '/rest/api/3' + path, headers=self.headers)

    def issue(self, key):
        return self.get(f'/issue/{key}?fields=summary,description,status,issuetype,parent,labels')

    def search(self, jql):
        issues, token = [], None
        while True:
            query = {'jql': jql, 'maxResults': 100, 'fields': 'summary,status,issuetype,parent'}
            if token:
                query['nextPageToken'] = token
            result = self.get('/search/jql?' + urlencode(query))
            issues.extend(result['issues'])
            token = result.get('nextPageToken')
            if not token:
                return issues

    def transition(self, key, stage):
        issue = self.issue(key)
        if stage == 'done' and issue['fields']['issuetype'].get('hierarchyLevel', 0) > 0:
            children = self.search(f'parent = "{key}"')
            if not children or any(c['fields']['status']['statusCategory']['key'] != 'done' for c in children):
                raise RuntimeError('Epic children are not all complete')
        desired = self.stages[stage]
        if issue['fields']['status']['name'] in desired or (
                stage == 'done' and issue['fields']['status']['statusCategory']['key'] == 'done'):
            return
        transitions = self.get(f'/issue/{key}/transitions')['transitions']
        selected = next((t for t in transitions if t['to']['name'] in desired), None)
        if selected is None:
            raise RuntimeError(f"No configured Jira transition for {stage}; available: {[t['to']['name'] for t in transitions]}")
        request(self.url + f'/rest/api/3/issue/{key}/transitions', {'transition': {'id': selected['id']}}, self.headers)

    def comment(self, key, marker, text):
        start = 0
        tag = f'[tradewinds:{marker}]'
        while True:
            result = self.get(f'/issue/{key}/comment?startAt={start}&maxResults=100')
            if any(tag in json.dumps(c['body']) for c in result['comments']):
                return
            start += len(result['comments'])
            if start >= result['total']:
                break
        request(self.url + f'/rest/api/3/issue/{key}/comment', {'body': adf(tag + '\n' + text)}, self.headers)


class Codex:
    def __init__(self, config, prompts, artifacts):
        self.config, self.prompts, self.artifacts = config, Path(prompts), Path(artifacts)

    def review(self, worktree, task, sha, mode, evidence):
        folder = self.artifacts / f'{mode}-{sha}'
        folder.mkdir(parents=True, exist_ok=True)
        schema = folder / 'schema.json'
        output = folder / 'report.json'
        schema.write_text(json.dumps(REPORT_SCHEMA), encoding='utf-8')
        if output.exists():
            output.unlink()
        diff = command(['git', 'diff', 'origin/' + self.config['github']['base'] + '...HEAD'] if mode == 'review' else
                       ['git', 'diff', sha + '^1', sha], worktree)
        prompt = (self.prompts / 'reviewer.md').read_text() + '\n' + json.dumps({
            'mode': mode, 'task': task, 'commit': sha, 'evidence': evidence,
            'diff': diff,
            'instruction': 'Inspect git diff origin/main...HEAD for PR review. For merged assessment inspect the supplied merged changes against acceptance criteria. Return only the schema.'})
        # stdin avoids shell quoting and command-line length limits. Integration
        # credentials are excluded; Codex uses its own existing login.
        import subprocess
        from .core import clean_env
        result = subprocess.run([self.config['codex'], 'exec', '--sandbox', 'read-only', '--ephemeral', '--ignore-user-config',
                                 '--output-schema', str(schema), '--output-last-message', str(output), '-'],
                                input=prompt, cwd=worktree, env=clean_env(), capture_output=True,
                                text=True, encoding='utf-8', errors='replace',
                                timeout=self.config['limits']['model_seconds'])
        (folder / 'transcript.txt').write_text(result.stdout + result.stderr, encoding='utf-8')
        if result.returncode:
            raise RuntimeError(f'Codex failed; inspect {folder / "transcript.txt"}')
        return report(json.loads(output.read_text(encoding='utf-8')))
