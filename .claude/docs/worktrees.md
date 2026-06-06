# Parallel-Work Isolation with `wt` (git worktrees)

Running several Claude/agent sessions in one repo means they share one working
tree — concurrent edits, build artifacts, the git index, and dev servers all
collide. `wt` gives each session its own **git worktree + branch + isolated
runtime** so they stop clobbering each other, while sharing one `.git`.

## Quickstart

```bash
.claude/bin/wt new auth          # → ../.worktrees/<repo>/auth on branch agent/auth
cd ../.worktrees/<repo>/auth     # work here; commit on agent/auth
.claude/bin/wt list              # see all worktrees + their port offsets
.claude/bin/wt rm auth           # tear down services, remove worktree + branch
```

Tip: add an alias so it's available everywhere —
```bash
alias wt="$HOME/path/to/repo/.claude/bin/wt"   # or wherever the kit lives
```

## What it isolates (and how)

`git worktree` isolates **tracked files** for free. The hard part is the
gitignored *runtime* state a fresh worktree doesn't inherit. `wt` handles it:

| Concern | How `wt` isolates it |
|---|---|
| **Files / index / branch** | One worktree per slug at `<repo>/../.worktrees/<repo-name>/<slug>` on branch `agent/<slug>`. |
| **Env file** | Seeds `.env` from `.env.example` (if present) and upserts two keys (below). Idempotent. |
| **Services / ports** | Each worktree gets a unique `COMPOSE_PROJECT_NAME=<repo>-<slug>` and a **collision-free** `WT_PORT_OFFSET` (0, 10, 20, … assigned from a locked registry, reclaimed on removal). |
| **Dependencies** | `--deps` installs via a shared store (`pnpm`/`uv`/`npm`, availability-gated) so worktrees are cheap. Off by default (fast creates). |
| **Databases / external state** | Not auto-isolated — worktrees isolate files, not a shared dev DB. Use the per-worktree compose project to run an isolated DB, or namespace schemas. |

### Consuming the isolation in your project

Have your compose / dev config read the injected env so parallel stacks never
clash on the host:

```yaml
# docker-compose.yml — add the offset to every published port
services:
  web:
    ports: ["${WEB_PORT:-3000}:3000"]   # and set WEB_PORT = base + WT_PORT_OFFSET
```
```bash
# or in a Makefile / dev script
WEB_PORT=$(( 3000 + ${WT_PORT_OFFSET:-0} )) docker compose up
```
`COMPOSE_PROJECT_NAME` is already exported via `.env`, so containers/networks/volumes
are namespaced per worktree automatically.

## Commands

| Command | Does |
|---|---|
| `wt new <slug> [--base <ref>] [--deps] [--up] [--no-bootstrap]` | Create worktree + branch, assign ports, bootstrap. Idempotent (re-bootstraps if it exists). |
| `wt list` | All worktrees with offsets/branches/paths (flags `MISSING` dirs). |
| `wt info <slug>` | Path / branch / offset / compose project for one worktree. |
| `wt bootstrap <slug> [--deps]` | Re-run env/ports/deps setup (idempotent). |
| `wt rm <slug> [--force] [--keep-branch]` | `compose down`, remove the worktree, delete the branch, free the offset. `--force` discards local changes. |
| `wt prune` | Drop registry entries whose worktree dir is gone + `git worktree prune`. |

Worktrees live **outside** the repo (siblings), never nested inside it. The
registry (`.worktrees/<repo>/.registry.tsv`) is `flock`-guarded, so parallel
`wt new` calls get distinct offsets safely.

## Wiring into Claude Code (optional)

The bootstrap/teardown scripts are designed to double as native hook targets:

```jsonc
// .claude/settings.json (verify hook-event support against your CC version)
"hooks": {
  "WorktreeCreate": [{ "hooks": [{ "type": "command",
    "command": ".claude/scripts/worktree-bootstrap.sh \"$WT_PATH\" \"$WT_SLUG\" \"$WT_OFFSET\" \"$WT_PROJECT\"" }]}],
  "WorktreeRemove": [{ "hooks": [{ "type": "command",
    "command": ".claude/scripts/worktree-teardown.sh \"$WT_PATH\" \"$WT_PROJECT\"" }]}]
}
```

For our use case, the eval harness creates one worktree per mode off the same
base commit, so the three modes run fully isolated and independently diffable.

## Testing

```bash
bash .claude/scripts/test_worktree.sh   # E2E: creation, isolation, idempotency,
                                        # offset reuse, error paths, concurrency
```

## Gotchas

- **One branch per worktree** — git forbids checking out the same branch twice.
- **Shared dev DB** still collides across worktrees; use the per-worktree compose
  project to isolate it, or separate schemas.
- **Deps aren't installed by default** — pass `--deps` (and use `pnpm`/`uv` for a
  cheap shared store) when the worktree needs to actually build/run.
- **Cross-project port collisions** (two *different* repos' worktrees) are out of
  scope — offsets are namespaced per repo.
