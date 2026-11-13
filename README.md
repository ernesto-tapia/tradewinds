# Caribbean Tradewinds

A small Godot 2D demo developed through a sequential local agent harness.

## Setup on Windows

Run `./scripts/setup.ps1` in PowerShell with Python 3.11+ installed. This pins PyYAML 6.0.3 and setuptools 80.9.0. Git, a signed-in Codex CLI, Ollama with `qwen2.5-coder:7b`, **Godot 4.5.1 stable standard** and matching Windows x86_64 export templates are prerequisites. Set `GODOT_BIN` and `CODEX_BIN` to executable paths if they are absent from PATH.

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

The default `ollama.protocol: json_actions` uses schema-constrained executable actions to avoid models describing tool calls as prose. `native` remains available for models with reliable native tool calling. Required checks are executed by the harness after the structured action loop, and failed checks override optimistic model reports. Jira descriptions are flattened to task text so transport metadata does not distract the model. Model claims alone cannot pass validation.

Foundation scaffolding guidance is scoped to KAN-8. Later stories use the current Jira requirements and optional `stories.<key>.guidance`, `commands`, and `check_dependencies` overrides. Checks run in dependency order. KAN-9 adds a real viewport-input test for two identifiable ports, destination feedback, bounded camera, and ship selection. Existing Ocean/Island labels do not satisfy it. Generic startup/export checks are regression checks, not evidence that a new feature was implemented.

Unchanged development results and empty diffs against the PR base return to bounded repair instead of attempting an empty PR (GitHub rejects that with HTTP 422). Existing saved publication-stage runs get the same guard when resumed. A successful model report cannot override an empty feature diff.

`ollama.max_output_tokens` bounds each response (default 2048). Truncated actions are never executed. Logs include Ollama timing/token metrics. A bounded snapshot of existing game files is supplied at role startup; agents can read further files with tools. The `scene` check verifies the title, labeled rectangles and label bounds without claiming human visual observation.

The default developer and QA model is now `qwen2.5-coder:7b`, selected after a user-approved local evaluation on KAN-8. Both roles passed validate, scene, smoke, and Windows export, including launching the exported executable headlessly. The earlier `llama3.1:8b` run described calls as text and later struggled with Godot syntax; its history is preserved under `.runs/`. It remains installed, and role models are editable in YAML. No OpenAI model silently replaces a failed Ollama role.

`check_dependencies` prevents running smoke/export against an unvalidated or blank scene. Rewriting identical text preserves check receipts, including across Windows line endings. Action-budget failures return factual failed reports and consume the bounded repair budget. Git ownership trust is scoped to the exact selected workspace per invocation; no global `safe.directory=*` exception is installed.

To retry after correcting a harness/model problem, use `tradewinds resume RUN_ID --retry`. This starts a new bounded cycle in the same worktree, archives the old feedback and repair count in `retry_history`, and preserves all existing logs. It does not increase the global repair limit.

All prototype visuals must be simple rectangles with labels inside, using built-in fonts and flat colors. No image generation, downloaded art, sprites, SVGs, complex shapes, models, shaders, animation assets or audio. File tools block common external asset formats when `asset_policy: labeled_boxes` is configured. See `AGENTS.md` and the role prompts.

The harness restricts tool paths and command names, but this is **not an OS security sandbox**: Godot executes project code. Use only your trusted repository and trusted configured checks. Agents cannot edit harness policy or CI through file tools. No arbitrary shell tool is exposed. Codex uses read-only mode and its existing account login.

State lives in ignored `.runs/state.sqlite`; logs and worktrees are under `.runs/`. An exclusive SQLite lock prevents concurrent runs. PR/comment reconciliation uses remote evidence and stable markers, including after a lost HTTP response. Do not manually reuse a run branch for another story. No force push or automatic merge is used.

Post-merge completion requires a matching reviewed head, successful GitHub checks, and Codex acceptance assessment. Gaps leave Jira open. Jira destinations must match your site's actual workflow; `doctor` verifies connectivity, and a missing stage transition fails visibly. Epics are never run as stories.

During post-merge assessment the harness validates and exports the exact merge commit in an isolated, clean detached checkout under `.runs/acceptance/`. Codex receives actual command arguments, working directories, exit codes and runtime output, including the exported-executable launch. These receipts remain in `assessment-checks.jsonl`; summaries alone are not treated as runtime proof. Failed merged-build checks prevent completion even if the model reports success.

`acceptance_gap` is a deliberate pause, not a repeating repair loop. `status` shows its specific gaps. Stop a running watcher with Ctrl+C, then use `resume RUN_ID --visual-observation ...` to record your real playtest observations and reassess. The assistant's visual check does not substitute for your human note.

## Validation

If authentication fails, run `.\.venv\Scripts\python.exe scripts/check_auth.py` in the terminal containing your tokens. It prints only formatting booleans and HTTP status codes; response bodies and credential values are never displayed. It tests GitHub account and repository access separately, and both direct-site and scoped-token Jira routes. A scoped token needs the Atlassian gateway: if the diagnostic returns `jira_api_url_to_set`, set `$env:JIRA_API_URL` to that URL and rerun `doctor`. Keep `jira.url` as the human-facing site URL. See [Atlassian token routing](https://support.atlassian.com/atlassian-account/docs/manage-api-tokens-for-your-atlassian-account/).

Run `python -m unittest discover -s tests -v`. Integration tests use fixtures and make no network calls. For a live run, `doctor` must pass first. Game setup and export instructions belong in `docs/game/README.md`, created by KAN-8.

`python scripts/smoke_agents.py` optionally tests the real Ollama developer and QA tool loops with a temporary text-file task, without Jira/GitHub writes. Logs go to `.runs/model-smoke.jsonl`.

Codex receives the exact commit diff and committed game-source snapshot, so it can review even when local file-reading tools are unavailable. Truncated or binary context is listed as omitted. Process deadlines terminate child processes using Windows Job Objects. A rebased PR head preserves the old local head under `refs/tradewinds/backups/` before synchronizing the clean worktree; publication never force-pushes.
