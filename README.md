# Claude Code Autopilot Kit (Claude + OpenClaw Engineer Workflow Kit)

A portable `.claude/` bundle for Claude Code with a staged agent workflow, safety hooks, logging, and a strict verification loop.

It also includes OpenClaw and CrewAI bootstrap scripts for remote control, browser automation, multi-agent routing, and cross-session memory.

This repo is built to support a full local engineer workflow:

- fix
- build
- run local stack (`yarn dev`, `make up`, `docker compose up`)
- test
- confirm
- commit and report

The goal is not code-only output. The goal is a repeatable engineering loop.

Once installed, Claude can auto-route substantive tasks into the autopilot pipeline and use OpenClaw when you enable it.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force --bootstrap-linux
```

After install, you'll see your **ntfy.sh subscription URL** — subscribe to get notified when Claude needs your attention.

Then restart Claude Code to load the new configuration.

> **Note:** Run Claude Code as a **non-root user**. The kit's hooks, logs, and VS Code integration are designed for regular user accounts. If using VS Code Remote (SSH/Tailscale), ensure you attach as the same user that runs Claude.

### Install With OpenClaw (Discord/browser/multi-agent)

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force --bootstrap-linux --with-openclaw
```

This Docker/OpenClaw install defaults to `/opt/openclaw-home` when `--dest` is omitted, regardless of the directory where you ran the command.

### OpenClaw Docker Quickstart

For a new user who wants Docker-only OpenClaw with access to repos under `/opt/repos`:

1. Install with `--with-openclaw`
2. Copy the env template:

```bash
cp /opt/openclaw-home/.env.example /opt/openclaw-home/.env
```

3. Edit `.env` and set:
   - `HOST_REPOS_DIR=/opt/repos`
   - `GIT_AUTHOR_NAME`
   - `GIT_AUTHOR_EMAIL`
   - `GIT_COMMITTER_NAME`
   - `GIT_COMMITTER_EMAIL`

Recommended defaults:

- `OPENCLAW_MODEL_PRIMARY=anthropic/claude-sonnet-4-6`
- `OPENCLAW_THINKING_DEFAULT=high`

Optional auth envs:

- `ANTHROPIC_API_KEY`
- `OPENAI_API_KEY`
- `OPENCLAW_ANTHROPIC_SETUP_TOKEN`

4. Put the repos you want OpenClaw to access under `/opt/repos`
5. Start the Docker stack after `.env` is ready:

```bash
cd /opt/openclaw-home
openclaw up
```

6. Authenticate providers inside the container wrapper:

**Claude Max subscription (via claude-max-proxy)** — generate a long-lived
token once, wire it into the container via env, forget for ~1 year:

```bash
# 1. Generate an OAuth token inside the proxy container. Follow the URL,
#    sign in with your Claude Max account, paste the `sk-ant-oat01-…`
#    token back into the terminal.
docker exec -it claude-max-proxy claude setup-token

# 2. Put the token into /opt/openclaw-home/.env and recreate the proxy.
echo "CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-<paste-your-token>" \
  >> /opt/openclaw-home/.env
chmod 600 /opt/openclaw-home/.env
cd /opt/openclaw-home
docker compose -f docker-compose.openclaw.yml up -d --force-recreate claude-max-proxy

# 3. Verify.
docker exec claude-max-proxy claude auth status
# → {"loggedIn": true, "authMethod": "oauth_token"}
```

The proxy has its own isolated `~/.claude` volume inside the container;
it does NOT share credentials with any host-side `claude` CLI. See
`docs/openclaw.md` for the full proxy + OpenClaw model config.

**Anthropic direct API (optional)** — only if you want OpenClaw to call
Anthropic without the proxy:

```bash
openclaw models auth paste-token --provider anthropic
```

**OpenAI subscription:**

```bash
openclaw models auth login --provider openai-codex
```

7. Verify the stack:

```bash
openclaw status
openclaw logs
```

8. Open the browser viewer when manual login or 2FA is needed:

```bash
openclaw viewer-url
```

9. Register mounted repos as agents when needed:

```bash
openclaw agents add my-app --workspace /opt/repos/my-app --non-interactive
```

What this means:

- OpenClaw runs in Docker, not on the host
- the host `openclaw` command is a wrapper into the container
- the default control directory is `/opt/openclaw-home` unless you override it with `--dest`
- `/opt/repos` is mounted read/write into the gateway container
- `~/.openclaw` on the host is bind-mounted into the container and reused for state
- if you ever need a different host state path, set `OPENCLAW_HOST_STATE_DIR` explicitly

### Install With CrewAI (engineering planner crew)

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force --bootstrap-linux --with-crewai
```

### Install With OpenClaw + CrewAI Together

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force --bootstrap-linux --with-openclaw --with-crewai
```

## Start Here

Pick one path:

1. Claude Code only (local terminal workflow): use the Quick Install command above
2. Claude Code + OpenClaw (Discord, browser, remote control): add `--with-openclaw`
3. Claude Code + CrewAI (crew-based domain teams): add `--with-crewai`
4. Claude Code + OpenClaw + CrewAI: use both flags in one command
5. Refresh an existing repo: re-run the install command with `--force`

What this kit covers:

- Claude Code hooks and guardrails (`.claude/hooks/*`)
- staged agent workflow (autopilot, triage, fixer, closer)
- OpenClaw gateway, Discord, browser, and agent bootstrap scripts
- CrewAI bootstrap with an engineering planner crew scaffold under `.crewai/`
- Codex compatibility layer (`AGENTS.md`, `.agents/skills`, `.codex/rules`)

Then read:

- `.claude/README-openclaw.md` for OpenClaw scripts and common commands
- `.claude/docs/openclaw-integration.md` for full setup and troubleshooting
- `.claude/docs/openclaw-remote-commands.md` for Discord use (slash commands, pairing, allowlists, bindings)
- `docs/crewai.md` for CrewAI setup, execution, and artifact workflow

---

## Terminal Names & `cca` Alias

Each Claude Code session gets a **random memorable name** (e.g., `cosmic-penguin`, `thunder-falcon`) so you can easily identify multiple terminals. The name appears in:

- The **terminal tab title**
- **Notification messages** (so you know which terminal needs attention)
- A local identity file at `.claude/terminal-identity.local.json`

Launch Claude with the **`cca` alias** (added to your shell during install):

```bash
cca
```

This runs `claude --dangerously-skip-permissions` with automatic terminal naming. Equivalent to:

```bash
.claude/bin/claude-named --dangerously-skip-permissions
```

> **Note:** After install, open a new shell or run `source ~/.bashrc` (or `~/.zshrc`) to activate the `cca` alias.

---

## How It Works

After installation, the kit automatically:

1. **Injects autopilot** — A hook detects substantive prompts and triggers the autopilot agent
2. **Guards dangerous operations** — Blocks `rm -rf`, `sudo`, `curl|bash`, auto-commits, etc.
3. **Protects sensitive files** — Blocks edits to `.env`, secrets, certs, prod configs
4. **Auto-formats code** — Runs Prettier/Black on edited files when configured
5. **Logs everything** — Prompts, commands, and responses go to `.claude/logs/`

If you install with OpenClaw, it also:

6. **Adds gateway tooling** — Remote access, channel routing, and session management
7. **Adds browser tooling** — OpenClaw-managed browser for local UI verification and CDP flows
8. **Bootstraps repo agents** — Generates root OpenClaw core files, `.openclaw/` runtime state, skills, and compatibility files for multi-repo work

If you install with CrewAI, it also:

9. **Scaffolds a CrewAI workspace** — Generates `.crewai/` with agents/tasks config and Python entrypoints
10. **Creates growth artifacts** — Produces go-to-market, experiment backlog, and weekly ops outputs under `.crewai/reports/`
11. **Adds a local runner** — `.claude/scripts/crewai-local-workflow.sh` for CLI-driven automation
12. **Supports local proxy mode** — `.claude/scripts/crewai-cliproxyapi.sh` to run Dockerized CLIProxyAPI for subscription-backed routing

---

## Usage Guide

### Ask Naturally

For most tasks, simply describe what you want:

```
Add a logout button to the navbar that clears the session and redirects to /login
```

The autopilot agent automatically:

- Explores the codebase to understand the structure
- Plans the implementation
- Makes the changes
- Verifies the result
- Reviews for issues

### Structured Prompts (For Complex Tasks)

For complex or multi-step tasks, use this structure for best results:

```
1) GOAL
- Add user authentication with JWT tokens

2) DEFINITION OF DONE
- [ ] Login endpoint returns JWT on valid credentials
- [ ] Protected routes reject requests without valid token
- [ ] Tests pass

3) CONTEXT
- Using Express.js backend in /src/api
- User model already exists at /src/models/user.js

4) DETAILS
- Use bcrypt for password hashing
- Token expiry: 24 hours
```

### Skip Autopilot for Simple Questions

Simple questions bypass autopilot automatically:

```
What files handle authentication?
How does the routing work?
Explain the database schema
```

---

## Available Agents

| Agent                     | Use Case                                                    | How to Invoke                            |
| ------------------------- | ----------------------------------------------------------- | ---------------------------------------- |
| **autopilot**             | Full task execution (explore → implement → verify → review) | Automatic for substantive prompts        |
| **autopilot-fixer**       | Fix incomplete/broken autopilot output                      | `Use the autopilot-fixer subagent`       |
| **closer**                | Final verification + PR notes (no new code)                 | `Use the closer subagent`                |
| **triage**                | Debug failures (repro → diagnose → fix)                     | `Use the triage subagent`                |
| **parallel-orchestrator** | Multi-part tasks needing parallel work                      | `Use the parallel-orchestrator subagent` |

### When Autopilot Doesn't Finish

```
Use the autopilot-fixer subagent.

Original Task:
<<<
[paste your original prompt]
>>>

What's Still Wrong:
<<<
[paste error messages or describe the issue]
>>>
```

### Final Verification Before PR

```
Use the closer subagent.

Acceptance Criteria:
<<<
- [ ] Feature works as described
- [ ] Tests pass
- [ ] No console errors
>>>
```

---

## Documentation

The README is the fast path. Detailed guides live in `docs/*.md` and `.claude/docs/*`.

### Core docs (`docs/*.md`)

- `docs/README.md` — documentation index
- `docs/install.md` — install modes, updates, flags, git hygiene
- `docs/workflow.md` — session persistence, notifications, guardrails, customization, plan mode
- `docs/editor.md` — external editor (`Ctrl+G`) and VS Code remote setup
- `docs/troubleshooting.md` — common issues and validation commands
- `docs/openclaw.md` — OpenClaw quick guide and hook model overview
- `docs/crewai.md` — CrewAI setup, engineering planner crew, and engineering-loop driver
- `docs/docker-openclaw-crewai.md` — separate compose files for OpenClaw-only or CrewAI-only container stacks
- `docs/openclaw-plugin-hooks.md` — plugin hooks and wrapper design for local workflow automation
- `docs/roadmap.md` — roadmap for full engineer workflow enforcement

### OpenClaw docs (repo-local references)

- `.claude/README-openclaw.md` — operator quick reference
- `.claude/docs/openclaw-integration.md` — full setup and operations guide
- `.claude/docs/openclaw-commands.md` — CLI and slash command reference
- `.claude/docs/openclaw-remote-commands.md` — Discord pairing, allowlists, bindings, and channel routing

### Quick reminders

- Use slash commands in Discord first: `/status`, `/help`, `/new`
- `commands.bash=true` is only needed for shell passthrough (`!<cmd>` / `/bash`)
- OpenClaw plugin hooks and `.claude/hooks/*` are separate systems

---

## Core Principles

1. **Smallest change that satisfies the task** — No drive-by refactors
2. **Discovery first** — Search and read before deciding
3. **Always verify** — Run tests/lint/build or provide manual steps
4. **One bounded retry** — Triage → patch → verify once if it fails
5. **No destructive commands** — Unless explicitly approved

## Contributors

We're happy to welcome [@Breadfishman](https://github.com/Breadfishman)'s contributions to our work this project. They collaborated closely on the project under our shared account.
