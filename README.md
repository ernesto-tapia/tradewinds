# Caribbean Tradewinds

A small Godot 2D demo developed through a sequential local agent harness.

## Setup on Windows

Run `./scripts/setup.ps1` in PowerShell with Python 3.11+ installed. This pins PyYAML 6.0.3 and setuptools 80.9.0. Git, a signed-in Codex CLI, Ollama with `llama3.1:8b`, **Godot 4.5.1 stable standard** and matching Windows x86_64 export templates are prerequisites. Set `GODOT_BIN` and `CODEX_BIN` to executable paths if they are absent from PATH.

`python scripts/install_godot.py` downloads checksum-verified official engine and template assets. It installs the engine under `.tools/godot` (auto-detected by the harness) and templates under your user Godot directory. The template archive is large. The installed Codex CLI used during setup was `0.167.0-alpha.4.1`; `doctor` checks its login, and the harness uses `exec --output-schema` and `--ignore-user-config` to avoid loading unrelated integrations.

Set these environment variables in the same terminal that launches the harness:

```powershell
$env:GITHUB_TOKEN = [System.Net.NetworkCredential]::new('', (Read-Host 'GitHub token' -AsSecureString)).Password
$env:JIRA_EMAIL = Read-Host 'Jira email'
$env:JIRA_API_TOKEN = [System.Net.NetworkCredential]::new('', (Read-Host 'Jira API token' -AsSecureString)).Password
```

Use a GitHub fine-grained token restricted to this repository: Contents, Pull requests, Issues read/write; Actions, Checks, Commit statuses read. Git push uses your existing Git Credential Manager authentication, separately from the REST token. Jira uses an Atlassian API token without scopes with your account email, against the configured site URL. Tokens with scopes require an Atlassian gateway URL instead. Never commit credentials. Integration variables are excluded from model-tool and Codex subprocess environments.

## Commands

```powershell
.\.venv\Scripts\tradewinds.exe doctor
.\.venv\Scripts\tradewinds.exe backlog
.\.venv\Scripts\tradewinds.exe run KAN-8
.\.venv\Scripts\tradewinds.exe status
.\.venv\Scripts\tradewinds.exe resume RUN_ID
.\.venv\Scripts\tradewinds.exe watch --once
.\.venv\Scripts\tradewinds.exe watch
```

`watch` runs in the foreground and polls every 60 seconds. It stops when you close the terminal or press Ctrl+C. Resume after restarting; this is not a background service. Your merge is the only merge authority. A clean review is not a GitHub approval or a substitute for your playtest.

After manually launching the exported build, record what you actually observed:

```powershell
.\.venv\Scripts\tradewinds.exe resume RUN_ID --visual-observation 'Launched the exported Windows executable; ocean map and title displayed without errors.'
```

## How to customize

Edit `harness.yaml` for models, endpoint, deadlines, repair budget, check commands, write scopes and Jira destination names. Edit `prompts/` for developer, QA and Codex guidance. A run snapshots its Jira story; later story edits require a new run. Config/prompts are read at process start, so restart to apply changes.

Developer and QA have separate conversations. QA can edit only `tests/game/`. Three total repair rounds are shared between QA and Codex findings. Test failures, model errors and exhausted budgets remain visible; there is no silent replacement of the local model with Codex.

The harness restricts tool paths and command names, but this is **not an OS security sandbox**: Godot executes project code. Use only your trusted repository and trusted configured checks. Agents cannot edit harness policy or CI through file tools. No arbitrary shell tool is exposed. Codex uses read-only mode and its existing account login.

State lives in ignored `.runs/state.sqlite`; logs and worktrees are under `.runs/`. An exclusive SQLite lock prevents concurrent runs. PR/comment reconciliation uses remote evidence and stable markers, including after a lost HTTP response. Do not manually reuse a run branch for another story. No force push or automatic merge is used.

Post-merge completion requires a matching reviewed head, successful GitHub checks, and Codex acceptance assessment. Gaps leave Jira open. Jira destinations must match your site's actual workflow; `doctor` verifies connectivity, and a missing stage transition fails visibly. Epics are never run as stories.

## Validation

Run `python -m unittest discover -s tests -v`. Integration tests use fixtures and make no network calls. For a live run, `doctor` must pass first. Game setup and export instructions belong in `docs/game/README.md`, created by KAN-8.
