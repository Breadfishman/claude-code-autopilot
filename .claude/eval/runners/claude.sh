#!/usr/bin/env bash
# Real runner — drives `claude -p` against the task prompt inside the workdir.
# The active mode overlay has already been written to <workdir>/CLAUDE.md by the
# harness, so Claude Code picks it up. Gated on the claude CLI being installed.
# args: <workdir> <task_dir> <metrics_file>
set -euo pipefail
workdir="$1"; task_dir="$2"; metrics="${3:-/dev/null}"
command -v claude >/dev/null 2>&1 || { echo "[claude-runner] claude CLI not found" >&2; exit 2; }

prompt="$(cat "$task_dir/task.md")"
cd "$workdir"
# Headless run in the isolated workdir. skip-permissions avoids hangs on prompts
# (the dir is a throwaway fixture); a timeout bounds a stuck session.
TIMEOUT="${WT_EVAL_TIMEOUT:-240}"
runner=(claude -p "$prompt" --dangerously-skip-permissions --output-format json)
if command -v timeout >/dev/null 2>&1; then
  out="$(timeout "$TIMEOUT" "${runner[@]}" 2>/dev/null || true)"
else
  out="$("${runner[@]}" 2>/dev/null || true)"
fi

if command -v python3 >/dev/null 2>&1; then
  tokens="$(printf '%s' "$out" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin); u = d.get("usage", {}) or {}
    print((u.get("input_tokens", 0) or 0) + (u.get("output_tokens", 0) or 0))
except Exception:
    print(0)
' 2>/dev/null || echo 0)"
else
  tokens=NA   # no python3 on this host — record "unmeasured", not a fake 0
fi
printf 'tokens=%s\n' "$tokens" >"$metrics"
