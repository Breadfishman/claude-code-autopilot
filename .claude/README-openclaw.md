# OpenClaw Quick Reference

This repo is OpenClaw-first. These are the most useful commands and scripts after install.

## Core Commands

All commands are available as `make` targets (run from repo root with `-f Makefile.openclaw`).

Start / restart gateway:

```bash
make restart            # or: make start
```

Check status:

```bash
make status             # container status + VNC processes
make dashboard-url      # print dashboard URL with token
```

Authenticate Anthropic (Claude Max / token):

```bash
make auth-anthropic     # interactive paste-token prompt
```

Set model (example: Opus-first):

```bash
make config-set KEY=models.default VALUE=claude-max-proxy/claude-opus
make restart
```

List models:

```bash
make models
```

Run diagnostics:

```bash
make doctor
```

## Bootstrap Scripts (`.claude/bootstrap/`)

Register a repo as an OpenClaw agent (most important):

```bash
make add-agent AGENT=myproject REPO=/path/to/project
# raw: bash .claude/bootstrap/add_openclaw_agent.sh <agent-id> <repo-path>
```

Pin one agent to one Discord channel (recommended runbook):

```bash
# 1) Register agent
make add-agent AGENT=<agent-id> REPO=<repo-path>

# 2) Ensure Discord bot/channel is connected
make setup-discord

# 3) Bind channel -> agent lane
make setup-discord-scale
```

After step 3:
- in Discord channel: `/new` then `/status`
- confirm session shows `agent:<agent-id>:discord:channel:<channel-id>`

What it does:
- registers the agent in OpenClaw
- creates/updates root OpenClaw core files (`AGENTS.md`, `SOUL.md`, `TOOLS.md`, etc.)
- runs repo analysis (`TOOLS.md`, `HEARTBEAT.md`, `PROJECT.md`)
- converts Claude skills into `.openclaw/skills`
- creates Codex compatibility files (`AGENTS.md`, `.agents/skills`, `.codex/rules`)
- updates `.gitignore` for local agent/runtime files

Useful flags:

```bash
--force          # Overwrite existing persona .md files with latest templates
--no-restart     # Don't restart the gateway after registration
--skip-persona   # Don't create/update persona files
--skip-skills    # Don't create skills directory
--skip-codex     # Don't create Codex compatibility files
```

Set up Discord bot channel:

```bash
make setup-discord
# raw: bash .claude/bootstrap/openclaw_discord_setup.sh
```

Set up Discord scaling (parallel threads + channel->agent lanes):

```bash
make setup-discord-scale
# raw: bash .claude/bootstrap/openclaw_discord_scale_setup.sh
```

What it does:
- configures strict Discord allowlist (guild + user + allowed channels)
- binds channels to specific agents (lane routing)
- sets `agents.defaults.maxConcurrent`
- keeps thread-per-task workflow for parallel runs in one channel
- avoids duplicate lane entries for the same channel (parallelism comes from threads)

Run repo analysis manually:

```bash
bash .claude/bootstrap/analyze_repo.sh <repo-path>
bash .claude/bootstrap/analyze_repo.sh <repo-path> --deep
```

Notes:
- `analyze_repo.sh` detects build, test, local run, and confirm/smoke-check commands from common files (Makefile, package.json, pyproject, go.mod, Cargo.toml, docker-compose).
- `--deep` generates `PROJECT.md` and now uses a timeout if `timeout` is available.

## Discord Notes (OpenClaw 2026.2.x)

- Prefer slash commands in Discord: `/status`, `/help`, `/new`
- `!status` / `!ask` may not be built-in on newer OpenClaw versions
- DM pairing and server-channel authorization are separate
- Server channels may require allowlist entries for:
  - guild ID
  - channel ID
  - your Discord user ID
- `commands.bash=true` is only needed if you want shell passthrough (`!<cmd>` / `/bash`)

## Hook Systems (Two Kinds)

- `.claude/hooks/*` = Claude Code hooks (prompt/tool guardrails, logging)
- `openclaw hooks ...` = OpenClaw gateway plugin hooks (runtime features)

The setup script enables recommended OpenClaw plugin hooks when the version supports them:
- `bootstrap-extra-files`
- `session-memory`
- `command-logger`

## Tailscale / Remote Dashboard

- Preferred: Tailscale Serve (HTTPS) + loopback gateway
- If setup cannot enable Serve automatically:

```bash
sudo tailscale set --operator=$USER
tailscale serve --bg http://127.0.0.1:18789
```

- First secure UI connect may require device pairing (run inside container):

```bash
make shell
# then: openclaw devices list
# then: openclaw devices approve <requestId>
```

## Updating Existing Repos

Refresh `.claude/` only (no OpenClaw bootstrap rerun):

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force --bootstrap-linux
```

Re-run OpenClaw bootstrap / regenerate `.openclaw/*`:

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force --bootstrap-linux --with-openclaw
```

## Updating Agent Persona Files (AGENTS.md, SOUL.md, etc.)

When you update templates in `claude-code-autopilot` and want agents to pick up the changes:

**Step 1: Pull latest templates + re-register agent with `--force`:**

```bash
# From the claude-code-autopilot repo (or after install --force)
bash .claude/bootstrap/add_openclaw_agent.sh <agent-id> <repo-path> --force
```

This overwrites AGENTS.md, SOUL.md, USER.md, IDENTITY.md with the latest templates.
TOOLS.md, HEARTBEAT.md, PROJECT.md are NOT overwritten (they are auto-generated by `analyze_repo.sh`).

**Step 2: Restart the gateway:**

```bash
make restart
```

**Step 3: Start a new session** (`/new` in Discord).

The agent will load the updated AGENTS.md on the next session start.

**Deep scan timeout:** If `PROJECT.md` generation times out during registration, re-run with no timeout:

```bash
CLAUDE_DEEP_WAIT_FOR_COMPLETION=1 bash .claude/bootstrap/analyze_repo.sh <repo-path> --deep
```

**Quick reference — full agent refresh:**

```bash
# 1. Pull latest templates
cd /path/to/claude-code-autopilot
git pull

# 2. Re-register agent with --force (overwrites persona .md files)
bash .claude/bootstrap/add_openclaw_agent.sh <agent-id> <repo-path> --force

# 3. Re-run deep scan if PROJECT.md was placeholder
CLAUDE_DEEP_WAIT_FOR_COMPLETION=1 bash .claude/bootstrap/analyze_repo.sh <repo-path> --deep

# 4. Restart gateway + new session
make restart
# Then /new in Discord
```

## Browser

OpenClaw uses its built-in managed browser (`openclaw` profile) by default. See https://docs.openclaw.ai/tools/browser
