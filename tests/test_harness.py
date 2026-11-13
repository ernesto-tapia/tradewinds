import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

from harness.core import Ollama, Store, Tools, command, report
from harness.workflow import Workflow
from harness.integrations import GitHub, Jira


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

    def workflow(self):
        store = Store(self.root / 'state')
        self.addCleanup(store.db.close)
        workflow = Workflow(self.root, self.cfg, store, Mock(), Mock(), Mock(), Mock())
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
        self.assertEqual(workflow.agent.call_count, 7)  # QA + 3 developer/QA repairs

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


if __name__ == '__main__':
    unittest.main()
