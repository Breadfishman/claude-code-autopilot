#!/usr/bin/env bash
# worktree-teardown.sh — stop a worktree's isolated services before removal.
#
# Best-effort and availability-gated: brings down the worktree's docker compose
# project (if docker + a compose file are present) so no orphaned containers or
# bound ports linger. Git worktree/branch removal is handled by `wt rm`, not here.
#
# Usage: worktree-teardown.sh <worktree_path> <compose_project>
# Designed to also work as a Claude Code `WorktreeRemove` hook target.
set -euo pipefail

wt_path="${1:-}"
project="${2:-}"

log() { printf '[wt-teardown] %s\n' "$*" >&2; }

if [ -n "$project" ] && [ -d "$wt_path" ] && command -v docker >/dev/null 2>&1; then
  if ls "$wt_path"/docker-compose*.y*ml "$wt_path"/compose.y*ml >/dev/null 2>&1; then
    log "docker compose -p $project down --remove-orphans"
    ( cd "$wt_path" && docker compose -p "$project" down --remove-orphans ) \
      || log "compose down reported issues (non-fatal)"
  else
    log "no compose file in worktree — nothing to bring down"
  fi
else
  log "docker unavailable or worktree gone — skipping service teardown"
fi

log "teardown complete for '${project:-unknown}'"
