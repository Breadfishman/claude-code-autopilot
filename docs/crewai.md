# CrewAI Setup and Workflow

This guide covers the CrewAI multi-crew setup added by `--with-crewai`.

## Architecture

```
Task files (bin/*.md)
        │
        ▼
engineering-loop.sh
        │
   **Type:** field
        │
   ┌────┴──────────────────────────────────────────┐
   │                                               │
coding (default)                    research / creative / personal
   │                                marketing / auto / <custom>
   ▼                                               │
claude-max-proxy (port 3456)                       ▼
  Claude Code subscription             CrewAI router (Codex)
  Executes code, runs tests,                       │
  retries on failure, commits          ┌───────────┴──────────────┐
                                       │                          │
                               Public domain crews       Private crews
                               (research, creative)    .crewai/crews/private/
                               Codex via CLIProxyAPI    (gitignored, yours only)
                                       │
                                       ▼
                               bin/outputs/<slug>/result.md
```

**Two subscription-backed engines:**
- **CLIProxyAPI (port 8317)** — Codex/OpenAI subscription → "brain" for all thinking and non-coding tasks
- **claude-max-proxy (port 3456)** — Claude Max subscription → "hands" for coding execution only

## What `--with-crewai` Adds

- Runs `.claude/bootstrap/crewai_setup.sh`
- Scaffolds `.crewai/` with:
  - Engineering planner crew (`EngineeringPlannerCrew`)
  - Domain crews: `research`, `creative` (public examples)
  - `CodeExecutorTool` — bridge from CrewAI to claude-max-proxy
  - `router.py` — routes `auto`-type tasks to the right crew
  - `crews/private/` — gitignored directory for your own private crews
- Adds host-side runners:
  - `.claude/scripts/engineering-loop.sh` (autonomous task driver)
  - `.claude/scripts/crewai-local-workflow.sh` (manual planner wrapper)

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force --bootstrap-linux --with-crewai
```

With OpenClaw (claude-max-proxy):

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force --bootstrap-linux --with-openclaw --with-crewai
```

## Initial Setup

```bash
cd .crewai
cp .env.example .env
# Edit .env — set proxy keys, verify CLAUDE_MAX_PROXY_URL
uv sync
```

## Task File Format

Task files live in `bin/` (or any directory). The driver scans all `*.md` files
in the directory you point it at.

```markdown
## Task: <slug>
**Status:** pending
**Type:** coding          # optional; defaults to "coding"
**Branch:** feat/<slug>   # optional; only used for coding tasks

<free-form task description, acceptance criteria, context>

---
```

**Type values:**

| Type | Engine | Output |
|------|--------|--------|
| `coding` (default) | claude-max-proxy | git commit on branch |
| `research` | CrewAI ResearchCrew (Codex) | `bin/outputs/<slug>/result.md` |
| `creative` | CrewAI CreativeCrew (Codex) | `bin/outputs/<slug>/result.md` |
| `auto` | Codex classifies → dispatches | `bin/outputs/<slug>/result.md` |
| `<custom>` | Your private crew | `bin/outputs/<slug>/result.md` |

**Status values:** `pending` | `in-progress` | `done` | `failed`

## Running the Engineering Loop

```bash
# Show help
bash .claude/scripts/engineering-loop.sh --help

# Dry-run (parse and print only — no execution)
bash .claude/scripts/engineering-loop.sh --dry-run bin/

# Live run on all *.md files in bin/
bash .claude/scripts/engineering-loop.sh bin/

# With CrewAI planner PRDs for coding tasks
bash .claude/scripts/engineering-loop.sh --use-planner bin/

# Single file
bash .claude/scripts/engineering-loop.sh bin/tasks.md

# With a custom workspace
bash .claude/scripts/engineering-loop.sh --workspace /opt/repos/myrepo bin/
```

Per coding task, the driver:

1. Marks the task `in-progress` in the tasks file.
2. Checks out `**Branch:**` (creating it if missing).
3. If `--use-planner`, runs the CrewAI engineering planner to generate a PRD.
4. Calls `claude-max-proxy` HTTP API with the task + PRD prompt.
5. Runs the detected test command (`make test`, `npm test`, `pytest`, `cargo test`, `go test ./...`).
6. On test failure, retries up to `--max-retries` times with the prior output attached.
7. Marks `done` (tests pass) or `failed` (retries exhausted or agent output `<promise>FAILED: ...</promise>`).

Per non-coding task, the driver:

1. Marks the task `in-progress`.
2. Calls `uv run python -m <pkg>.main --type <type> --task "<description>"`.
3. The router dispatches to the matching crew (Codex via CLIProxyAPI).
4. Writes output to `bin/outputs/<slug>/result.md`.
5. Marks `done` or `failed`.

Make-target shortcuts:

```bash
make engineering-loop ARGS="--use-planner bin/"
make engineering-loop-dry TASKS_FILE=bin/
```

## Adding Private Crews

Private crews live in `.crewai/crews/private/` — this directory is gitignored.
**Nothing you put there is ever committed to the public repo.**

### Step 1 — Create your crew file

```python
# .crewai/crews/private/my_crew.py

CREW_NAME = "my-crew"   # routing key used in **Type:** field

def run(task_description: str, **kwargs) -> str:
    # build your CrewAI crew here
    from crewai import Agent, Crew, LLM, Process, Task
    import os

    llm = LLM(
        model=os.getenv("ENGINEERING_MODEL", "gpt-5.3-codex"),
        base_url=os.getenv("OPENAI_BASE_URL", "http://127.0.0.1:8317/v1"),
        api_key=os.getenv("OPENAI_API_KEY", ""),
    )
    agent = Agent(role="...", goal="...", backstory="...", llm=llm)
    task = Task(description=task_description, agent=agent, expected_output="...")
    crew = Crew(agents=[agent], tasks=[task], process=Process.sequential)
    return str(crew.kickoff())
```

### Step 2 — Add a task that uses it

```markdown
## Task: my-private-task
**Status:** pending
**Type:** my-crew

Task description here.
```

The crew loader scans `private/` at startup and registers any module with a
`run()` function. See `.crewai/crews/private/README.md` for details.

## CLIProxyAPI Setup (Codex subscription)

### Step 1 — Start the proxy

```bash
make crewai-proxy-up
# or: bash .claude/scripts/crewai-cliproxyapi.sh up
```

### Step 2 — Log in to your Codex subscription (one-time)

**Device code (headless / no local browser — recommended):**

```bash
docker exec -it cliproxyapi-<project-slug> ./CLIProxyAPI -config /app/config.yaml -codex-device-login
```

**OAuth (requires a browser on the same machine):**

```bash
docker exec -it cliproxyapi-<project-slug> ./CLIProxyAPI -config /app/config.yaml -codex-login
```

The `<project-slug>` is your repo name lowercased, e.g. `cliproxyapi-claude-code-autopilot`.
Both flows write OAuth state to `cliproxyapi/auths/` (gitignored, persists across restarts).

Verify the login:

```bash
PROXY_KEY=$(grep -A1 'api-keys' .crewai/cliproxyapi/config.yaml | tail -1 | tr -d ' -"')
curl -s -H "Authorization: Bearer $PROXY_KEY" http://127.0.0.1:8317/v1/models | python3 -m json.tool | head -20
```

### Step 3 — Configure `.crewai/.env`

```bash
CREWAI_LLM_MODE=proxy
OPENAI_BASE_URL=http://127.0.0.1:8317/v1
CLI_PROXY_BASE_URL=http://127.0.0.1:8317/v1
CLI_PROXY_API_KEY=<key from .crewai/cliproxyapi/config.yaml>
OPENAI_API_KEY=<same key>
ENGINEERING_MODEL=gpt-5.3-codex

# claude-max-proxy for coding execution
CLAUDE_MAX_PROXY_URL=http://localhost:3456
ENGINEERING_CODE_MODEL=claude-opus-4-8
```

## Run Commands

### Engineering loop (recommended entry point)

```bash
# All pending tasks in bin/
bash .claude/scripts/engineering-loop.sh bin/

# With planner PRDs for coding tasks
bash .claude/scripts/engineering-loop.sh --use-planner bin/
```

### Manual planner (plan a single task, print to stdout)

```bash
cd .crewai
uv run python -m <package>.main --task "Add JWT auth to the API"
# For a non-coding task:
uv run python -m <package>.main --type research --task "Compare auth patterns"
```

The `<package>` name is in `.crewai/.package-name`.

Or use the wrapper:

```bash
bash .claude/scripts/crewai-local-workflow.sh --task "Add JWT auth"
bash .claude/scripts/crewai-local-workflow.sh --with-proxy --task "Add JWT auth"
bash .claude/scripts/crewai-local-workflow.sh --dry-run
```

## Troubleshooting

- **`uv: command not found`** — Install `uv`, then `cd .crewai && uv sync`.
- **`No LLM provider key found`** — Add keys in `.crewai/.env` or use `--dry-run`.
- **Loop reports `planner: .crewai not found`** — Drop `--use-planner` or run `bash .claude/bootstrap/crewai_setup.sh`.
- **Non-coding task fails** — Check `.claude/logs/engineering-loop.log`. Ensure CLIProxyAPI is running and Codex auth is valid.
- **Codex login error about missing config** — Always pass `-config /app/config.yaml` to the login command.
- **Wrong container name** — The container is named `cliproxyapi-<project-slug>`, not just `cliproxyapi`.
