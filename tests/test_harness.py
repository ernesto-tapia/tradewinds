import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

from harness.core import Ollama, Store, Tools, command, report, action_call, git_command
from harness.workflow import Workflow, plain_text
from harness.integrations import GitHub, Jira, Codex
from harness.core import request
from harness.cli import resolve_codex


class HarnessTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.cfg = {'permissions': {'developer': ['game/'], 'qa': ['tests/game/']},
                    'commands': {'validate': ['fake']}, 'godot': 'godot',
                    'limits': {'repairs': 3, 'command_seconds': 1, 'turns': 2, 'model_seconds': 1},
                    'ollama': {'url': 'http://localhost', 'qa': 'model', 'context': 100},
                    'github': {'base': 'main'}, 'jira': {'url': 'https://example.test'}}

    def test_http_errors_preserve_status_without_exposing_secrets(self):
        import io
        import urllib.error
        for data, method in [(None, 'GET'), ({'example': True}, 'POST')]:
            error = urllib.error.HTTPError('https://example.test', 401, 'Unauthorized', {}, io.BytesIO(b'secret server body'))
            with patch('harness.core.urllib.request.urlopen', side_effect=error):
                with self.assertRaises(RuntimeError) as raised:
                    request('https://example.test/resource?secret=query', data, {'Authorization': 'Bearer private-token'})
            message = str(raised.exception)
            self.assertIn('HTTP 401 for ' + method, message)
            self.assertIn('Credentials were rejected', message)
            for secret in ('secret', 'private-token', 'Authorization'):
                self.assertNotIn(secret, message)

    def test_desktop_codex_discovery_without_path(self):
        import os
        older = self.root / 'OpenAI/Codex/bin/old/codex.exe'
        newer = self.root / 'OpenAI/Codex/bin/new/codex.exe'
        for path in (older, newer):
            path.parent.mkdir(parents=True)
            path.touch()
        os.utime(older, (1, 1))
        os.utime(newer, (2, 2))
        with patch.dict(os.environ, {'LOCALAPPDATA': str(self.root)}, clear=True), patch('harness.cli.shutil.which', return_value=None):
            self.assertEqual(resolve_codex('codex'), str(newer))
            self.assertEqual(resolve_codex('custom.exe'), 'custom.exe')
            with patch.dict(os.environ, {'CODEX_BIN': 'explicit.exe'}):
                self.assertEqual(resolve_codex('codex'), 'explicit.exe')

    def test_scoped_jira_route_preserves_site_url(self):
        import os
        config = {'jira': {'url': 'https://example.atlassian.net', 'stages': {}}}
        with patch.dict(os.environ, {'JIRA_EMAIL': 'test@example.test', 'JIRA_API_TOKEN': 'dummy',
                                    'JIRA_API_URL': 'https://api.atlassian.com/ex/jira/cloud-id'}):
            jira = Jira(config)
        with patch('harness.integrations.request', return_value={}) as req:
            jira.get('/myself')
        self.assertEqual(jira.url, config['jira']['url'])
        self.assertEqual(req.call_args.args[0], 'https://api.atlassian.com/ex/jira/cloud-id/rest/api/3/myself')

    def test_auth_diagnostics_do_not_disclose_credentials(self):
        import importlib.util
        import os
        spec = importlib.util.spec_from_file_location('check_auth', Path(__file__).resolve().parents[1] / 'scripts/check_auth.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        cfg = {'github': {'repository': 'owner/repo'}, 'jira': {'url': 'https://example.atlassian.net', 'cloud_id': 'cloud'}}
        with patch.dict(os.environ, {'GITHUB_TOKEN': 'private-github', 'JIRA_EMAIL': 'private@example.test', 'JIRA_API_TOKEN': 'private-jira'}), patch.object(module, 'probe', side_effect=[200, 404, 401, 200]):
            result = module.diagnose(cfg)
        text = json.dumps(result)
        for secret in ('private-github', 'private-jira', 'private@example.test'):
            self.assertNotIn(secret, text)
        self.assertEqual(result['jira_api_url_to_set'], 'https://api.atlassian.com/ex/jira/cloud')

    def test_codex_corrects_inconsistent_report_without_dropping_findings(self):
        prompts = self.root / 'prompts'
        prompts.mkdir()
        (prompts / 'reviewer.md').write_text('Review the supplied diff')
        self.cfg['codex'] = 'codex'
        reports = [dict(passed=True, summary='Clean PR review', evidence=[], gaps=['Human approval pending']),
                   dict(passed=True, summary='Clean PR review; human approval pending', evidence=['Human approval pending'], gaps=[])]
        def fake_process(args, **kwargs):
            output = Path(args[args.index('--output-last-message') + 1])
            output.write_text(json.dumps(reports.pop(0)), encoding='utf-8')
            return subprocess.CompletedProcess(args, 0, 'transcript', '')
        reviewer = Codex(self.cfg, prompts, self.root / 'artifacts')
        with patch('harness.integrations.git_command', return_value=''), patch('harness.integrations.run_process', side_effect=fake_process) as execute:
            value = reviewer.review(self.root, {}, 'abc', 'review', {})
        self.assertTrue(value['passed'])
        self.assertIn('Human approval pending', value['evidence'])
        self.assertEqual(execute.call_count, 2)
        self.assertTrue((self.root / 'artifacts/review-abc/invalid-report-1.json').exists())

    def test_role_permissions_and_traversal(self):
        tools = Tools(self.root, 'qa', self.cfg, lambda _: None)
        for path in ['../outside', 'game/main.gd', '.git/config', 'tests/game/../../../outside']:
            with self.subTest(path=path), self.assertRaises(PermissionError):
                tools.call('write_file', {'path': path, 'content': 'bad'})
        tools.call('write_file', {'path': 'tests/game/check.gd', 'content': 'test'})
        self.assertEqual((self.root / 'tests/game/check.gd').read_text(), 'test')
        with self.assertRaises(PermissionError):
            tools.call('shell', {'command': 'anything'})

    def test_invalid_reports(self):
        for value in [{}, {'passed': 'yes', 'summary': '', 'evidence': [], 'gaps': []},
                      {'passed': True, 'summary': '', 'evidence': [], 'gaps': ['missing build']}]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                report(value)

    def test_timeout(self):
        import sys
        with self.assertRaises(subprocess.TimeoutExpired):
            command([sys.executable, '-c', 'import time; time.sleep(2)'], self.root, timeout=0.05)

    def test_state_survives_restart_and_lock(self):
        store = Store(self.root)
        store.save({'id': 'run', 'stage': 'publish'})
        store.db.close()
        reopened = Store(self.root)
        self.addCleanup(reopened.db.close)
        self.assertEqual(reopened.get('run')['stage'], 'publish')
        import sqlite3
        with reopened.lock():
            with self.assertRaises(sqlite3.OperationalError):
                with reopened.lock():
                    pass

    def test_qa_cannot_claim_pass_without_checks(self):
        prompts = self.root / 'prompts'
        prompts.mkdir()
        (prompts / 'qa.md').write_text('qa')
        value = {'passed': True, 'summary': 'done', 'evidence': [], 'gaps': []}
        responses = [{'message': {'role': 'assistant', 'content': 'finished'}},
                     {'message': {'content': json.dumps(value)}}]
        with patch('harness.core.request', side_effect=responses):
            result = Ollama(self.cfg, prompts).run('qa', {}, Tools(self.root, 'qa', self.cfg, lambda _: None))
        self.assertFalse(result['passed'])

    def test_edit_invalidates_checks(self):
        tools = Tools(self.root, 'qa', self.cfg, lambda _: None)
        tools.checks['validate'] = True
        tools.call('write_file', {'path': 'tests/game/test.gd', 'content': 'test'})
        self.assertEqual(tools.checks, {})

    def test_identical_write_preserves_checks_across_windows_line_endings(self):
        (self.root / 'game').mkdir()
        (self.root / 'game/main.gd').write_bytes(b'extends Control\r\n')
        tools = Tools(self.root, 'developer', self.cfg, lambda _: None)
        tools.checks['validate'] = True
        result = tools.call('write_file', {'path': 'game/main.gd', 'content': 'extends Control\n'})
        self.assertTrue(result.startswith('unchanged'))
        self.assertEqual(tools.checks, {'validate': True})

    def test_export_receipt_contains_real_command_and_launch_results(self):
        self.cfg['commands'] = {'export': ['export-tool', '--release']}
        self.cfg['export_artifact'] = 'build/test.exe'
        (self.root / 'build').mkdir()
        (self.root / 'build/test.exe').touch()
        tools = Tools(self.root, 'qa', self.cfg, lambda _: None)
        with patch('harness.core.command', side_effect=['export completed', 'startup output']):
            tools.call('run_check', {'name': 'export'})
        receipt = tools.receipts['export']
        self.assertEqual(receipt['command'], ['export-tool', '--release'])
        self.assertEqual(receipt['exit_code'], 0)
        self.assertEqual(receipt['output'], 'export completed')
        launch = receipt['exported_executable_launch']
        self.assertEqual(launch['command'][0], str(self.root / 'build/test.exe'))
        self.assertEqual(launch['exit_code'], 0)
        self.assertEqual(launch['output'], 'startup output')
        with patch('harness.core.command', side_effect=RuntimeError('later failure')):
            with self.assertRaises(RuntimeError):
                tools.call('run_check', {'name': 'export'})
        self.assertNotIn('export', tools.receipts)

    def workflow(self):
        store = Store(self.root / 'state')
        self.addCleanup(store.db.close)
        workflow = Workflow(self.root, self.cfg, store, Mock(), Mock(), Mock(), Mock())
        workflow.verify_merged = Mock(return_value={'sha': 'merge', 'passed': True,
            'checks': {'validate': {'command': ['fixture-check'], 'cwd': str(self.root), 'exit_code': 0, 'output': 'verified fixture output'}}, 'errors': []})
        return workflow, store

    def run_data(self, stage):
        return {'id': 'run', 'key': 'KAN-8', 'stage': stage, 'worktree': str(self.root),
                'branch': 'codex/kan-8', 'feedback': [], 'repairs': 0, 'task': {},
                'pr': 1, 'pr_url': 'https://example/pr/1', 'qa_sha': 'abc', 'review_sha': 'abc',
                'review': {'passed': True}, 'qa': {'passed': True}}

    def test_qa_repair_and_exhaustion(self):
        workflow, store = self.workflow()
        run = self.run_data('qa')
        workflow.agent = Mock(return_value={'passed': False, 'gaps': ['bad']})
        result = workflow.advance(run)
        self.assertEqual(result['stage'], 'exhausted')
        self.assertEqual(result['repairs'], 3)
        self.assertEqual(workflow.agent.call_count, 4)  # QA failure + 3 failed developer repairs

    def test_closed_pr_never_completes(self):
        workflow, _ = self.workflow()
        workflow.github.pr.return_value = {'merged': False, 'state': 'closed'}
        result = workflow.advance(self.run_data('waiting_merge'))
        self.assertEqual(result['stage'], 'closed')
        workflow.jira.transition.assert_not_called()

    def test_changed_head_invalidates_review(self):
        workflow, _ = self.workflow()
        run = self.run_data('waiting_merge')
        workflow.github.pr.return_value = {'merged': False, 'state': 'open', 'head': {'sha': 'new'}}
        workflow.sync_head = Mock()
        workflow.agent = Mock(side_effect=RuntimeError('stop at QA'))
        with self.assertRaises(RuntimeError):
            workflow.advance(run)
        workflow.sync_head.assert_called_once_with(run, 'new')
        self.assertEqual(run['stage'], 'qa')

    def test_pending_checks_wait_for_human(self):
        workflow, _ = self.workflow()
        workflow.github.pr.return_value = {'merged': False, 'state': 'open', 'head': {'sha': 'abc'}}
        workflow.github.checks_pass.return_value = False
        run = workflow.advance(self.run_data('waiting_merge'))
        self.assertEqual(run['stage'], 'waiting_merge')
        self.assertFalse(run['checks_pass'])
        workflow.jira.transition.assert_not_called()

    def test_merged_acceptance_gap_leaves_open(self):
        workflow, _ = self.workflow()
        workflow.github.pr.return_value = {'merged': True, 'head': {'sha': 'abc'}, 'merge_commit_sha': 'merge'}
        workflow.github.checks_pass.return_value = True
        workflow.git = Mock(side_effect=lambda *args, **kwargs: 'merge' if args[0] == 'rev-parse' else '')
        workflow.codex.review.return_value = {'passed': False, 'gaps': ['manual launch missing']}
        run = workflow.advance(self.run_data('waiting_merge'))
        self.assertEqual(run['stage'], 'acceptance_gap')
        workflow.jira.transition.assert_not_called()

    def test_merge_completion_transition_failure_retries(self):
        workflow, store = self.workflow()
        run = self.run_data('complete')
        run['assessment'] = {'passed': True}
        run['merge_sha'] = 'merge'
        run['visual_observation'] = 'Launched visibly'
        run['assessment_validation'] = workflow.verify_merged.return_value
        workflow.github.pr.return_value = {'merged': True, 'merge_commit_sha': 'merge', 'head': {'sha': 'abc'}}
        workflow.github.checks_pass.return_value = True
        workflow.jira.transition.side_effect = [RuntimeError('Jira unavailable'), None]
        with self.assertRaises(RuntimeError):
            workflow.advance(run)
        self.assertEqual(store.get('run')['stage'], 'complete')
        self.assertEqual(workflow.advance(store.get('run'))['stage'], 'done')

    def test_github_pr_and_comment_idempotency(self):
        github = object.__new__(GitHub)
        github.repo, github.base, github.url, github.headers = 'owner/repo', 'main', 'https://example', {}
        github.get = Mock(return_value=[{'number': 4}])
        self.assertEqual(github.ensure_pr('branch', 'title', 'body')['number'], 4)
        with patch('harness.integrations.pages', return_value=[{'body': '<!-- tradewinds:key -->'}]), patch('harness.integrations.request') as req:
            github.comment(4, 'key', 'body')
            req.assert_not_called()

    def test_jira_comment_idempotency(self):
        jira = object.__new__(Jira)
        jira.get = Mock(return_value={'comments': [{'body': {'text': '[tradewinds:key]'}}], 'total': 1})
        with patch('harness.integrations.request') as req:
            jira.comment('KAN-8', 'key', 'body')
            req.assert_not_called()

    def test_failed_recheck_invalidates_previous_success(self):
        tools = Tools(self.root, 'qa', self.cfg, lambda _: None)
        tools.checks['validate'] = True
        with patch('harness.core.command', side_effect=RuntimeError('failed')):
            with self.assertRaises(RuntimeError):
                tools.call('run_check', {'name': 'validate'})
        self.assertEqual(tools.checks, {})

    def test_check_prerequisites_prevent_launching_invalid_project(self):
        self.cfg['commands']['smoke'] = ['fake']
        self.cfg['check_dependencies'] = {'smoke': ['validate']}
        tools = Tools(self.root, 'qa', self.cfg, lambda _: None)
        with patch('harness.core.command') as execute:
            with self.assertRaisesRegex(RuntimeError, 'validate'):
                tools.call('run_check', {'name': 'smoke'})
            execute.assert_not_called()

    def test_repair_success_reaches_publication(self):
        workflow, _ = self.workflow()
        run = self.run_data('qa')
        workflow.agent = Mock(side_effect=[{'passed': False, 'gaps': ['fix']}, {'passed': True}, {'passed': True}])
        workflow.commit = Mock(return_value='fixed')
        workflow.git = Mock(side_effect=RuntimeError('stop before push'))
        with self.assertRaises(RuntimeError):
            workflow.advance(run)
        self.assertEqual(run['stage'], 'publish')
        self.assertEqual(run['qa_sha'], 'fixed')
        self.assertEqual(run['repairs'], 1)

    def test_successful_merge_finishes_once(self):
        workflow, store = self.workflow()
        run = self.run_data('waiting_merge')
        run['visual_observation'] = 'Exported game visibly launched'
        workflow.github.pr.return_value = {'merged': True, 'head': {'sha': 'abc'}, 'merge_commit_sha': 'merge'}
        workflow.github.checks_pass.return_value = True
        workflow.git = Mock(side_effect=lambda *args, **kwargs: 'merge' if args[0] == 'rev-parse' else '')
        workflow.codex.review.return_value = {'passed': True, 'gaps': []}
        self.assertEqual(workflow.advance(run)['stage'], 'done')
        workflow.advance(store.get('run'))
        workflow.jira.transition.assert_called_once_with('KAN-8', 'done')

    def test_jira_missing_transition_is_visible(self):
        jira = object.__new__(Jira)
        jira.stages = {'developing': ['In Progress']}
        jira.issue = Mock(return_value={'fields': {'status': {'name': 'Todo'}}})
        jira.get = Mock(return_value={'transitions': []})
        with self.assertRaisesRegex(RuntimeError, 'No configured Jira transition'):
            jira.transition('KAN-8', 'developing')

    def test_story_cannot_complete_with_open_subtasks(self):
        jira = object.__new__(Jira)
        jira.stages = {'done': ['Done']}
        jira.issue = Mock(return_value={'fields': {'status': {'name': 'Todo'}, 'issuetype': {'hierarchyLevel': 0}}})
        jira.search = Mock(return_value=[{'fields': {'status': {'statusCategory': {'key': 'new'}}}}])
        with self.assertRaisesRegex(RuntimeError, 'Child issues'):
            jira.transition('KAN-8', 'done')

    def test_assessment_reconciles_previously_pending_checks(self):
        workflow, _ = self.workflow()
        run = self.run_data('assess')
        run.update(merge_sha='merge', merge_gap='Checks were pending', visual_observation='Launched visibly')
        workflow.github.pr.return_value = {'merged': True, 'head': {'sha': 'abc'}, 'merge_commit_sha': 'merge'}
        workflow.github.checks_pass.return_value = True
        workflow.git = Mock(side_effect=lambda *args, **kwargs: 'merge' if args[0] == 'rev-parse' else '')
        workflow.codex.review.return_value = {'passed': True, 'gaps': []}
        self.assertEqual(workflow.advance(run)['stage'], 'done')
        self.assertNotIn('merge_gap', run)

    def test_dirty_assessment_is_rejected(self):
        workflow, _ = self.workflow()
        run = self.run_data('assess')
        run['merge_sha'] = 'merge'
        workflow.github.pr.return_value = {'merged': True, 'head': {'sha': 'abc'}, 'merge_commit_sha': 'merge'}
        workflow.git = Mock(side_effect=lambda *args, **kwargs: 'dirty' if args[0] == 'status' else '')
        with self.assertRaisesRegex(RuntimeError, 'must be clean'):
            workflow.advance(run)
        workflow.codex.review.assert_not_called()

    def test_assessment_receives_command_results_for_merged_commit(self):
        workflow, _ = self.workflow()
        run = self.run_data('assess')
        run.update(merge_sha='merge', visual_observation='Observed the boxes')
        workflow.github.pr.return_value = {'merged': True, 'head': {'sha': 'abc'}, 'merge_commit_sha': 'merge'}
        workflow.github.checks_pass.return_value = True
        workflow.git = Mock(side_effect=lambda *args, **kwargs: 'merge' if args[0] == 'rev-parse' else '')
        workflow.codex.review.return_value = {'passed': True, 'gaps': []}
        self.assertEqual(workflow.advance(run)['stage'], 'done')
        evidence = workflow.codex.review.call_args.args[4]
        self.assertEqual(evidence['merged_commit_validation']['sha'], 'merge')
        self.assertEqual(evidence['merged_commit_validation']['checks']['validate']['output'], 'verified fixture output')

    def test_failed_merged_checks_override_optimistic_assessment(self):
        workflow, _ = self.workflow()
        run = self.run_data('assess')
        run.update(merge_sha='merge', visual_observation='Observed boxes')
        workflow.github.pr.return_value = {'merged': True, 'head': {'sha': 'abc'}, 'merge_commit_sha': 'merge'}
        workflow.github.checks_pass.return_value = True
        workflow.git = Mock(side_effect=lambda *args, **kwargs: 'merge' if args[0] == 'rev-parse' else '')
        workflow.verify_merged.return_value = {'sha': 'merge', 'passed': False, 'checks': {}, 'errors': ['export failed']}
        workflow.codex.review.return_value = {'passed': True, 'gaps': []}
        self.assertEqual(workflow.advance(run)['stage'], 'acceptance_gap')
        self.assertIn('export failed', run['assessment']['gaps'])
        workflow.jira.transition.assert_not_called()

    def test_merged_validation_uses_isolated_checkout_and_detects_source_changes(self):
        import sys
        workflow, _ = self.workflow()
        command(['git', 'init', '--initial-branch=main'], self.root)
        command(['git', 'config', 'user.name', 'Harness Test'], self.root)
        command(['git', 'config', 'user.email', 'harness@example.test'], self.root)
        (self.root / 'README.md').write_text('fixture')
        (self.root / '.gitignore').write_text('state/\nbuild/\n')
        command(['git', 'add', 'README.md', '.gitignore'], self.root)
        command(['git', 'commit', '-m', 'fixture'], self.root)
        sha = workflow.git('rev-parse', 'HEAD')
        run = self.run_data('assess')
        run['merge_sha'] = sha
        self.cfg['commands'] = {'validate': [sys.executable, '-c', "print('actual runtime receipt')"]}
        proof = Workflow.verify_merged(workflow, run)
        self.assertTrue(proof['passed'])
        self.assertTrue(proof['fresh_checkout'])
        self.assertNotEqual(Path(proof['checkout']), self.root)
        self.assertEqual(proof['sha'], sha)
        self.assertEqual(proof['checks']['validate']['exit_code'], 0)
        self.assertIn('actual runtime receipt', proof['checks']['validate']['output'])
        self.cfg['commands']['validate'] = [sys.executable, '-c', "from pathlib import Path; Path('README.md').write_text('modified')"]
        proof = Workflow.verify_merged(workflow, run)
        self.assertFalse(proof['passed'])
        self.assertFalse(proof['source_clean'])
        self.assertIn('Acceptance checks changed tracked or unignored source files', proof['errors'])

    def test_edit_during_review_is_rejected(self):
        workflow, _ = self.workflow()
        run = self.run_data('review')
        workflow.github.pr.return_value = {'merged': False, 'state': 'open', 'head': {'sha': 'abc'}}
        workflow.git = Mock(side_effect=['abc', '', 'changed'])
        workflow.codex.review.return_value = {'passed': True}
        with self.assertRaisesRegex(RuntimeError, 'changed during Codex review'):
            workflow.advance(run)
        workflow.github.comment.assert_not_called()

    def test_deleted_last_file_is_staged(self):
        workflow, _ = self.workflow()
        command(['git', 'init', '--initial-branch=main'], self.root)
        command(['git', 'config', 'user.name', 'Harness Test'], self.root)
        command(['git', 'config', 'user.email', 'harness@example.test'], self.root)
        (self.root / 'game').mkdir()
        path = self.root / 'game/last.txt'
        path.write_text('old')
        command(['git', 'add', 'game'], self.root)
        command(['git', 'commit', '-m', 'fixture'], self.root)
        path.unlink()
        path.parent.rmdir()
        workflow.commit(self.run_data('qa'))
        self.assertIn('D\tgame/last.txt', command(['git', 'show', '--format=', '--name-status', 'HEAD'], self.root))

    def test_git_ownership_exception_is_per_invocation_and_scoped(self):
        with patch('harness.core.command', return_value='ok') as execute:
            git_command(['status', '--short'], self.root)
        args = execute.call_args.args[0]
        self.assertEqual(args[:3], ['git', '-c', 'safe.directory=' + self.root.resolve().as_posix()])
        self.assertNotIn('--global', args)
        workflow, _ = self.workflow()
        with self.assertRaises(PermissionError):
            workflow.git('status', cwd=self.root.parent)

    def test_timeout_kills_descendants_holding_output_pipes(self):
        import sys
        import time
        child = 'import time; time.sleep(20)'
        parent = f'import subprocess,sys,time; subprocess.Popen([sys.executable,"-c",{child!r}]); time.sleep(20)'
        started = time.monotonic()
        with self.assertRaises(subprocess.TimeoutExpired):
            command([sys.executable, '-c', parent], self.root, timeout=0.3)
        self.assertLess(time.monotonic() - started, 2)

    def test_invalid_final_report_is_corrected_within_budget(self):
        prompts = self.root / 'prompts'
        prompts.mkdir()
        (prompts / 'qa.md').write_text('qa')
        bad = {'passed': True, 'summary': 'result', 'evidence': [], 'gaps': ['missing work']}
        good = {**bad, 'passed': False}
        responses = [{'message': {'role': 'assistant', 'content': 'finished'}},
                     {'message': {'role': 'assistant', 'content': json.dumps(bad)}},
                     {'message': {'role': 'assistant', 'content': json.dumps(good)}}]
        with patch('harness.core.request', side_effect=responses) as req:
            value = Ollama(self.cfg, prompts).run('qa', {}, Tools(self.root, 'qa', self.cfg, lambda _: None))
        self.assertFalse(value['passed'])
        self.assertEqual(req.call_count, 3)

    def test_github_checks_require_present_successful_evidence(self):
        github = object.__new__(GitHub)
        github.url, github.headers = 'https://example', {}
        for runs, state, expected in [([], {'statuses': []}, False),
            ([{'status': 'completed', 'conclusion': 'failure'}], {'statuses': []}, False),
            ([{'status': 'in_progress', 'conclusion': None}], {'statuses': []}, False),
            ([{'status': 'completed', 'conclusion': 'success'}], {'statuses': []}, True),
            ([], {'statuses': [{}], 'state': 'failure'}, False)]:
            github.get = Mock(return_value=state)
            with patch('harness.integrations.pages', return_value=runs):
                self.assertEqual(github.checks_pass('sha'), expected)

    def test_json_actions_execute_writes_and_automatic_checks(self):
        prompts = self.root / 'prompts'
        prompts.mkdir()
        (prompts / 'developer.md').write_text('develop')
        self.cfg['ollama']['protocol'] = 'json_actions'
        self.cfg['ollama']['developer'] = 'model'
        value = {'passed': True, 'summary': 'written', 'evidence': ['file and check'], 'gaps': []}
        actions = [dict(action='write_file', arguments={'path': 'game/probe.txt', 'content': 'real content'}),
                   dict(action='finish', arguments={}), value]
        responses = [{'message': {'role': 'assistant', 'content': json.dumps(a)}} for a in actions]
        tools = Tools(self.root, 'developer', self.cfg, lambda _: None)
        with patch('harness.core.request', side_effect=responses) as req, patch('harness.core.command', return_value=''):
            result = Ollama(self.cfg, prompts).run('developer', {}, tools)
        self.assertTrue(result['passed'])
        self.assertEqual((self.root / 'game/probe.txt').read_text(), 'real content')
        self.assertEqual(tools.checks, {'validate': True})
        self.assertNotIn('tools', req.call_args_list[0].args[1])
        self.assertIn('format', req.call_args_list[0].args[1])

    def test_structured_agent_cannot_pass_failed_real_checks(self):
        prompts = self.root / 'prompts'
        prompts.mkdir()
        (prompts / 'developer.md').write_text('develop')
        self.cfg['ollama'].update(protocol='json_actions', developer='model')
        value = {'passed': True, 'summary': 'imagined success', 'evidence': ['not real'], 'gaps': []}
        responses = [{'message': {'role': 'assistant', 'content': json.dumps(a)}} for a in [
            {'action': 'finish', 'arguments': {}}, value]]
        with patch('harness.core.request', side_effect=responses), patch('harness.core.command', side_effect=RuntimeError('no project')):
            result = Ollama(self.cfg, prompts).run('developer', {}, Tools(self.root, 'developer', self.cfg, lambda _: None))
        self.assertFalse(result['passed'])
        self.assertEqual(result['evidence'], [])
        self.assertIn('validate: no project', result['gaps'])

    def test_action_validation_does_not_accept_prose_or_arbitrary_tools(self):
        for value in ['example tool call', {'action': 'shell', 'arguments': {}},
                      {'action': 'finish', 'arguments': {'path': 'unexpected'}},
                      {'action': 'write_file', 'arguments': {'path': 42, 'content': 'bad'}}]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                action_call(value)

    def test_token_limited_action_is_not_executed(self):
        prompts = self.root / 'prompts'
        prompts.mkdir()
        (prompts / 'developer.md').write_text('develop')
        self.cfg['ollama'].update(protocol='json_actions', developer='model', max_output_tokens=128)
        value = {'passed': True, 'summary': 'done', 'evidence': [], 'gaps': []}
        responses = [
            {'done_reason': 'length', 'message': {'role': 'assistant', 'content': json.dumps({'action': 'write_file', 'arguments': {'path': 'game/should-not-exist.txt', 'content': 'truncated'}})}},
            {'message': {'role': 'assistant', 'content': json.dumps({'action': 'finish', 'arguments': {}})}},
            {'message': {'role': 'assistant', 'content': json.dumps(value)}}]
        with patch('harness.core.request', side_effect=responses) as req, patch('harness.core.command', side_effect=RuntimeError('missing file')):
            result = Ollama(self.cfg, prompts).run('developer', {}, Tools(self.root, 'developer', self.cfg, lambda _: None))
        self.assertFalse((self.root / 'game/should-not-exist.txt').exists())
        self.assertFalse(result['passed'])
        self.assertEqual(req.call_args_list[0].args[1]['options']['num_predict'], 128)

    def test_action_budget_failure_returns_report_for_bounded_repair(self):
        prompts = self.root / 'prompts'
        prompts.mkdir()
        (prompts / 'developer.md').write_text('develop')
        self.cfg['ollama'].update(protocol='json_actions', developer='model')
        message = {'message': {'role': 'assistant', 'content': json.dumps({'action': 'run_check', 'arguments': {'name': 'validate'}})}}
        with patch('harness.core.request', return_value=message), patch('harness.core.command', side_effect=RuntimeError('invalid project syntax')):
            result = Ollama(self.cfg, prompts).run('developer', {}, Tools(self.root, 'developer', self.cfg, lambda _: None))
        self.assertFalse(result['passed'])
        self.assertIn('budget exhausted', result['summary'])
        self.assertEqual(result['gaps'], ['invalid project syntax'])

    def test_simple_asset_policy_blocks_image_files(self):
        self.cfg['asset_policy'] = 'labeled_boxes'
        tools = Tools(self.root, 'developer', self.cfg, lambda _: None)
        for path in ('game/icon.svg', 'game/ship.PNG', 'game/ship.glb'):
            with self.assertRaisesRegex(PermissionError, 'Asset policy'):
                tools.call('write_file', {'path': path, 'content': 'unwanted'})
        tools.call('write_file', {'path': 'game/main.gd', 'content': 'extends Control'})

    def test_retry_preserves_history_and_worktree(self):
        workflow, store = self.workflow()
        run = self.run_data('exhausted')
        run.update(repairs=3, feedback=[{'summary': 'old failure'}])
        workflow.retry(run)
        self.assertEqual(run['stage'], 'develop')
        self.assertEqual(run['repairs'], 0)
        self.assertEqual(run['feedback'], [])
        self.assertEqual(run['retry_history'][0]['feedback'], [{'summary': 'old failure'}])
        self.assertEqual(store.get('run')['worktree'], str(self.root))
        with self.assertRaises(ValueError):
            workflow.retry(run)

    def test_jira_description_normalizes_to_plain_task_text(self):
        value = {'type': 'doc', 'content': [{'type': 'paragraph', 'content': [
            {'type': 'text', 'text': 'Not in scope:'}, {'type': 'text', 'text': ' final art'}]}]}
        self.assertEqual(plain_text(value).strip(), 'Not in scope: final art')

    def test_role_receives_actual_source_without_jira_transport_metadata(self):
        workflow, _ = self.workflow()
        run = self.run_data('develop')
        run['task'] = {'self': 'transport-only', 'fields': {'summary': 'Create skeleton', 'description': 'Only labeled boxes'}}
        (self.root / 'game').mkdir()
        (self.root / 'game/main.gd').write_text('extends Control')
        (self.root / '.env').write_text('secret-hidden')
        workflow.agent(run, 'developer')
        task = workflow.ollama.run.call_args.args[1]
        self.assertEqual(task['existing_files']['game/main.gd'], 'extends Control')
        self.assertNotIn('transport-only', json.dumps(task))
        self.assertNotIn('secret-hidden', json.dumps(task))


if __name__ == '__main__':
    unittest.main()
