# Roadmap: Full Engineer Workflow Kit

This roadmap tracks the move from a prompt-guided agent kit to a repeatable local engineering workflow system.

The target workflow is:

1. Fix
2. Build
3. Run local stack
4. Test
5. Confirm locally
6. Commit and report
7. Move to next bug

This means local developer workflows only. It does not mean staging or production deploys.

## Current State (Implemented)

- Claude Code hooks for safety, logging, and formatting (`.claude/hooks/*`)
- Staged agent workflow (autopilot, triage, fixer, closer)
- OpenClaw setup and agent bootstrap scripts
- OpenClaw Discord setup wizard with secure guild/channel/user allowlists
- OpenClaw-managed browser for CDP and local UI checks
- Generated root `TOOLS.md` with detected build/test/local-run/confirm commands
- Generated root `HEARTBEAT.md` and `PROJECT.md` (via `analyze_repo.sh`, `--deep` for `PROJECT.md`)
- Opus-first routing with Sonnet downshift for simple tasks
- Commit trailer blocking (`Co-Authored-By`)
- Real local workflow wrapper script (`.claude/scripts/openclaw-local-workflow.sh`)
- Real local workflow wrapper script for build/test/confirm automation

## Gaps (Not Fully Enforced Yet)

- Hard gate that requires build + local-run + test + confirm before "done"
- Structured evidence output (build log summary, test summary, smoke-check result)
- Policy that blocks PR creation when local verification steps are missing

## Next Steps (Recommended)

### 1) Add strict completion/report gate (highest impact)

Use plugin hooks to:

- reject completion/reporting when required workflow evidence is missing
- require a fresh `workflow-report.local.json` before a "done" response pattern is allowed
- optionally require all four steps to be `passed`

The wrapper and plugin commands already exist. The missing piece is strict gating.

### 2) Improve workflow evidence output

Require a standard report with fields like:

- Build: pass/fail
- Local run: command used
- Test: pass/fail and counts
- Confirm: what was checked locally
- Files changed
- Next bug

### 3) Add per-repo command overrides

Keep `analyze_repo.sh` detection as the default and support project overrides in root `TOOLS.md` where detection is not enough.

### 4) Add higher-level workflow commands (optional)

The core wrapper is implemented. Add task-oriented wrappers only if needed, for example:

- `/localfix`
- `/verify-local`
- `/next-bug`

These should call the same local workflow runner and produce the same report shape.

## Design Rules

- Prefer local commands (`yarn dev`, `make up`, `docker compose up`) over staging/prod actions
- Keep defaults safe (`commands.bash=false`, allowlists on Discord)
- Use slash commands first in Discord
- Keep automation idempotent and version-tolerant
- Treat root core files as canonical (`AGENTS.md`, `TOOLS.md`, `PROJECT.md`, etc.)
- Use `.openclaw/` for runtime state, skills, sessions, memory logs, and local reports
