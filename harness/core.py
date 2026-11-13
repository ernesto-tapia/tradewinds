from __future__ import annotations

import contextlib
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import time
import tempfile
import urllib.request
import urllib.error


class WindowsJob:
    """Close the job to terminate every descendant, including inherited pipes."""
    def __init__(self, process):
        import ctypes
        from ctypes import wintypes
        class Basic(ctypes.Structure):
            _fields_ = [('process_time', ctypes.c_int64), ('job_time', ctypes.c_int64),
                        ('flags', wintypes.DWORD), ('min_ws', ctypes.c_size_t), ('max_ws', ctypes.c_size_t),
                        ('process_limit', wintypes.DWORD), ('affinity', ctypes.c_size_t),
                        ('priority', wintypes.DWORD), ('scheduling', wintypes.DWORD)]
        class Extended(ctypes.Structure):
            _fields_ = [('basic', Basic), ('io', ctypes.c_uint64 * 6),
                        ('process_memory', ctypes.c_size_t), ('job_memory', ctypes.c_size_t),
                        ('peak_process_memory', ctypes.c_size_t), ('peak_job_memory', ctypes.c_size_t)]
        self.kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        self.kernel.CreateJobObjectW.argtypes = [ctypes.c_void_p, wintypes.LPCWSTR]
        self.kernel.CreateJobObjectW.restype = wintypes.HANDLE
        self.kernel.SetInformationJobObject.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD]
        self.kernel.AssignProcessToJobObject.argtypes = [wintypes.HANDLE, wintypes.HANDLE]
        self.kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        self.handle = self.kernel.CreateJobObjectW(None, None)
        info = Extended()
        info.basic.flags = 0x2000  # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        if not self.handle or not self.kernel.SetInformationJobObject(self.handle, 9, ctypes.byref(info), ctypes.sizeof(info)) or not self.kernel.AssignProcessToJobObject(self.handle, int(process._handle)):
            error = ctypes.get_last_error()
            self.close()
            process.kill()
            raise OSError(error, 'Cannot establish Windows process-tree boundary')

    def close(self):
        if self.handle:
            self.kernel.CloseHandle(self.handle)
            self.handle = None


def run_process(args, cwd, timeout, env=None, input=None):
    process = subprocess.Popen(args, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               stdin=subprocess.PIPE if input is not None else subprocess.DEVNULL,
                               text=True, encoding='utf-8', errors='replace',
                               env=clean_env() if env is None else env,
                               start_new_session=os.name != 'nt')
    job = WindowsJob(process) if os.name == 'nt' else None
    try:
        stdout, stderr = process.communicate(input=input, timeout=timeout)
        return subprocess.CompletedProcess(args, process.returncode, stdout, stderr)
    except (subprocess.TimeoutExpired, KeyboardInterrupt):
        if job:
            job.close()
        else:
            import signal
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        try:
            process.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            pass
        raise
    finally:
        if job:
            job.close()


def request(url, data=None, headers=None, method=None, timeout=60):
    raw = None if data is None else json.dumps(data).encode()
    req = urllib.request.Request(url, raw, {"Content-Type": "application/json", **(headers or {})}, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            body = response.read()
            return json.loads(body) if body else None
    except urllib.error.HTTPError as error:
        hints = {401: 'Credentials were rejected; check the token, email, and expiration.',
                 403: 'Access denied; check token permissions and account/repository access.',
                 404: 'Resource unavailable; check the URL and token access to this resource.'}
        error.close()
        raise RuntimeError(f"HTTP {error.code} for {req.get_method()} {url.split('?')[0]}. {hints.get(error.code, '')}".strip()) from None


def clean_env():
    allowed = {"PATH", "SYSTEMROOT", "WINDIR", "TEMP", "TMP", "LOCALAPPDATA", "APPDATA", "USERPROFILE", "HOME", "COMSPEC", "PATHEXT"}
    return {k: v for k, v in os.environ.items() if k.upper() in allowed}


def command(args, cwd, timeout=180, env=None):
    result = run_process(args, cwd, timeout, env)
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {args[0]}\n{result.stdout[-8000:]}\n{result.stderr[-8000:]}")
    return result.stdout + result.stderr


def git_command(args, cwd, timeout=180):
    # Trust this explicitly selected workspace for this invocation only. Windows
    # administrator-created worktrees may otherwise fail ownership checks.
    directory = Path(cwd).resolve()
    return command(['git', '-c', 'safe.directory=' + directory.as_posix(), *args], directory, timeout)


def report(value):
    if not isinstance(value, dict) or set(value) != {"passed", "summary", "evidence", "gaps"}:
        raise ValueError("Invalid report fields")
    if type(value["passed"]) is not bool or not isinstance(value["summary"], str):
        raise ValueError("Invalid report types")
    for key in ("evidence", "gaps"):
        if not isinstance(value[key], list) or not all(isinstance(x, str) for x in value[key]):
            raise ValueError("Invalid report list")
    if value["passed"] and value["gaps"]:
        raise ValueError("Passing report contains gaps")
    return value


REPORT_SCHEMA = {"type": "object", "additionalProperties": False,
                 "properties": {"passed": {"type": "boolean"}, "summary": {"type": "string"},
                                "evidence": {"type": "array", "items": {"type": "string"}},
                                "gaps": {"type": "array", "items": {"type": "string"}}},
                 "required": ["passed", "summary", "evidence", "gaps"]}


class Store:
    def __init__(self, root):
        self.root = Path(root)
        self.root.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(self.root / "state.sqlite")
        self.db.execute("CREATE TABLE IF NOT EXISTS runs (id TEXT PRIMARY KEY, data TEXT NOT NULL)")

    def save(self, run):
        self.db.execute("INSERT OR REPLACE INTO runs VALUES (?, ?)", (run["id"], json.dumps(run)))
        self.db.commit()

    def all(self):
        return [json.loads(row[0]) for row in self.db.execute("SELECT data FROM runs ORDER BY rowid")]

    def get(self, run_id):
        return next(r for r in self.all() if r["id"] == run_id)

    def log(self, run_id, name, value):
        folder = self.root / run_id
        folder.mkdir(exist_ok=True)
        with (folder / f"{name}.jsonl").open("a", encoding="utf-8") as stream:
            stream.write(json.dumps(value, ensure_ascii=False) + "\n")

    @contextlib.contextmanager
    def lock(self):
        # SQLite releases the lock automatically after a crash; separate connection
        # leaves the state database usable during a long agent call.
        lock = sqlite3.connect(self.root / "lock.sqlite", timeout=0)
        try:
            lock.execute("BEGIN EXCLUSIVE")
            yield
        finally:
            lock.close()


class Tools:
    def __init__(self, root, role, config, log):
        self.root, self.role, self.config, self.log = Path(root).resolve(), role, config, log
        self.checks = {}
        self.receipts = {}

    def path(self, name, write=False):
        rel = Path(name)
        target = (self.root / rel).resolve()
        if rel.is_absolute() or not target.is_relative_to(self.root):
            raise PermissionError("Path outside worktree")
        parts = target.relative_to(self.root).parts
        if any(p.startswith('.') or p in ("__pycache__",) for p in parts):
            raise PermissionError("Hidden/internal paths are unavailable")
        if write and not any(target.is_relative_to(self.root / p) for p in self.config["permissions"][self.role]):
            raise PermissionError(f"{self.role} cannot write {name}")
        if write and self.config.get('asset_policy') == 'labeled_boxes' and target.suffix.lower() in {
                '.png', '.jpg', '.jpeg', '.webp', '.svg', '.gif', '.bmp', '.ico', '.tga', '.tiff',
                '.psd', '.blend', '.glb', '.gltf', '.fbx', '.obj', '.wav', '.mp3', '.ogg'}:
            raise PermissionError('Asset policy: use a simple rectangle with an interior text label; no image, model, or audio assets')
        return target

    def call(self, name, args):
        if name == "list_files":
            return [str(p.relative_to(self.root)).replace('\\', '/') for p in self.root.rglob('*')
                    if p.is_file() and not any(x.startswith('.') for x in p.relative_to(self.root).parts)][:500]
        if name == "read_file":
            return self.path(args["path"]).read_text(encoding="utf-8")[:20000]
        if name == "write_file":
            path = self.path(args["path"], True)
            if path.is_file() and path.read_bytes().replace(b'\r\n', b'\n') == args['content'].encode('utf-8').replace(b'\r\n', b'\n'):
                return 'unchanged: file already has exactly this content; fixing an error requires different content'
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(args["content"], encoding="utf-8", newline='\n')
            self.checks.clear()
            self.receipts.clear()
            return "written"
        if name == "run_check":
            key = args["name"]
            argv = self.config["commands"][key]
            missing = [check for check in self.config.get('check_dependencies', {}).get(key, []) if check not in self.checks]
            if missing:
                raise RuntimeError('Run required checks successfully first: ' + ', '.join(missing))
            self.checks.pop(key, None)
            self.receipts.pop(key, None)
            (self.root / "build").mkdir(exist_ok=True)
            resolved = [s.replace("{godot}", self.config["godot"]).replace('{harness_root}', str(Path(__file__).resolve().parents[1])) for s in argv]
            result = command(resolved, self.root,
                             self.config["limits"]["command_seconds"])
            if any(x in result for x in ("SCRIPT ERROR:", "Parse Error:", "ERROR:")):
                lines = result.splitlines()
                errors = [line for i, line in enumerate(lines) if any('ERROR:' in prior or 'Parse Error:' in prior for prior in lines[max(0, i-2):i+1])]
                raise RuntimeError('\n'.join(errors)[-4000:])
            receipt = {'command': resolved, 'cwd': str(self.root), 'exit_code': 0, 'output': result}
            if key == 'export' and self.config.get('export_artifact'):
                artifact = self.path(self.config['export_artifact'])
                if not artifact.is_file():
                    raise RuntimeError('Exported executable is missing')
                smoke_command = [str(artifact), '--headless', '--quit-after', '120']
                smoke = command(smoke_command, artifact.parent,
                                self.config['limits']['command_seconds'])
                if 'ERROR:' in smoke:
                    raise RuntimeError(smoke[-10000:])
                result += '\nExported executable smoke test:\n' + smoke
                receipt['exported_executable_launch'] = {'command': smoke_command, 'cwd': str(artifact.parent), 'exit_code': 0, 'output': smoke}
            self.checks[key] = True
            self.receipts[key] = receipt
            self.log({"check": key, "output": result, 'receipt': receipt})
            return result[-1500:] or "exit 0"
        raise PermissionError("Unknown tool")


TOOLS = [{"type": "function", "function": {"name": name, "description": description,
          "parameters": {"type": "object", "properties": {k: {"type": "string"} for k in keys},
                         "required": keys, "additionalProperties": False}}}
         for name, description, keys in [
             ("list_files", "List repository files", []),
             ("read_file", "Read a UTF-8 repository file", ["path"]),
             ("write_file", "Write a complete UTF-8 file within role permissions", ["path", "content"]),
             ("run_check", "Run a configured check by name from the task configured_checks list", ["name"])]]

ACTION_SCHEMA = {'oneOf': [
    {'type': 'object', 'additionalProperties': False, 'required': ['action', 'arguments'],
     'properties': {'action': {'type': 'string', 'enum': [name]}, 'arguments': parameters}}
    for name, parameters in [(t['function']['name'], t['function']['parameters']) for t in TOOLS]
    + [('finish', {'type': 'object', 'properties': {}, 'required': [], 'additionalProperties': False})]]}


def action_call(value):
    if not isinstance(value, dict) or set(value) != {'action', 'arguments'}:
        raise ValueError('Return exactly action and arguments')
    name, args = value['action'], value['arguments']
    expected = {t['function']['name']: t['function']['parameters']['required'] for t in TOOLS}
    expected['finish'] = []
    if not isinstance(name, str) or name not in expected or not isinstance(args, dict):
        raise ValueError('Unknown action or invalid arguments')
    if set(args) != set(expected[name]) or not all(isinstance(v, str) for v in args.values()):
        raise ValueError('Invalid action arguments')
    return name, args


class Ollama:
    def __init__(self, config, prompts):
        self.config, self.prompts = config, Path(prompts)

    def chat(self, cfg, role, messages, schema, tools):
        return request(cfg['ollama']['url'] + '/api/chat', {
            'model': cfg['ollama'][role], 'messages': messages, 'stream': False,
            'format': schema, 'options': {'temperature': 0, 'num_ctx': cfg['ollama']['context'],
            'num_predict': cfg['ollama'].get('max_output_tokens', 2048)}}, timeout=cfg['limits']['model_seconds'])

    def run(self, role, task, tools):
        cfg = tools.config
        structured = cfg.get('agents', {}).get('provider') == 'codex' or cfg['ollama'].get('protocol') == 'json_actions'
        model = cfg['agents']['model'] if cfg.get('agents', {}).get('provider') == 'codex' else cfg['ollama'][role]
        tools.log({'role': role, 'model': model, 'protocol': 'json_actions' if structured else 'native'})
        system = (self.prompts / f'{role}.md').read_text(encoding='utf-8')
        if structured:
            system += ('\nRespond with one executable JSON action per turn, never prose or example calls. '
                       'The harness actually executes each action and returns its result. '
                       'Actions: list_files arguments {}; read_file arguments {"path":"relative/path"}; '
                       'write_file arguments {"path":"relative/path","content":"complete file text"}; '
                       'run_check arguments {"name":"configured check name"}; finish arguments {}. '
                       'Use action and arguments keys. For example: '
                       '{"action":"read_file","arguments":{"path":"README.md"}}. '
                       'Use workspace paths starting game/ or docs/game/ when writing game files, never res://. '
                       'Only finish when work is actually complete.\nSchema: ' + json.dumps(ACTION_SCHEMA))
        messages = [{"role": "system", "content": system},
                    {"role": "user", "content": json.dumps(task)}]
        last_tool_error = None
        ineffective_actions = {}
        rejected_actions = 0
        def rejected_report(reason):
            value = {'passed': False, 'summary': f'{role} repeatedly produced unusable actions',
                     'evidence': [f'{name}: verified exit 0' for name in tools.checks], 'gaps': [reason]}
            tools.log({'role': role, 'report': value})
            return value
        for _ in range(cfg["limits"]["turns"]):
            payload = {"model": cfg["ollama"][role], "messages": messages, "stream": False,
                       "options": {"temperature": 0, "num_ctx": cfg["ollama"]["context"],
                                   "num_predict": cfg['ollama'].get('max_output_tokens', 2048)}}
            payload['format' if structured else 'tools'] = ACTION_SCHEMA if structured else TOOLS
            answer = self.chat(cfg, role, messages, ACTION_SCHEMA, tools) if structured else request(
                cfg['ollama']['url'] + '/api/chat', payload, timeout=cfg['limits']['model_seconds'])
            message = answer['message']
            messages.append(message)
            tools.log({"role": role, "message": message, 'metrics': {k: answer[k] for k in
                       ('done_reason', 'prompt_eval_count', 'eval_count', 'total_duration') if k in answer}})
            if answer.get('done_reason') == 'length':
                rejected_actions += 1
                if rejected_actions >= cfg['limits'].get('no_progress', 3):
                    return rejected_report('Repeated output truncation; no truncated action was executed.')
                messages.append({'role': 'user', 'content': 'Output token budget exceeded. Return one concise complete action. Keep files short; do not repeat code or emit prose.'})
                continue
            if structured:
                try:
                    name, args = action_call(json.loads(message['content']))
                except (ValueError, TypeError) as error:
                    rejected_actions += 1
                    if rejected_actions >= cfg['limits'].get('no_progress', 3):
                        return rejected_report(f'Repeated invalid actions: {error}')
                    messages.append({'role': 'user', 'content': f'Action rejected: {error}. Return a valid JSON action.'})
                    continue
                rejected_actions = 0
                if name == 'finish':
                    break
                calls = [{'function': {'name': name, 'arguments': args}}]
            else:
                calls = message.get("tool_calls", [])
            if not calls:
                break
            for call in calls:
                function = call["function"]
                try:
                    result = tools.call(function["name"], function["arguments"])
                except (KeyError, ValueError, OSError, RuntimeError, subprocess.TimeoutExpired) as error:
                    result = {"error": str(error)}
                    last_tool_error = str(error)
                tools.log({'tool': function['name'], 'result': result})
                if result == 'written':
                    ineffective_actions.clear()
                elif (isinstance(result, dict) and 'error' in result) or (isinstance(result, str) and result.startswith('unchanged:')):
                    signature = json.dumps([function['name'], function['arguments'], result], sort_keys=True)
                    ineffective_actions[signature] = ineffective_actions.get(signature, 0) + 1
                    if ineffective_actions[signature] >= cfg['limits'].get('no_progress', 3):
                        value = {'passed': False, 'summary': f'{role} repeated an ineffective action without source progress',
                                 'evidence': [f'{name}: verified exit 0' for name in tools.checks],
                                 'gaps': [last_tool_error or 'The same unchanged file was submitted repeatedly; implement the current feature instead.']}
                        tools.log({'role': role, 'report': value})
                        return value
                messages.append({'role': 'user', 'content': json.dumps({'executed_action': function['name'], 'result': result})} if structured else
                                {"role": "tool", "tool_name": function["name"], "content": json.dumps(result)})
        else:
            value = {'passed': False, 'summary': f'{role} tool-turn budget exhausted',
                     'evidence': [f'{name}: verified exit 0' for name in tools.checks],
                     'gaps': [last_tool_error or 'Agent did not finish within the configured action budget']}
            tools.log({'role': role, 'report': value})
            return value
        check_errors = []
        if structured:
            for name in cfg['commands']:
                if name in tools.checks:
                    continue
                try:
                    tools.call('run_check', {'name': name})
                except (KeyError, ValueError, OSError, RuntimeError, subprocess.TimeoutExpired) as error:
                    check_errors.append(f'{name}: {error}')
                    tools.log({'required_check': name, 'error': str(error)})
                    break
            messages.append({'role': 'user', 'content': json.dumps({'verified_checks': tools.checks, 'check_errors': check_errors})})
        messages.append({"role": "user", "content": "Return the final factual report using the report JSON schema, not an action. Gaps are unmet IN-SCOPE requirements only. Excluded work (final art, multiplayer, world simulation) is not a gap. Human visual review happens separately after automated QA. Never claim unexecuted actions or tests. If passed=true, gaps must be the empty array []."})
        for attempt in range(cfg['limits'].get('report_attempts', 2)):
            result = self.chat(cfg, role, messages, REPORT_SCHEMA, tools)
            tools.log({'role': role, 'raw_report': result['message']['content'], 'attempt': attempt + 1})
            try:
                value = report(json.loads(result["message"]["content"]))
                break
            except (ValueError, TypeError) as error:
                if attempt + 1 >= cfg['limits'].get('report_attempts', 2):
                    raise
                messages.append(result['message'])
                messages.append({'role': 'user', 'content': f'Invalid report: {error}. Correct the report while preserving the factual outcome. Use passed=false if unmet requirements remain.'})
        if (role == 'qa' or structured) and set(tools.checks) != set(cfg['commands']):
            value = {"passed": False, "summary": f"{role} lacks successful required checks after its final edit",
                     "evidence": [f'{name}: verified exit 0' for name in tools.checks],
                     "gaps": check_errors + [f'Required check not passed: {name}' for name in cfg['commands'] if name not in tools.checks]}
        tools.log({"role": role, "report": value})
        return value


class CodexActions(Ollama):
    """Codex proposes JSON actions; only the host Tools executes them."""

    def chat(self, cfg, role, messages, schema, tools):
        settings = cfg['agents']
        action = schema is ACTION_SCHEMA
        # Structured outputs require a root object and all properties required.
        # The host's stricter action_call validates the applicable argument set.
        wire_schema = {'type': 'object', 'additionalProperties': False,
            'required': ['action', 'arguments'], 'properties': {
                'action': {'type': 'string', 'enum': ['list_files', 'read_file', 'write_file', 'run_check', 'finish']},
                'arguments': {'type': 'object', 'additionalProperties': False,
                    'required': ['path', 'content', 'name'], 'properties': {
                        key: {'type': ['string', 'null']} for key in ('path', 'content', 'name')}}}} if action else schema
        with tempfile.TemporaryDirectory(prefix='tradewinds-codex-') as folder:
            schema_path, output = Path(folder) / 'schema.json', Path(folder) / 'response.json'
            schema_path.write_text(json.dumps(wire_schema), encoding='utf-8')
            prompt = ('Act as a model endpoint for the host harness. Do not execute native tools or shell commands. '
                      'The supplied conversation contains the authoritative task, source and real tool results. '
                      'Return the next JSON action or final report requested by the last message. '
                      'For actions use null for unused argument fields.\n' + json.dumps(messages))
            result = run_process([cfg['codex'], 'exec', '--sandbox', 'read-only', '--ephemeral',
                '--ignore-user-config', '--model', settings['model'], '-c',
                'model_reasoning_effort=' + json.dumps(settings['reasoning_effort']),
                '--output-schema', str(schema_path), '--output-last-message', str(output), '-'],
                cwd=tools.root, env=clean_env(), input=prompt, timeout=cfg['limits']['model_seconds'])
            tools.log({'role': role, 'provider': 'codex', 'transcript': result.stdout + result.stderr})
            if result.returncode or not output.exists():
                raise RuntimeError('Codex action generation failed; inspect the role transcript')
            value = json.loads(output.read_text(encoding='utf-8'))
            if action and isinstance(value.get('arguments'), dict):
                value['arguments'] = {k: v for k, v in value['arguments'].items() if v is not None}
            return {'message': {'role': 'assistant', 'content': json.dumps(value)}}


def agent_client(config, prompts):
    provider = config.get('agents', {}).get('provider', 'ollama')
    if provider not in ('ollama', 'codex'):
        raise ValueError('agents.provider must be ollama or codex')
    if provider == 'ollama' and config.get('agents', {}).get('fallback') == 'codex':
        return FallbackAgents(config, prompts)
    return (CodexActions if provider == 'codex' else Ollama)(config, prompts)


class FallbackAgents:
    def __init__(self, config, prompts):
        self.local = Ollama(config, prompts)
        self.remote = CodexActions(config, prompts)

    def run(self, role, task, tools):
        try:
            local_report = self.local.run(role, task, tools)
        except (RuntimeError, ValueError, OSError, TypeError, subprocess.TimeoutExpired) as error:
            local_report = {'passed': False, 'summary': 'Local agent failed',
                            'evidence': [], 'gaps': [str(error)]}
        if local_report['passed']:
            return local_report
        tools.log({'role': role, 'fallback': 'codex', 'local_report': local_report})
        import copy
        original = tools.config
        cfg = copy.deepcopy(original)
        cfg['agents']['provider'] = 'codex'
        tools.config = cfg
        try:
            return self.remote.run(role, {**task, 'local_failure': local_report}, tools)
        finally:
            tools.config = original
