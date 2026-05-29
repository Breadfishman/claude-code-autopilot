#!/usr/bin/env bash
set -euo pipefail

# Ensure files created by the node user (including openclaw.json) are
# world-readable (644 for files, 755 for dirs). Without this, OpenClaw's
# config writes use the default 077 umask, creating 600 files that break
# on subsequent reads after container recreation or host-side access.
umask 0022

mode="${1:-gateway}"
if [[ $# -gt 0 ]]; then
  shift
fi

# Align container node user UID/GID with host user (avoids permission conflicts on bind mounts)
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

current_uid=$(id -u node)
current_gid=$(id -g node)

if [[ "$PGID" != "$current_gid" ]]; then
  groupmod -o -g "$PGID" node 2>/dev/null || true
fi
if [[ "$PUID" != "$current_uid" ]]; then
  usermod -o -u "$PUID" node 2>/dev/null || true
fi

# Grant node user access to the host Docker socket (if mounted).
# The socket GID varies per host, so we detect it at runtime and create
# a matching group inside the container.
if [[ -S /var/run/docker.sock ]]; then
  DOCKER_SOCK_GID="$(stat -c '%g' /var/run/docker.sock)"
  if ! getent group "$DOCKER_SOCK_GID" >/dev/null 2>&1; then
    groupadd -g "$DOCKER_SOCK_GID" docker-host 2>/dev/null || true
  fi
  DOCKER_GROUP_NAME="$(getent group "$DOCKER_SOCK_GID" | cut -d: -f1)"
  usermod -aG "$DOCKER_GROUP_NAME" node 2>/dev/null || true
fi

OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-/home/node/.openclaw}"
OPENCLAW_BROWSER_DOWNLOADS_DIR="${OPENCLAW_BROWSER_DOWNLOADS_DIR:-$OPENCLAW_STATE_DIR/downloads}"
OPENCLAW_BROWSER_WIDTH="${OPENCLAW_BROWSER_WIDTH:-1920}"
OPENCLAW_BROWSER_HEIGHT="${OPENCLAW_BROWSER_HEIGHT:-1080}"
OPENCLAW_BROWSER_HEADLESS="${OPENCLAW_BROWSER_HEADLESS:-false}"
OPENCLAW_BROWSER_DEBUG_PORT="${OPENCLAW_BROWSER_DEBUG_PORT:-18800}"
OPENCLAW_VNC_PORT="${OPENCLAW_VNC_PORT:-5900}"
CHROME_BIN="${CHROME_BIN:-/usr/bin/chromium}"
OPENCLAW_MODEL_FALLBACKS="${OPENCLAW_MODEL_FALLBACKS:-[\"claude-max-proxy/claude-sonnet\"]}"
OPENCLAW_MODEL_PRIMARY="${OPENCLAW_MODEL_PRIMARY:-claude-max-proxy/claude-opus}"

# Clean up stale Chromium profile locks from previous container runs.
# force-recreate gives the container a new hostname, so Chromium sees the
# old lock as belonging to "another computer" and refuses to start.
find "$OPENCLAW_STATE_DIR/browser" -name 'SingletonLock' -delete 2>/dev/null || true
find "$OPENCLAW_STATE_DIR/browser" -name 'SingletonSocket' -delete 2>/dev/null || true
find "$OPENCLAW_STATE_DIR/browser" -name 'SingletonCookie' -delete 2>/dev/null || true

# Initialize browser isolation directories (used by browser-manager.sh)
mkdir -p "$OPENCLAW_STATE_DIR/display-locks" \
         "$OPENCLAW_STATE_DIR/browser-profiles"

# Clean up stale display locks from previous container runs
rm -f "$OPENCLAW_STATE_DIR/display-locks"/* 2>/dev/null || true

HOST_REPOS_DIR="${HOST_REPOS_DIR:-/opt/repos}"
mkdir -p "$OPENCLAW_STATE_DIR" "$OPENCLAW_BROWSER_DOWNLOADS_DIR" "$HOST_REPOS_DIR"
# Only chown container-internal dirs — NOT bind-mounted repos dir
chown -R node:node "$OPENCLAW_STATE_DIR" "$OPENCLAW_BROWSER_DOWNLOADS_DIR" /home/node
# Ensure config is readable even if written by a host user with a different UID
chmod 644 "$OPENCLAW_STATE_DIR/openclaw.json" 2>/dev/null || true
touch /home/node/.gitconfig
chown node:node /home/node/.gitconfig

if [[ -n "${GIT_AUTHOR_NAME:-}" ]]; then
  gosu node git config --global user.name "$GIT_AUTHOR_NAME"
fi
if [[ -n "${GIT_AUTHOR_EMAIL:-}" ]]; then
  gosu node git config --global user.email "$GIT_AUTHOR_EMAIL"
fi
export GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-${GIT_AUTHOR_NAME:-}}"
export GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-${GIT_AUTHOR_EMAIL:-}}"

# Ensure the official Discord plugin is installed (idempotent).
#
# OpenClaw installs external plugins into $OPENCLAW_STATE_DIR/npm, which is a
# host bind mount — so the plugin CANNOT be baked into the image (the mount
# would shadow it at runtime). Instead we install on first boot and let the
# pinned npm record persist in the state dir; later boots see it present and
# skip the network install. Set OPENCLAW_INSTALL_DISCORD_PLUGIN=0 to opt out.
OPENCLAW_DISCORD_PLUGIN="${OPENCLAW_DISCORD_PLUGIN:-@openclaw/discord}"
ensure_discord_plugin() {
  [[ "${OPENCLAW_INSTALL_DISCORD_PLUGIN:-1}" == "1" ]] || return 0
  if [[ -d "$OPENCLAW_STATE_DIR/npm/node_modules/@openclaw/discord" ]]; then
    return 0
  fi
  echo "[entrypoint] Installing OpenClaw Discord plugin (${OPENCLAW_DISCORD_PLUGIN})..."
  if gosu node openclaw plugins install "$OPENCLAW_DISCORD_PLUGIN" --pin; then
    echo "[entrypoint] Discord plugin installed."
  else
    echo "[entrypoint] WARN: Discord plugin install failed (continuing). Install manually with:" >&2
    echo "[entrypoint]   docker exec openclaw-gateway openclaw plugins install @openclaw/discord --pin" >&2
  fi
}

start_display_stack() {
  export DISPLAY=:99

  # Clean up stale X server lock files from previous runs
  rm -f /tmp/.X99-lock /tmp/.X11-unix/X99

  # Start virtual X server
  Xvfb :99 -screen 0 "${OPENCLAW_BROWSER_WIDTH}x${OPENCLAW_BROWSER_HEIGHT}x24" -ac -nolisten tcp >/tmp/xvfb.log 2>&1 &

  # Wait for Xvfb to fully initialize before starting dependent services
  sleep 2

  # Start window manager and VNC server (both depend on Xvfb being ready)
  fluxbox >/tmp/fluxbox.log 2>&1 &
  x11vnc -display :99 -forever -shared -rfbport "$OPENCLAW_VNC_PORT" -nopw >/tmp/x11vnc.log 2>&1 &
}

# Auto-configure on fresh install (no openclaw.json yet)
if [[ ! -f "$OPENCLAW_STATE_DIR/openclaw.json" ]]; then
  gosu node openclaw config set gateway.mode local 2>/dev/null || true
  gosu node openclaw config set gateway.bind all 2>/dev/null || true
fi

# Clean up per-agent browser displays on container shutdown
trap 'browser-manager cleanup 2>/dev/null || true' EXIT

case "$mode" in
  gateway)
    ensure_discord_plugin
    start_display_stack
    exec gosu node openclaw gateway
    ;;
  shell)
    start_display_stack
    exec gosu node /bin/bash "$@"
    ;;
  *)
    start_display_stack
    exec gosu node "$mode" "$@"
    ;;
esac
