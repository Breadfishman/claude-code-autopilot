# AGENTS.md — Claude Code Autopilot Kit

> Follows the [AGENTS.md](https://agents.md/) open standard so any agent (Claude Code,
> OpenAI Codex, Cursor, Copilot, Gemini CLI, …) gets the same guidance on task start.
> This repository is OpenClaw-first but supports OpenAI Codex workflows.

## Project Overview

A portable `.claude/` bundle that turns Claude Code into a self-verifying engineering
loop (fix → build → run → test → confirm → commit → report), plus optional OpenClaw
(Discord/browser/remote) and CrewAI (planner crew) Docker stacks. It is **a kit that
installs into other repos**, not a buildable application — there is no root
`package.json`/`pyproject.toml`. Hooks are Python 3 (stdlib only), bootstrap/scripts are
bash, agents/skills are Markdown with YAML frontmatter.

## Setup, Build & Validation

Working **on this kit itself**:

```bash
# Validate the bundle (dir structure, settings JSON, hook syntax, agent frontmatter)
bash .claude/extras/doctor.sh

# Functional-test the bash safety guard (allowed vs blocked patterns)
python3 .claude/scripts/test_guard.py

# Re-install / refresh the kit into a target repo (--force preserves logs/ + vendor/)
bash install.sh --repo NorkzYT/claude-code-autopilot --ref main --force
```

There is no compile step. "Build/Test" for changes here means: run `doctor.sh`, run
`test_guard.py` if you touched `hooks/guard_*.py`, and confirm hooks still read stdin
JSON and exit with the right code. When the kit is **installed in a target repo**, the
build/test/run commands come from that repo's generated `TOOLS.md` (see the Task
Completion Protocol below).

## Code Style & Conventions

- **Python hooks:** read a JSON event from stdin; signal via exit code (`0` allow, `2`
  block) plus stdout (JSON for Stop/decision hooks, plain text for `UserPromptSubmit`
  injection). Keep them fast — hooks have per-call timeouts. Stdlib only; no new deps.
- **Shell:** bash, idempotent, fail-fast. Match the style of neighbouring scripts.
- **Agents/skills:** Markdown with YAML frontmatter (`name`, `description`, `model`,
  `tools`). Mirror the structure of existing files in `.claude/agents/` and `.claude/skills/`.
- **Smallest change that satisfies the task** — no drive-by refactors (the Constitution
  rule in `.claude/CLAUDE.md`).
- **Commits:** [Conventional Commits](https://www.conventionalcommits.org/)
  (`type(scope): subject`, scopes like `openclaw`/`crewai`/`install`). Work on a feature
  branch, **never** `main`. **Never** add `Co-Authored-By` trailers — the generated
  `.git/hooks/commit-msg` blocks them.

## Primary Policy Files

Read and follow these files in order:

1. `.claude/CLAUDE.md`
2. `.claude/templates/AGENTS.md`
3. `.claude/templates/agent-persona/AGENTS.md.tmpl`

## Task Completion Protocol

For EVERY bug fix or feature:
1. **Understand** — Read PROJECT.md, relevant source files
2. **Fix** — Make the code change
3. **Build** — Run build command from TOOLS.md
4. **Run Local** — Start or reload the local stack only (e.g. `yarn dev`, `make up`, `docker compose up`)
5. **Test** — Run test command from TOOLS.md
6. **Confirm** — Verify the changed flow works locally (browser-check if UI change via CDP)
7. **Commit** — On feature branch, not main
8. **Report** — Summary of what changed, what was tested

Do not mark tasks complete after code-only changes.

## Timed Follow-Ups (OpenClaw)

- Never say "I will check back in X minutes/hours" unless you create a real OpenClaw cron job first.
- Use `/recheckin <delay> <task>` in Discord/OpenClaw channels to make timed follow-ups real.
- When a timed follow-up is scheduled, include the cron `jobId` (or say the CLI did not return one) in the reply.
- If scheduling fails, do not promise a timed callback. Ask the user to ping you later or keep monitoring synchronously.
- Strong rule: timed promise language is forbidden unless `/recheckin` succeeded in the same turn.
- Forbidden without cron success: "I'll check back in X", "give me X minutes and I'll re-check", "I'll report back in X".

## Cost-Optimized Routing

- Claude/OpenClaw: use Sonnet first for plan + direct execution.
- Escalate to Opus/autopilot only for complex multi-file/architectural tasks.
- Codex: follow the same plan-first/direct-first policy and keep browser verification explicit.

## Shared Skills and Guardrails

- Skills source: `.claude/skills/` and generated `.openclaw/skills/`
- Codex repo skills path: `.agents/skills/` (symlink to `.openclaw/skills/`)
- Codex rule file: `.codex/rules/default.rules`
- Recommended local Codex state path: `.codex-home/` (via `ccx` alias)
- Codex compatibility templates: `.claude/templates/codex/`
- Safety hook references: `.claude/hooks/guard_bash.py`, `.claude/hooks/guard_browser.py`
- Commit trailer enforcement: generated `.git/hooks/commit-msg` blocks `Co-Authored-By`
