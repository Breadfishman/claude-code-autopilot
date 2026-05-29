#!/usr/bin/env bash
set -euo pipefail

# Discord bot setup helper for OpenClaw
# Guides user through Discord bot creation and configuration

log()  { printf "\n==> %s\n" "$*"; }
warn() { printf "\n[WARN] %s\n" "$*" >&2; }
has()  { command -v "$1" >/dev/null 2>&1; }
cfg_path() {
  local state_home

  # If openclaw-gateway container is running, use host mount path
  if has docker && docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^openclaw-gateway$'; then
    state_home="${OPENCLAW_HOST_STATE_DIR:-${HOME}/.openclaw}"
  else
    state_home="${OPENCLAW_STATE_DIR:-${OPENCLAW_HOME:-$HOME/.openclaw}}"
  fi

  printf "%s/openclaw.json" "$state_home"
}

restart_openclaw_gateway() {
  # Check if openclaw-gateway container is running (Docker setup)
  if has docker && docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^openclaw-gateway$'; then
    log "Detected Docker setup - restarting via docker compose..."

    # Find docker-compose file (check common locations)
    local compose_file=""
    if [[ -f "docker-compose.openclaw.yml" ]]; then
      compose_file="docker-compose.openclaw.yml"
    elif [[ -f "../docker-compose.openclaw.yml" ]]; then
      compose_file="../docker-compose.openclaw.yml"
    elif [[ -f "../../docker-compose.openclaw.yml" ]]; then
      compose_file="../../docker-compose.openclaw.yml"
    fi

    if [[ -n "$compose_file" ]]; then
      docker compose -f "$compose_file" up -d --force-recreate openclaw-gateway
      return $?
    else
      warn "Docker container found but docker-compose.openclaw.yml not found. Trying standard restart..."
    fi
  fi

  # Fallback to standard restart methods
  openclaw gateway restart 2>/dev/null || systemctl --user restart openclaw-gateway.service 2>/dev/null || true
}

upsert_discord_secure_guild_config() {
  local guild_id="$1"
  local channel_id="$2"
  local user_id="$3"
  local require_mention="$4"
  local config_file
  config_file="$(cfg_path)"

  if ! has python3; then
    warn "python3 not found; cannot auto-configure Discord allowlist."
    return 1
  fi

  python3 - "$config_file" "$guild_id" "$channel_id" "$user_id" "$require_mention" <<'PY'
import json, os, sys
from datetime import datetime, timezone

cfg_path, guild_id, channel_id, user_id, require_mention = sys.argv[1:]

with open(cfg_path, "r", encoding="utf-8") as f:
    data = json.load(f)

meta = data.setdefault("meta", {})
meta["lastTouchedAt"] = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

channels = data.setdefault("channels", {})
discord = channels.setdefault("discord", {})
discord["groupPolicy"] = "allowlist"

guilds = discord.get("guilds")
if not isinstance(guilds, dict):
    guilds = {}
discord["guilds"] = guilds

guild_cfg = guilds.get(guild_id)
if not isinstance(guild_cfg, dict):
    guild_cfg = {}
guilds[guild_id] = guild_cfg
if require_mention.lower() in ("true", "false"):
    guild_cfg["requireMention"] = (require_mention.lower() == "true")

users = guild_cfg.get("users")
if not isinstance(users, list):
    users = []
uid = str(user_id).strip()
if uid and uid not in users:
    users.append(uid)
guild_cfg["users"] = users

guild_channels = guild_cfg.get("channels")
if not isinstance(guild_channels, dict):
    guild_channels = {}
guild_cfg["channels"] = guild_channels

chan_cfg = guild_channels.get(channel_id)
if not isinstance(chan_cfg, dict):
    chan_cfg = {}
chan_cfg["allow"] = True
if require_mention.lower() in ("true", "false"):
    chan_cfg["requireMention"] = (require_mention.lower() == "true")
guild_channels[channel_id] = chan_cfg

tmp = cfg_path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.replace(tmp, cfg_path)
PY
}

upsert_discord_channel_binding() {
  local guild_id="$1"
  local channel_id="$2"
  local agent_id="$3"
  local config_file
  config_file="$(cfg_path)"

  [[ -z "$agent_id" ]] && return 0

  if ! has python3; then
    warn "python3 not found; cannot auto-bind Discord channel to agent."
    return 1
  fi

  python3 - "$config_file" "$guild_id" "$channel_id" "$agent_id" <<'PY'
import json, os, sys
from datetime import datetime, timezone

cfg_path, guild_id, channel_id, agent_id = sys.argv[1:]

with open(cfg_path, "r", encoding="utf-8") as f:
    data = json.load(f)

meta = data.setdefault("meta", {})
meta["lastTouchedAt"] = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

bindings = data.get("bindings")
if not isinstance(bindings, list):
    bindings = []

def is_same_channel_binding(item):
    if not isinstance(item, dict):
        return False
    match = item.get("match")
    if not isinstance(match, dict):
        return False
    if match.get("channel") != "discord":
        return False
    peer = match.get("peer")
    if isinstance(peer, dict) and peer.get("kind") == "channel" and str(peer.get("id")) == str(channel_id):
        return True
    return match.get("guildId") == str(guild_id) and match.get("channelId") == str(channel_id)

bindings = [b for b in bindings if not is_same_channel_binding(b)]
bindings.append({
    "agentId": str(agent_id),
    "match": {
        "channel": "discord",
        "guildId": str(guild_id),
        "peer": {"kind": "channel", "id": str(channel_id)}
    }
})
data["bindings"] = bindings

tmp = cfg_path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.replace(tmp, cfg_path)
PY
}

# Raise the Discord inbound-worker run timeout. OpenClaw caps total wall-clock
# per inbound message at a hard-coded 30 min default and SIGTERMs the run when
# it trips (reason=client_disconnected) — independent of, and unaffected by,
# agents.defaults.timeoutSeconds. Default here is 2h so the agent's own
# graceful timeout is the limiter, not the channel's hard kill.
upsert_discord_inbound_timeout() {
  local timeout_ms="${1:-7200000}"
  local config_file
  config_file="$(cfg_path)"

  if ! has python3; then
    warn "python3 not found; cannot set Discord inbound worker timeout."
    return 1
  fi

  if [[ ! -f "$config_file" ]]; then
    warn "Config not found at ${config_file}; cannot set Discord inbound worker timeout."
    return 1
  fi

  python3 - "$config_file" "$timeout_ms" <<'PY'
import json, os, sys
from datetime import datetime, timezone

cfg_path, timeout_ms = sys.argv[1], int(sys.argv[2])

with open(cfg_path, "r", encoding="utf-8") as f:
    data = json.load(f)

meta = data.setdefault("meta", {})
meta["lastTouchedAt"] = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

channels = data.setdefault("channels", {})
discord = channels.setdefault("discord", {})
inbound = discord.get("inboundWorker")
if not isinstance(inbound, dict):
    inbound = {}
inbound["runTimeoutMs"] = timeout_ms
discord["inboundWorker"] = inbound

tmp = cfg_path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.replace(tmp, cfg_path)
PY
}

if ! has openclaw; then
  warn "OpenClaw is not installed. Run install.sh --with-openclaw first."
  exit 1
fi

echo ""
echo "=============================================="
echo "  DISCORD BOT SETUP FOR OPENCLAW"
echo "=============================================="
echo ""
echo "  This wizard helps you connect OpenClaw to Discord."
echo ""
echo "  Prerequisites:"
echo "    - A Discord server where you have admin permissions"
echo "    - A web browser to create the Discord application"
echo ""
echo "=============================================="
echo ""

# Step 1: Create Discord Application
echo "Step 1: Create a Discord Application"
echo "-------------------------------------"
echo ""
echo "  1. Go to: https://discord.com/developers/applications"
echo "  2. Click 'New Application'"
echo "  3. Name it: 'Claude Code Autopilot' (or your preference)"
echo "  4. Click 'Create'"
echo ""

# Step 2: Create Bot
echo "Step 2: Create the Bot"
echo "----------------------"
echo ""
echo "  1. In the application settings, click 'Bot' in the left sidebar"
echo "  2. Click 'Add Bot' -> 'Yes, do it!'"
echo "  3. Under 'Privileged Gateway Intents', enable:"
echo "     - MESSAGE CONTENT INTENT"
echo "     - SERVER MEMBERS INTENT (optional)"
echo "  4. Click 'Reset Token' to generate a bot token"
echo "  5. Copy the token (you'll need it next)"
echo ""

# Step 3: Invite Bot to Server
echo "Step 3: Invite Bot to Your Server"
echo "----------------------------------"
echo ""
echo "  1. Click 'OAuth2' -> 'URL Generator' in the left sidebar"
echo "  2. Under 'Scopes', check: bot, applications.commands"
echo "  3. Under 'Bot Permissions', check:"
echo "     - Send Messages"
echo "     - Read Message History"
echo "     - Use Slash Commands"
echo "     - Embed Links"
echo "     - Attach Files"
echo "  4. Copy the generated URL and open it in your browser"
echo "  5. Select your server and click 'Authorize'"
echo ""

# Step 4: Configure OpenClaw
echo "Step 4: Connect to OpenClaw"
echo "----------------------------"
echo ""
read -rp "  Paste your Discord bot token: " BOT_TOKEN

if [[ -z "$BOT_TOKEN" ]]; then
  warn "No token provided. You can configure later with:"
  echo "  openclaw channels add --channel discord --token <your-token>"
  exit 0
fi

# Enable Discord plugin if not already enabled
openclaw plugins enable discord 2>/dev/null || true

# Add Discord channel to OpenClaw
# Try current CLI syntax first, then fall back to config-based setup
TOKEN_CONFIGURED=0
if openclaw channels add --channel discord --token "$BOT_TOKEN" 2>&1; then
  log "Discord channel configured successfully!"
  TOKEN_CONFIGURED=1
elif openclaw config set channels.discord.token "$BOT_TOKEN" 2>&1; then
  log "Discord token set via config."
  TOKEN_CONFIGURED=1
else
  warn "Failed to configure Discord channel."
  echo "  Try manually inside the container (make shell):"
  echo "    1. openclaw plugins enable discord"
  echo "    2. openclaw channels add --channel discord --token <your-token>"
  echo "       OR: openclaw config set channels.discord.token <your-token>"
  echo "    3. Restart: exit && make restart"
  exit 1
fi

if [[ "$TOKEN_CONFIGURED" == "1" ]]; then
  # Lift the 30-min inbound-worker cap before restarting so the same restart
  # applies both the token and the timeout. Override with env if desired.
  if upsert_discord_inbound_timeout "${OPENCLAW_DISCORD_INBOUND_TIMEOUT_MS:-7200000}"; then
    log "Set channels.discord.inboundWorker.runTimeoutMs (2h) in $(cfg_path)"
  else
    warn "Could not set Discord inbound worker timeout; apply it later with 'make set-inbound-timeout' (see docs/troubleshooting.md)."
  fi

  # Restart gateway to pick up new channel + timeout
  restart_openclaw_gateway
  log "Gateway restarted to connect Discord bot."
  sleep 3
fi

# Step 5: Test connection
echo ""
echo "Step 5: Test Connection"
echo "-----------------------"
echo ""
echo "  IMPORTANT: OpenClaw Discord typically requires an initial Discord pairing"
echo "  approval before command execution, especially for DMs / secure sessions."
echo "  Also, built-in commands are slash-style (/status, /help), not !status."
echo ""

read -rp "  Send a test message to Discord? (y/N): " TEST_MSG

if [[ "$TEST_MSG" =~ ^[Yy] ]]; then
  if openclaw notify "Hello from Claude Code Autopilot! Bot is connected." 2>/dev/null; then
    log "Test message sent! Check your Discord server."
  else
    warn "Test message failed. Check your bot token and server permissions."
  fi
fi

echo ""
echo "Step 6: Secure Guild/Channel Access (Recommended)"
echo "--------------------------------------------------"
echo ""
echo "  Lock Discord access to one server, one channel, and one Discord user."
echo "  This also fixes common 'This channel is not allowed' / 'not authorized'"
echo "  errors by creating the proper OpenClaw allowlist entries."
echo ""
read -rp "  Configure secure Discord allowlist now? (Y/n): " CFG_SECURE

if [[ ! "$CFG_SECURE" =~ ^[Nn]$ ]]; then
  read -rp "  Discord Server ID (guild): " DISCORD_GUILD_ID
  read -rp "  Discord Channel ID: " DISCORD_CHANNEL_ID
  read -rp "  Your Discord User ID: " DISCORD_USER_ID
  read -rp "  Require mention in that channel for plain-text commands? (Y/n): " REQUIRE_MENTION_ANS

  REQUIRE_MENTION="true"
  if [[ "$REQUIRE_MENTION_ANS" =~ ^[Nn]$ ]]; then
    REQUIRE_MENTION="false"
  fi

  if [[ -n "$DISCORD_GUILD_ID" && -n "$DISCORD_CHANNEL_ID" && -n "$DISCORD_USER_ID" ]]; then
    if upsert_discord_secure_guild_config "$DISCORD_GUILD_ID" "$DISCORD_CHANNEL_ID" "$DISCORD_USER_ID" "$REQUIRE_MENTION"; then
      log "Configured Discord guild/channel/user allowlist in $(cfg_path)"
    else
      warn "Failed to auto-configure Discord allowlist. You can edit $(cfg_path) manually."
    fi

    echo ""
    read -rp "  Bind this Discord channel to a specific agent ID (e.g. myproject) [optional]: " DISCORD_AGENT_ID
    if [[ -n "$DISCORD_AGENT_ID" ]]; then
      if upsert_discord_channel_binding "$DISCORD_GUILD_ID" "$DISCORD_CHANNEL_ID" "$DISCORD_AGENT_ID"; then
        log "Bound Discord channel ${DISCORD_CHANNEL_ID} to agent '${DISCORD_AGENT_ID}'"
      else
        warn "Failed to auto-bind Discord channel to agent '${DISCORD_AGENT_ID}'."
      fi
    fi

    restart_openclaw_gateway
    log "Gateway restarted to apply Discord allowlist and optional agent binding."
  else
    warn "Skipped secure allowlist setup (missing one or more IDs)."
  fi
fi

echo ""
log "Discord setup complete!"
echo ""
echo "  First-time pairing (required before replies work):"
echo "    1. DM the bot in Discord (send: hello)"
echo "    2. Run: openclaw pairing list discord"
echo "    3. Run: openclaw pairing approve discord <code>"
echo ""
echo "  Test from Discord (standalone messages):"
echo "    /help"
echo "    /status"
echo "    /new"
echo "    /recheckin 5m Re-check service health and report back in this channel."
echo "    (If channel is bound to an agent, start a new session after setup: /new)"
echo ""
echo "  Scale setup wizard (parallel lanes + threads):"
echo "    bash .claude/bootstrap/openclaw_discord_scale_setup.sh"
echo ""
echo "  Notes:"
echo "    - !status / !ask are not guaranteed built-in commands on newer OpenClaw"
echo "    - If you run !status and see 'bash is disabled', that is expected on secure"
echo "      setups. Prefer slash commands, or explicitly enable commands.bash=true."
echo "    - If using a server channel, ensure bot has 'Use Application Commands'"
echo "      and that your Discord allowlist/guild policy permits that channel"
echo ""
echo "  See: .claude/docs/openclaw-remote-commands.md for full reference"
echo ""
