from __future__ import annotations

import contextlib
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import time
import urllib.request
import urllib.error


def request(url, data=None, headers=None, method=None, timeout=60):
    raw = None if data is None else json.dumps(data).encode()
    req = urllib.request.Request(url, raw, {"Content-Type": "application/json", **(headers or {})}, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            body = response.read()
            return json.loads(body) if body else None
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"HTTP {error.code} for {req.method} {url.split('?')[0]}") from None


def clean_env():
    allowed = {"PATH", "SYSTEMROOT", "WINDIR", "TEMP", "TMP", "LOCALAPPDATA", "APPDATA", "USERPROFILE", "HOME", "COMSPEC", "PATHEXT"}
    return {k: v for k, v in os.environ.items() if k.upper() in allowed}


def command(args, cwd, timeout=180, env=None):
    result = subprocess.run(args, cwd=cwd, capture_output=True, text=True,
                            encoding="utf-8", errors="replace", timeout=timeout,
                            env=clean_env() if env is None else env)
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {args[0]}\n{result.stdout[-8000:]}\n{result.stderr[-8000:]}")
    return result.stdout + result.stderr


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
        return target

    def call(self, name, args):
        if name == "list_files":
            return [str(p.relative_to(self.root)).replace('\\', '/') for p in self.root.rglob('*')
                    if p.is_file() and not any(x.startswith('.') for x in p.relative_to(self.root).parts)][:500]
        if name == "read_file":
            return self.path(args["path"]).read_text(encoding="utf-8")[:20000]
        if name == "write_file":
            path = self.path(args["path"], True)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(args["content"], encoding="utf-8")
            self.checks.clear()
            return "written"
        if name == "run_check":
            key = args["name"]
            argv = self.config["commands"][key]
            self.checks.pop(key, None)
            (self.root / "build").mkdir(exist_ok=True)
            result = command([s.replace("{godot}", self.config["godot"]) for s in argv], self.root,
                             self.config["limits"]["command_seconds"])
            if any(x in result for x in ("SCRIPT ERROR:", "Parse Error:", "ERROR:")):
                raise RuntimeError(result[-10000:])
            self.checks[key] = True
            self.log({"check": key, "output": result})
            return result[-10000:] or "exit 0"
        raise PermissionError("Unknown tool")


TOOLS = [{"type": "function", "function": {"name": name, "description": description,
          "parameters": {"type": "object", "properties": {k: {"type": "string"} for k in keys},
                         "required": keys, "additionalProperties": False}}}
         for name, description, keys in [
             ("list_files", "List repository files", []),
             ("read_file", "Read a UTF-8 repository file", ["path"]),
             ("write_file", "Write a complete UTF-8 file within role permissions", ["path", "content"]),
             ("run_check", "Run one configured check: validate, smoke, export", ["name"])]]


class Ollama:
    def __init__(self, config, prompts):
        self.config, self.prompts = config, Path(prompts)

    def run(self, role, task, tools):
        cfg = self.config
        messages = [{"role": "system", "content": (self.prompts / f"{role}.md").read_text()},
                    {"role": "user", "content": json.dumps(task)}]
        for _ in range(cfg["limits"]["turns"]):
            payload = {"model": cfg["ollama"][role], "messages": messages, "stream": False,
                       "tools": TOOLS, "options": {"temperature": 0, "num_ctx": cfg["ollama"]["context"]}}
            message = request(cfg["ollama"]["url"] + "/api/chat", payload,
                              timeout=cfg["limits"]["model_seconds"])["message"]
            messages.append(message)
            tools.log({"role": role, "message": message})
            calls = message.get("tool_calls", [])
            if not calls:
                break
            for call in calls:
                function = call["function"]
                try:
                    result = tools.call(function["name"], function["arguments"])
                except (KeyError, ValueError, OSError, RuntimeError, subprocess.TimeoutExpired) as error:
                    result = {"error": str(error)}
                messages.append({"role": "tool", "tool_name": function["name"], "content": json.dumps(result)})
        else:
            raise RuntimeError("Agent tool-turn budget exhausted")
        messages.append({"role": "user", "content": "Return the final factual report using the required JSON schema."})
        result = request(cfg["ollama"]["url"] + "/api/chat", {
            "model": cfg["ollama"][role], "messages": messages, "stream": False, "format": REPORT_SCHEMA,
            "options": {"temperature": 0, "num_ctx": cfg["ollama"]["context"]}},
            timeout=cfg["limits"]["model_seconds"])
        value = report(json.loads(result["message"]["content"]))
        if role == "qa" and value["passed"] and set(tools.checks) != set(cfg["commands"]):
            value = {"passed": False, "summary": "QA did not execute all required checks after its final edit",
                     "evidence": value["evidence"], "gaps": ["Run every configured check successfully"]}
        tools.log({"role": role, "report": value})
        return value
