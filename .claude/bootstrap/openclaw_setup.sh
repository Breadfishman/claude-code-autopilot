#!/usr/bin/env bash
set -euo pipefail

log()  { printf "\n==> %s\n" "$*"; }
warn() { printf "\n[WARN] %s\n" "$*" >&2; }
skip() { printf "    [SKIP] %s\n" "$*"; }
has()  { command -v "$1" >/dev/null 2>&1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${1:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
OPENCLAW_WRAPPER_TARGET="${HOME}/.local/bin/openclaw"
HOST_OPENCLAW_STATE_DIR="${OPENCLAW_HOST_STATE_DIR:-$HOME/.openclaw}"
PROJECT_ENV_EXAMPLE="$PROJECT_DIR/.env.example"
PROJECT_ENV_FILE="$PROJECT_DIR/.env"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.openclaw.yml"
OPENCLAW_AUTO_START="${OPENCLAW_AUTO_START:-ask}"

if ! has docker; then
  warn "Docker is required for the Docker-only OpenClaw setup."
  exit 1
fi

if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD=(docker compose)
elif has docker-compose; then
  COMPOSE_CMD=(docker-compose)
else
  warn "Docker Compose plugin is required."
  exit 1
fi

if [[ ! -f "$COMPOSE_FILE" ]]; then
  warn "Compose file not found: $COMPOSE_FILE"
  exit 1
fi

mkdir -p "$(dirname "$OPENCLAW_WRAPPER_TARGET")"
mkdir -p "$HOST_OPENCLAW_STATE_DIR"

cat > "$OPENCLAW_WRAPPER_TARGET" <<EOF_WRAPPER
#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$PROJECT_DIR"
COMPOSE_FILE="\$PROJECT_DIR/docker-compose.openclaw.yml"
ENV_FILE="\$PROJECT_DIR/.env"
SERVICE="openclaw-gateway"
VIEWER_SERVICE="openclaw-browser-viewer"

if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD=(docker-compose)
else
  echo "Docker Compose is required." >&2
  exit 1
fi

compose() {
  local args=()
  if [[ -f "\$ENV_FILE" ]]; then
    args+=(--env-file "\$ENV_FILE")
  fi
  "\${COMPOSE_CMD[@]}" -f "\$COMPOSE_FILE" "\${args[@]}" "\$@"
}

env_value() {
  local key="\$1"
  local default_value="\$2"
  local value=""

  if [[ -f "\$ENV_FILE" ]]; then
    value="\$(sed -n "s/^\\\${key}=//p" "\$ENV_FILE" | tail -n1)"
  fi

  if [[ -n "\$value" ]]; then
    printf '%s\n' "\$value"
  else
    printf '%s\n' "\$default_value"
  fi
}

service_running() {
  compose ps --status running --services 2>/dev/null | grep -qx "\$1"
}

ensure_started() {
  if ! service_running "\$SERVICE"; then
    compose up -d "\$SERVICE" "\$VIEWER_SERVICE" >/dev/null
  fi
}

# Run a command inside the container with umask 0022 to prevent 600 file perms.
# compose exec skips login shells, so /etc/profile.d/umask.sh is never sourced.
oc_exec() {
  if [[ -t 0 && -t 1 ]]; then
    compose exec "\$SERVICE" gosu node bash -c 'umask 0022 && "\$@"' -- "\$@"
  else
    compose exec -T "\$SERVICE" gosu node bash -c 'umask 0022 && "\$@"' -- "\$@"
  fi
}

if [[ \$# -eq 0 ]]; then
  ensure_started
  oc_exec openclaw
  exit \$?
fi

case "\$1" in
  up)
    shift
    compose up -d "\$SERVICE" "\$VIEWER_SERVICE" "\$@"
    exit \$?
    ;;
  down)
    shift
    compose down "\$@"
    exit \$?
    ;;
  logs)
    shift
    compose logs -f "\$SERVICE" "\$VIEWER_SERVICE" "\$@"
    exit \$?
    ;;
  shell)
    shift
    ensure_started
    compose exec "\$SERVICE" /bin/bash "\$@"
    exit \$?
    ;;
  viewer-url)
    port="$(compose port "\$VIEWER_SERVICE" 6080 2>/dev/null | sed -n 's/.*://p' | head -n1)"
    if [[ -z "\${port:-}" ]] && service_running "\$VIEWER_SERVICE"; then
      port="\$(env_value OPENCLAW_VIEWER_PORT 6080)"
    fi
    if [[ -n "\${port:-}" ]]; then
      printf 'http://127.0.0.1:%s/vnc.html\n' "\$port"
    else
      echo "Viewer is not running." >&2
      exit 1
    fi
    ;;
  dashboard-url)
    port="$(compose port "\$SERVICE" 18789 2>/dev/null | sed -n 's/.*://p' | head -n1)"
    if [[ -z "\${port:-}" ]] && service_running "\$SERVICE"; then
      port="\$(env_value OPENCLAW_GATEWAY_PORT 18789)"
    fi
    if [[ -n "\${port:-}" ]]; then
      printf 'http://127.0.0.1:%s/\n' "\$port"
    else
      echo "Gateway is not running." >&2
      exit 1
    fi
    ;;
  compose)
    shift
    compose "\$@"
    exit \$?
    ;;
  status)
    if service_running "\$SERVICE"; then
      oc_exec openclaw "\$@"
    else
      echo "OpenClaw is not running. Start with: openclaw up" >&2
      exit 1
    fi
    exit \$?
    ;;
  *)
    ensure_started
    oc_exec openclaw "\$@"
    exit \$?
    ;;
esac
EOF_WRAPPER
chmod +x "$OPENCLAW_WRAPPER_TARGET"
log "Installed OpenClaw wrapper: $OPENCLAW_WRAPPER_TARGET"

for rcfile in "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [[ -f "$rcfile" ]] || [[ "$(basename "$rcfile")" == ".bashrc" ]]; then
    touch "$rcfile"
    if ! grep -qF 'export PATH="$HOME/.local/bin:$PATH"' "$rcfile" 2>/dev/null; then
      printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rcfile"
      log "Added ~/.local/bin to PATH in $rcfile"
    else
      skip "~/.local/bin already on PATH in $rcfile"
    fi
  fi
done

if [[ -f "$PROJECT_ENV_FILE" ]]; then
  skip "Existing .env detected at $PROJECT_ENV_FILE"
else
  if [[ -f "$PROJECT_ENV_EXAMPLE" ]]; then
    cp "$PROJECT_ENV_EXAMPLE" "$PROJECT_ENV_FILE"
    log "Created .env from .env.example"
  else
    log "Using defaults from $PROJECT_ENV_EXAMPLE until you create $PROJECT_ENV_FILE"
  fi
fi

# Auto-populate OPENCLAW_HOST_STATE_DIR and PUID/PGID if not already set
real_user="${SUDO_USER:-$(id -un)}"
real_home="$(eval echo "~$real_user")"
real_uid="$(id -u "$real_user")"
real_gid="$(id -g "$real_user")"

if [[ -f "$PROJECT_ENV_FILE" ]]; then
  if ! grep -q '^OPENCLAW_HOST_STATE_DIR=' "$PROJECT_ENV_FILE"; then
    sed -i "s|^# OPENCLAW_HOST_STATE_DIR=.*|OPENCLAW_HOST_STATE_DIR=${real_home}/.openclaw|" "$PROJECT_ENV_FILE" \
      || echo "OPENCLAW_HOST_STATE_DIR=${real_home}/.openclaw" >> "$PROJECT_ENV_FILE"
    log "Set OPENCLAW_HOST_STATE_DIR=${real_home}/.openclaw"
  fi
  if ! grep -q '^PUID=' "$PROJECT_ENV_FILE"; then
    echo "PUID=${real_uid}" >> "$PROJECT_ENV_FILE"
    echo "PGID=${real_gid}" >> "$PROJECT_ENV_FILE"
    log "Set PUID=${real_uid}, PGID=${real_gid}"
  fi
fi

compose_args=()
if [[ -f "$PROJECT_ENV_FILE" ]]; then
  compose_args+=(--env-file "$PROJECT_ENV_FILE")
fi

START_STACK=false
if [[ "$OPENCLAW_AUTO_START" == "1" || "$OPENCLAW_AUTO_START" == "true" || "$OPENCLAW_AUTO_START" == "yes" ]]; then
  START_STACK=true
elif [[ "$OPENCLAW_AUTO_START" == "0" || "$OPENCLAW_AUTO_START" == "false" || "$OPENCLAW_AUTO_START" == "no" ]]; then
  START_STACK=false
elif [[ -f "$PROJECT_ENV_FILE" ]]; then
  if [[ -t 0 && -t 1 ]]; then
    read -r -p "Start the Docker OpenClaw stack now? [y/N]: " start_now
    case "${start_now,,}" in
      y|yes) START_STACK=true ;;
      *) START_STACK=false ;;
    esac
  fi
else
  warn "Skipping automatic startup because .env does not exist yet."
  warn "Create and edit $PROJECT_ENV_FILE first, then run: openclaw up"
fi

if [[ "$START_STACK" == "true" ]]; then
  log "Starting Docker OpenClaw stack..."
  "${COMPOSE_CMD[@]}" -f "$COMPOSE_FILE" "${compose_args[@]}" up -d openclaw-gateway openclaw-browser-viewer
fi

VIEWER_PORT=""
GATEWAY_PORT=""
if [[ "$START_STACK" == "true" ]]; then
  VIEWER_PORT="$("${COMPOSE_CMD[@]}" -f "$COMPOSE_FILE" "${compose_args[@]}" port openclaw-browser-viewer 6080 2>/dev/null | sed -n 's/.*://p' | head -n1 || true)"
  GATEWAY_PORT="$("${COMPOSE_CMD[@]}" -f "$COMPOSE_FILE" "${compose_args[@]}" port openclaw-gateway 18789 2>/dev/null | sed -n 's/.*://p' | head -n1 || true)"

  # Configure workspace anchor hooks (session-memory + bootstrap-extra-files).
  # These prevent agents from losing track of their workspace after context
  # compaction. Idempotent — safe to re-run on every install/update.
  HOOKS_SCRIPT="$SCRIPT_DIR/openclaw_hooks_setup.sh"
  if [[ -f "$HOOKS_SCRIPT" ]]; then
    log "Configuring workspace anchor hooks..."
    # Give the gateway a moment to come up before the CLI talks to it
    for _i in 1 2 3 4 5 6 7 8 9 10; do
      if openclaw status >/dev/null 2>&1; then break; fi
      sleep 2
    done
    bash "$HOOKS_SCRIPT" || warn "Hook configuration failed — run manually: bash $HOOKS_SCRIPT"
  fi
fi

cat <<EOF_SUMMARY

======================================
  Docker OpenClaw Setup Complete
======================================

  Wrapper:
    $OPENCLAW_WRAPPER_TARGET

  Compose file:
    $COMPOSE_FILE

  Gateway:
    ${GATEWAY_PORT:-not started}

  Browser viewer:
    http://127.0.0.1:${VIEWER_PORT:-6080}/vnc.html

  Next steps (run from $PROJECT_DIR):
    1. (Optional) Edit .env to customize identity, ports, or API keys.
       PUID, PGID, and OPENCLAW_HOST_STATE_DIR were auto-configured.
    2. Re-open your shell so ~/.local/bin is on PATH.
    3. Start the stack (first start takes ~30s to initialize):
       make start
    4. Expose the gateway via Tailscale HTTPS (for remote access):
       sudo tailscale serve --bg http://localhost:18789
       Copy the https:// URL from the output (e.g., https://your-host.tail1234.ts.net)
    5. Add the Tailscale URL to .env:
       Edit .env and set: OPENCLAW_EXTRA_ORIGINS=https://your-host.tail1234.ts.net
    6. Configure allowed origins:
       make add-origins
    7. Get the dashboard auth token (NOT the localhost URL):
       make dashboard-url
       Copy only the token parameter (e.g., ?token=abc123...) from the output.
       Access dashboard at: https://your-host.tail1234.ts.net?token=abc123...
    8. Approve the pending device (open Tailscale dashboard first, then approve):
       make approve-device
    9. Authenticate providers if needed:
       make auth-anthropic
       make auth-openai
   10. Verify everything is running:
       make status
   11. Register an agent for your project:
       make add-agent AGENT=my-project REPO=/opt/repos/my-project
   12. Set up Discord bot channel:
       make setup-discord
   13. Set up Discord scaling/lanes (required after setup-discord):
       make setup-discord-scale
   14. See all available commands:
       make help

  Docker-only notes:
    - No host OpenClaw CLI is required.
    - State, cookies, downloads, and auth are stored in: $HOST_OPENCLAW_STATE_DIR
    - /opt/repos is mounted read-write into the gateway container by default.

EOF_SUMMARY
