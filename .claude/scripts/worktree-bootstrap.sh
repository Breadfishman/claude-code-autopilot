#!/usr/bin/env bash
# worktree-bootstrap.sh — project-aware setup for an isolated git worktree.
#
# Makes a fresh worktree actually runnable: renders a per-worktree .env, wires a
# unique COMPOSE_PROJECT_NAME + WT_PORT_OFFSET so parallel stacks don't collide,
# and (opt-in) installs dependencies via a shared store. Idempotent.
#
# Usage: worktree-bootstrap.sh <worktree_path> <slug> <port_offset> <compose_project> [--deps]
# Designed to also work as a Claude Code `WorktreeCreate` hook target.
set -euo pipefail

wt_path="${1:?worktree path required}"
slug="${2:?slug required}"
offset="${3:?port offset required}"
project="${4:?compose project required}"
shift 4 || true

do_deps=0
for a in "$@"; do [ "$a" = "--deps" ] && do_deps=1; done

log() { printf '[wt-bootstrap] %s\n' "$*" >&2; }

[ -d "$wt_path" ] || { log "not a directory: $wt_path"; exit 1; }
cd "$wt_path"

# --- 1. env file: seed from .env.example, then guarantee isolation keys ---------
if [ -f .env.example ] && [ ! -f .env ]; then
  cp .env.example .env
  log "rendered .env from .env.example"
fi
touch .env

set_kv() { # key value  — idempotent upsert into .env
  local k="$1" v="$2" tmp
  if grep -qE "^${k}=" .env; then
    tmp="$(mktemp)"
    awk -F= -v k="$k" -v v="$v" 'BEGIN{OFS="="} $1==k{$0=k"="v} {print}' .env >"$tmp" && mv "$tmp" .env
  else
    printf '%s=%s\n' "$k" "$v" >>.env
  fi
}
set_kv COMPOSE_PROJECT_NAME "$project"
set_kv WT_PORT_OFFSET "$offset"
log "wired COMPOSE_PROJECT_NAME=$project WT_PORT_OFFSET=$offset into .env"

# --- 2. metadata file (machine-readable) ---------------------------------------
{
  printf 'slug=%s\n' "$slug"
  printf 'offset=%s\n' "$offset"
  printf 'project=%s\n' "$project"
  printf 'path=%s\n' "$wt_path"
} >.worktree-info

# --- 3. dependencies (opt-in, availability-gated, shared store) -----------------
if [ "$do_deps" = "1" ]; then
  if [ -f pnpm-lock.yaml ] && command -v pnpm >/dev/null 2>&1; then
    log "pnpm install (shared content-addressed store)"
    pnpm install --prefer-offline || log "pnpm install failed (non-fatal)"
  elif { [ -f uv.lock ] || [ -f pyproject.toml ]; } && command -v uv >/dev/null 2>&1; then
    log "uv sync (shared cache)"
    uv sync || log "uv sync failed (non-fatal)"
  elif [ -f package-lock.json ] && command -v npm >/dev/null 2>&1; then
    log "npm ci"
    npm ci || log "npm ci failed (non-fatal)"
  else
    log "no recognized lockfile/toolchain found — skipping dependency install"
  fi
else
  log "dependency install skipped (pass --deps to enable)"
fi

log "bootstrap complete for '$slug'"
