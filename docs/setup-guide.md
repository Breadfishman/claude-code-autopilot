# Full Setup Guide: OpenClaw + Multi-Crew AI Workforce

> **This is the single entry-point guide.** Follow it top to bottom on a fresh dev machine.

## Architecture (How the Parts Connect)

```
You (Discord)
     │
     ▼
OpenClaw Gateway  ← Docker container
     │  Claude Code agent receives your message,
     │  executes tools inside the container,
     │  can reach the host at host.docker.internal
     │
     ├─ Coding task ─────────────────────────────────────────────────────────────┐
     │    Agent calls claude-max-proxy directly                                    │
     │    POST http://claude-max-proxy:3456/v1/chat/completions                   │
     │    (same Docker network — no host needed)                                  │
     │    Claude Code runs: edits files, runs tests, commits                      │
     │    → result posted back to Discord                                          │
     │                                                                             │
     └─ Research / creative / custom task ───────────────────────────────────────┐ │
          Agent calls the CrewAI HTTP bridge on the HOST                          │ │
          POST http://host.docker.internal:9317/run                               │ │
               │                                                                  │ │
               ▼  (on the HOST machine)                                           │ │
          CrewAI server  (.crewai/ — started with: make crewai-serve)            │ │
               │  loads .crewai/.env, router.py, crews/                           │ │
               │                                                                  │ │
               ├── research  → ResearchCrew  ──┐                                 │ │
               ├── creative  → CreativeCrew  ──┤→ POST http://127.0.0.1:8317/v1  │ │
               ├── auto      → Codex classifies┘   CLIProxyAPI (Codex)           │ │
               └── <custom>  → .crewai/crews/private/<name>.py                   │ │
                                                                                  │ │
          → result returned to OpenClaw → posted to Discord                      ◄─┘
```

**Three services, two subscriptions, zero API costs:**

| Service | Where | Port | Subscription | Used for |
|---------|-------|------|-------------|----------|
| OpenClaw gateway | Docker | 18789 | Claude Max (via proxy) | Discord bot + agent |
| claude-max-proxy | Docker | 3456 | Claude Max | Coding execution |
| CLIProxyAPI | Docker | 8317 | Codex / ChatGPT Plus | All thinking + non-coding |
| **CrewAI server** | **HOST** | **9317** | — | **Bridges OpenClaw → Codex crews** |

The CrewAI server is the missing link. It runs on the HOST (where `uv` and Python are installed), listens on port 9317, and OpenClaw reaches it via `http://host.docker.internal:9317`.

---

## Part 1 — Prerequisites Check

Verify all services are alive:

```bash
# OpenClaw
openclaw status

# claude-max-proxy (coding engine)
curl -s http://localhost:3456/health | python3 -c "import sys,json; d=json.load(sys.stdin); print('claude-max-proxy logged in:', d.get('auth',{}).get('loggedIn'))"
# Expected: claude-max-proxy logged in: True

# CLIProxyAPI (Codex thinking engine)
curl -s http://127.0.0.1:8317/v1/models | python3 -m json.tool | head -8
# Expected: list of model objects including a gpt-5.x-codex entry
```

Fixes if any fail:
- OpenClaw not responding → `make start` in `/opt/openclaw-home`
- claude-max-proxy: see `docs/openclaw.md` § Claude Max Proxy Setup
- CLIProxyAPI not running → `make crewai-proxy-up` in this repo
- CLIProxyAPI logged out → `docker exec -it cliproxyapi-claude-code-autopilot ./CLIProxyAPI -config /app/config.yaml -codex-device-login`

---

## Part 2 — Bootstrap the Multi-Crew Files (One-time)

Your `.crewai/` was created with older templates. Re-run the bootstrap — it skips existing files and only creates missing ones:

```bash
# From the repo root:
bash .claude/bootstrap/crewai_setup.sh /opt/repos/claude-code-autopilot
```

You should see `[SKIP]` for existing files and `==> Created` for new ones:
```
==> Created src/<pkg>/router.py
==> Created src/<pkg>/tools/__init__.py
==> Created src/<pkg>/tools/code_executor.py
==> Created src/<pkg>/crews/__init__.py
==> Created src/<pkg>/crews/research.py
==> Created src/<pkg>/crews/creative.py
==> Created src/<pkg>/server.py
    crews/private/README.md
```

Sync dependencies:
```bash
cd .crewai && uv sync && cd ..
```

Verify key files exist:
```bash
ls .crewai/src/*/router.py .crewai/src/*/server.py .crewai/src/*/crews/ .crewai/crews/private/
```

---

## Part 3 — Configure `.crewai/.env`

Edit `.crewai/.env` to have entries for both engines. If starting fresh:
```bash
cp .crewai/.env.example .crewai/.env
```

Minimum required:
```dotenv
# Codex (CLIProxyAPI) — all thinking and non-coding tasks
CREWAI_LLM_MODE=proxy
OPENAI_BASE_URL=http://127.0.0.1:8317/v1
OPENAI_API_BASE=http://127.0.0.1:8317/v1
CLI_PROXY_BASE_URL=http://127.0.0.1:8317/v1
CLI_PROXY_API_KEY=<key from .crewai/cliproxyapi/config.yaml>
OPENAI_API_KEY=<same key>
ENGINEERING_MODEL=gpt-5.3-codex

# claude-max-proxy — coding execution only
CLAUDE_MAX_PROXY_URL=http://localhost:3456
ENGINEERING_CODE_MODEL=claude-opus-4-7
```

Get your Codex proxy key:
```bash
grep -A5 'api-keys' .crewai/cliproxyapi/config.yaml
```

Smoke test:
```bash
cd .crewai
uv run python -m "$(cat .package-name)".main --type research --task "test" --dry-run
# Expected: Dry run — inputs for router.dispatch(type='research')
```

---

## Part 4 — Start the CrewAI HTTP Bridge

This is the piece that connects OpenClaw (Docker) to your Codex crews (host).

```bash
# Start in the foreground (Ctrl+C to stop):
make crewai-serve WORKSPACE=/opt/repos/claude-code-autopilot

# Or start in the background:
make crewai-serve-bg WORKSPACE=/opt/repos/claude-code-autopilot
# Logs: tail -f .claude/logs/crewai-server.log
```

Verify it's reachable from the HOST:
```bash
curl -s http://localhost:9317/health
# → {"status": "ok", "server": "crewai-api"}

curl -s http://localhost:9317/crews
# → {"crews": ["creative", "research"]}  (+ any private crews)
```

Keep this running whenever you use non-coding tasks from Discord.

**Auto-start on boot** (optional):
```bash
# Add to crontab: @reboot starts it after each machine restart
crontab -e
# Add this line:
# @reboot cd /opt/repos/claude-code-autopilot && make crewai-serve-bg WORKSPACE=/opt/repos/claude-code-autopilot
```

---

## Part 5 — Discord as the Interface

### For coding tasks (already works)

Just tell OpenClaw what to do. The agent uses Claude Code tools directly and calls `claude-max-proxy` in the same Docker network:

```
Add JWT authentication to the /opt/repos/myrepo API
```

The agent handles it end-to-end (plans, edits code, runs tests, commits) and reports back.

### For research / creative / non-coding tasks

The agent calls the CrewAI HTTP bridge you started in Part 4:

```
Research the best database for a real-time multiplayer game — give me a comparison table
```

```
Use the research crew to compare event sourcing vs traditional CRUD for an audit log system
```

Internally, the agent runs:
```bash
curl -s --max-time 600 \
  -X POST http://host.docker.internal:9317/run \
  -H "Content-Type: application/json" \
  -d '{"type": "research", "task": "Compare event sourcing vs CRUD for audit logs"}'
```

The CrewAI server dispatches to the ResearchCrew (Codex), returns the result, and the agent posts it to Discord.

**If you want the agent to route automatically** without you specifying the type, say:
```
[auto] Compare event sourcing vs CRUD for audit logs in a financial system
```
The `auto` type tells the router to ask Codex to classify the task and dispatch accordingly.

### Bind a Discord channel to this repo (if not already done)

```bash
# Register this repo as an OpenClaw agent
make add-agent AGENT=autopilot REPO=/opt/repos/claude-code-autopilot

# Configure Discord bot
bash .claude/bootstrap/openclaw_discord_setup.sh

# Bind channel → agent, set concurrency
bash .claude/bootstrap/openclaw_discord_scale_setup.sh
```

In Discord:
```
/new      ← start a fresh session on this repo agent
/status   ← confirm: Session: agent:autopilot:discord:channel:<id>
```

### Universal workspace anchoring (prevents agents from losing their repo)

After long sessions, OpenClaw compacts the conversation and agents can lose
track of their workspace (e.g. end up in `/app` instead of `/opt/repos/Kairo`).
Enable the workspace-anchor hooks so this can't happen, regardless of how many
repos or agents you add later:

```bash
make setup-workspace-anchors
```

This enables two OpenClaw hooks:
- `session-memory` — preserves context across `/new` and `/reset`
- `bootstrap-extra-files` — re-injects `AGENTS.md` and `.claude/CLAUDE.md` from
  the workspace at every session start

**This is a one-time setup.** It's also called automatically by
`bash .claude/bootstrap/openclaw_setup.sh` for new installs, so this step is
only needed on existing installs that pre-date the hook configuration.

For each new repo you add later, drop a minimal `AGENTS.md` at the repo root
(`# RepoName — Workspace: /opt/repos/<repo>`). The hook auto-injects it for
that repo's agent — no per-agent config required.

---

## Part 6 — Batch Task Queue (Engineering Loop)

For running many tasks unattended while you're away:

### Create task files in `bin/`

```markdown
# bin/my-tasks.md

## Task: add-rate-limiting
**Status:** pending
**Type:** coding
**Branch:** feat/add-rate-limiting

Add 100 req/min rate limiting per IP. Return 429 with Retry-After header.
Allowlist /health. Add tests.

---

## Task: research-auth-patterns
**Status:** pending
**Type:** research

Compare JWT vs session tokens vs API keys for a B2B SaaS product. Include
security trade-offs, operational complexity, and a recommendation.

---
```

### Run from terminal

```bash
# Dry-run first to verify parsing
bash .claude/scripts/engineering-loop.sh --dry-run bin/my-tasks.md

# Execute all pending tasks
bash .claude/scripts/engineering-loop.sh bin/my-tasks.md

# All *.md files in bin/ at once
bash .claude/scripts/engineering-loop.sh bin/

# With Codex-generated PRD for each coding task
bash .claude/scripts/engineering-loop.sh --use-planner bin/
```

### Run from Discord (tell the agent)

```
Run the engineering loop on bin/ in /opt/repos/claude-code-autopilot
```

The agent runs `bash .claude/scripts/engineering-loop.sh /opt/repos/claude-code-autopilot/bin/` and posts the summary when done.

### Results

- **Coding tasks** → committed to the branch in `**Branch:**`
- **Non-coding tasks** → `bin/outputs/<slug>/result.md`
- **Log** → `.claude/logs/engineering-loop.log`

---

## Part 7 — Private Crews (Yours, Never Committed)

`.crewai/crews/private/` is gitignored. Put your crew `.py` files there.

```python
# .crewai/crews/private/game_design.py

CREW_NAME = "game-design"

def run(task_description: str, **kwargs) -> str:
    import os
    from crewai import Agent, Crew, LLM, Process, Task

    llm = LLM(
        model=os.getenv("ENGINEERING_MODEL", "gpt-5.3-codex"),
        base_url=os.getenv("OPENAI_BASE_URL", "http://127.0.0.1:8317/v1"),
        api_key=os.getenv("OPENAI_API_KEY", ""),
    )
    agent = Agent(
        role="Game Designer",
        goal="Design engaging, balanced game mechanics and systems.",
        backstory="Senior game designer expert in game loops, economy, and player psychology.",
        llm=llm,
        verbose=True,
    )
    task = Task(
        description=task_description,
        agent=agent,
        expected_output="A detailed game design document with mechanics and implementation notes.",
    )
    return str(Crew(agents=[agent], tasks=[task], process=Process.sequential).kickoff())
```

Use it from Discord:
```
Design a crafting system for a survival roguelike using the game-design crew
```

Or in a task file:
```markdown
## Task: design-combat-system
**Status:** pending
**Type:** game-design

Design a turn-based combat system...
```

The crew loader auto-discovers any `.py` in `crews/private/` with a `run()` function. No registration needed. See `.crewai/crews/private/README.md` for the full interface.

Restart the CrewAI server after adding a new private crew so it reloads:
```bash
make crewai-serve-bg WORKSPACE=/opt/repos/claude-code-autopilot
```

---

## Part 8 — Task Type Reference

| `**Type:**` | Engine | Behaviour |
|-------------|--------|-----------|
| `coding` (default) | claude-max-proxy → Claude Code | Branch, test/retry, commit |
| `research` | CLIProxyAPI → ResearchCrew | → `bin/outputs/<slug>/result.md` |
| `creative` | CLIProxyAPI → CreativeCrew | → `bin/outputs/<slug>/result.md` |
| `auto` | Codex classifies → dispatches | → `bin/outputs/<slug>/result.md` |
| `<custom>` | CLIProxyAPI → private crew | → `bin/outputs/<slug>/result.md` |

---

## Quick-Reference Checklist (Daily Startup)

```bash
# 1. Verify both proxies
curl -s http://localhost:3456/health | python3 -c "import sys,json; print(json.load(sys.stdin).get('auth',{}).get('loggedIn'))"
curl -s http://127.0.0.1:8317/v1/models | python3 -m json.tool | head -5

# 2. Start the CrewAI bridge (if not auto-started)
make crewai-serve-bg WORKSPACE=/opt/repos/claude-code-autopilot
curl -s http://localhost:9317/health   # confirm it's up

# 3. In Discord: /status  ← confirm agent session is live
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `No module named <pkg>.router` | Re-run bootstrap: `bash .claude/bootstrap/crewai_setup.sh` |
| `Connection refused` on port 9317 | Start the bridge: `make crewai-serve-bg WORKSPACE=...` |
| OpenClaw can't reach port 9317 | Confirm `extra_hosts: host.docker.internal:host-gateway` is in `docker-compose.openclaw.yml` (it is by default) |
| Crew task times out | Increase `--max-time` on curl; default is 600s (10 min) |
| Wrong crew dispatched | Check `CREW_NAME` in your private crew file; use explicit `--type` instead of `auto` |
| CLIProxyAPI 401 | Re-run device login: `docker exec -it cliproxyapi-claude-code-autopilot ./CLIProxyAPI -config /app/config.yaml -codex-device-login` |
| claude-max-proxy 401 | `docker exec -it claude-max-proxy claude setup-token` in `/opt/openclaw-home` |
| `uv: command not found` | Install: `curl -LsSf https://astral.sh/uv/install.sh \| sh` then re-open shell |
| New private crew not loading | Restart the CrewAI server: `make crewai-serve-bg` |

---

## Deep-Dive References

| Topic | File |
|-------|------|
| OpenClaw full setup | `docs/openclaw.md` |
| CrewAI crews + CLIProxyAPI | `docs/crewai.md` |
| Engineering loop options | `docs/crewai.md` § Running the Engineering Loop |
| Private crews interface | `.crewai/crews/private/README.md` |
| Docker stack details | `docs/docker-openclaw-crewai.md` |
| Discord remote commands | `.claude/docs/openclaw-remote-commands.md` |
