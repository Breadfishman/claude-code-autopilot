#!/usr/bin/env bash
#
# openclaw_hooks_setup.sh — Configure OpenClaw hooks for workspace anchoring.
#
# What this does:
#   1. Enables the `session-memory` hook (preserves context across /new and /reset)
#   2. Enables the `bootstrap-extra-files` hook and configures it to inject
#      AGENTS.md and .claude/CLAUDE.md from each workspace on every session start
#
# Why this matters:
#   Long OpenClaw sessions lose track of their working directory after context
#   compaction. The bootstrap-extra-files hook re-injects workspace anchor files
#   at every session boundary, so any agent automatically re-anchors to its
#   correct repo without per-agent or per-repo manual setup.
#
# Idempotent: safe to run multiple times.
# Usage: bash .claude/bootstrap/openclaw_hooks_setup.sh

set -euo pipefail

log()  { printf "\n==> %s\n" "$*"; }
warn() { printf "\n[WARN] %s\n" "$*" >&2; }

OPENCLAW_HOME="${OPENCLAW_HOST_STATE_DIR:-$HOME/.openclaw}"
CONFIG_FILE="$OPENCLAW_HOME/openclaw.json"

if [[ ! -f "$CONFIG_FILE" ]]; then
  warn "OpenClaw config not found: $CONFIG_FILE"
  warn "Run the OpenClaw bootstrap first: bash .claude/bootstrap/openclaw_setup.sh"
  exit 1
fi

if ! command -v openclaw >/dev/null 2>&1; then
  warn "openclaw CLI not found on PATH."
  warn "Open a new shell so ~/.local/bin is loaded, or run the OpenClaw bootstrap first."
  exit 1
fi

if ! openclaw status >/dev/null 2>&1; then
  warn "OpenClaw gateway is not running. Start it first:"
  warn "  cd /opt/openclaw-home && make start"
  exit 1
fi

log "Enabling session-memory hook (preserves context across /new and /reset)..."
openclaw hooks enable session-memory >/dev/null 2>&1 || true

log "Enabling bootstrap-extra-files hook (injects workspace anchors)..."
openclaw hooks enable bootstrap-extra-files >/dev/null 2>&1 || true

log "Configuring bootstrap-extra-files to inject AGENTS.md and .claude/CLAUDE.md..."
python3 - "$CONFIG_FILE" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
d = json.loads(path.read_text())

d.setdefault("hooks", {}).setdefault("internal", {})
d["hooks"]["internal"]["enabled"] = True
entries = d["hooks"]["internal"].setdefault("entries", {})

# bootstrap-extra-files: inject workspace anchor files at every session start
entry = entries.setdefault("bootstrap-extra-files", {})
entry["enabled"] = True
cfg = entry.setdefault("config", {})
files = list(cfg.get("files", []))
for required in ("AGENTS.md", ".claude/CLAUDE.md"):
    if required not in files:
        files.append(required)
cfg["files"] = files

# session-memory: enable (default config is fine)
entries.setdefault("session-memory", {})["enabled"] = True

# Strip any invalid legacy keys that some earlier versions may have written
defaults = d.setdefault("agents", {}).setdefault("defaults", {})
defaults.pop("systemPrompt", None)  # unrecognized in current schema

path.write_text(json.dumps(d, indent=4))
print(f"Updated: {path}")
PY

log "Restarting gateway so the new hook config takes effect..."
if [[ -d /opt/openclaw-home ]] && command -v make >/dev/null 2>&1; then
  ( cd /opt/openclaw-home && make restart >/dev/null 2>&1 ) || \
    warn "Restart failed — run 'cd /opt/openclaw-home && make restart' manually."
else
  warn "Could not auto-restart — run 'cd /opt/openclaw-home && make restart' manually."
fi

cat <<'EOF'

======================================
  Workspace Anchor Hooks Configured
======================================

  Hooks enabled:
    - session-memory          (preserves context across /new and /reset)
    - bootstrap-extra-files   (injects AGENTS.md + .claude/CLAUDE.md at session start)

  What this gives you:
    Every agent automatically re-anchors to its workspace at session start
    and after context compaction. No per-agent or per-repo setup needed —
    works for every repo you add now and in the future.

  For each repo you add later:
    1. Create a minimal AGENTS.md at the repo root:
       echo "# <RepoName>\nWorkspace: /opt/repos/<repo>" > /opt/repos/<repo>/AGENTS.md
    2. Register the agent:
       make add-agent AGENT=<name> REPO=/opt/repos/<repo>

EOF
