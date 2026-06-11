# OpenClaw Setup (Quick Guide)

This page is a short entry point. The full OpenClaw guides live in `.claude/docs/`.

## What OpenClaw Adds

- Discord remote control (slash commands and channel bindings)
- Browser automation with a Docker-hosted managed browser
- Live browser viewer for manual login and takeover via noVNC
- Cron jobs and automation
- Gateway and multi-agent routing
- Cross-session memory and search

## Quick Setup

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force --bootstrap-linux --with-openclaw
```

Then:

The Docker/OpenClaw install defaults to `/opt/openclaw-home` when `--dest` is omitted.

1. Optional overrides: `cp /opt/openclaw-home/.env.example /opt/openclaw-home/.env`
2. Edit `/opt/openclaw-home/.env` before first startup
3. Start or restart the Docker stack from `/opt/openclaw-home`: `make start`
4. Authenticate Anthropic subscription inside the container: `make auth-anthropic`
5. Authenticate OpenAI subscription inside the container when needed: `make auth-openai`
6. Open the browser viewer: `make viewer-url`
7. Run Discord setup if needed: `make setup-discord` (also lifts the 30-min Discord inbound-worker cap to 2h so long tasks aren't killed mid-run — see [troubleshooting](troubleshooting.md#discord-task-killed-at-30-minutes-discord-inbound-worker-timed-out))
8. Register extra repos under `/opt/repos` if needed: `make add-agent AGENT=<agent-id> REPO=/opt/repos/<repo-name>`

Important:

- Default repo mount is `${HOST_REPOS_DIR:-/opt/repos}` on the host to `/opt/repos` in the container.
- OpenClaw is not installed on the host in the default flow. The `openclaw` command is a host wrapper into Docker.
- `OPENCLAW_THINKING_DEFAULT=high` is the recommended default when `OPENCLAW_MODEL_PRIMARY=claude-max-proxy/claude-opus` (the stack default).
- Use `ANTHROPIC_API_KEY` or `OPENAI_API_KEY` in `.env` for direct API-key auth. Use in-container auth commands for subscription-backed auth.
- Host OpenClaw state automatically defaults to `~/.openclaw`, bind-mounted into the container. Only set `OPENCLAW_HOST_STATE_DIR` if you want a non-default path.
- Host services are reachable from the container at `http://host.docker.internal:<port>`. For example, a host dev server on port `8080` should be accessed as `http://host.docker.internal:8080` from OpenClaw.
- Control UI pairing: `127.0.0.1` is auto-approved. Same-host Tailnet access may also count as local, but other Tailnet/LAN clients still require explicit device approval.
- `PROJECT.md` is generated only by deep analysis.

## Browser Login and Takeover

Use the noVNC viewer when you need to watch the browser or log into a site manually:

```bash
make viewer-url
```

Open the printed URL in your browser, complete the login in the viewer, then return to OpenClaw commands. The browser profile persists in the host `~/.openclaw` state directory across container restarts.

For OpenAI subscription OAuth inside Docker, run:

```bash
make auth-openai
```

If the callback flow cannot complete automatically, use OpenClaw's printed fallback prompt to paste the redirect URL or code back into the container session.

## Claude Max Proxy Setup

The installer clones `claude-max-api-proxy` and runs it as a container in the stack. It provides an OpenAI-compatible API backed by your Claude Max subscription through the Claude CLI.

**No host-side Claude install required.** The proxy container ships its own Claude CLI and keeps its credentials in a private Docker volume (`claude-proxy-home`) that is isolated from any `claude` sessions you run on the host. This prevents the OAuth refresh-token rotation race that used to lock the container into 401s after 8–9 hours of uptime.

### One-time auth setup

After the stack is up (`make start` or `openclaw up`), generate a long-lived OAuth token inside the container and wire it in via env — this bypasses the refresh-token flow entirely, giving you ~1 year of uninterrupted service:

```bash
cd /opt/openclaw-home

# Launch the Claude CLI's headless token flow inside the container.
# Follow the printed URL, sign in with your Claude Max account, and
# paste the resulting `sk-ant-oat01-…` token.
docker exec -it claude-max-proxy claude setup-token

# Put the token into the host env file. `.env` must be chmod 600.
echo "CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-<paste-your-token>" >> /opt/openclaw-home/.env
chmod 600 /opt/openclaw-home/.env

# Restart the proxy so it picks up the token.
docker compose -f docker-compose.openclaw.yml up -d --force-recreate claude-max-proxy
```

Verify:

```bash
docker exec claude-max-proxy claude auth status
# → {"loggedIn": true, "authMethod": "oauth_token", "apiProvider": "firstParty"}

curl -s http://localhost:3456/health | jq '.auth, .models.available'
# → "loggedIn": true, and the full model list populated
```

The token is valid for ~1 year. When it approaches expiry (or if you revoke it), rerun `claude setup-token` inside the container and replace the value in `.env`.

If you ever lose the private credentials volume and need to rebuild from scratch, `docker volume rm openclaw-stack_claude-proxy-home` + rebuild + rerun `setup-token` restores a clean state.

After the proxy is authenticated, it is reachable from the OpenClaw gateway at `http://claude-max-proxy:3456/v1`.

**Configure OpenClaw to use the proxy.** Edit `~/.openclaw/openclaw.json` and update two sections.

**1. Add the provider.** Place the `models` block between the `auth` and `agents` sections:

```json
"models": {
  "mode": "merge",
  "providers": {
    "claude-max-proxy": {
      "baseUrl": "http://claude-max-proxy:3456/v1",
      "api": "openai-completions",
      "auth": "api-key",
      "apiKey": "ignored",
      "models": [
        {
          "id": "claude-sonnet",
          "name": "Claude Sonnet (latest, Max Proxy)"
        },
        {
          "id": "claude-opus",
          "name": "Claude Opus (latest, Max Proxy)"
        }
      ]
    }
  }
},
```

These are **version-less, always-latest aliases**. The proxy resolves any
`claude-opus*` / `claude-sonnet*` / `claude-haiku*` id to that family and runs
the Claude CLI with `--model opus|sonnet|haiku`, which the CLI always points at
the newest release. So `claude-opus` follows every new Opus automatically — no
config change per release. If you'd rather pin a fixed model (e.g. to hold
Sonnet at a known version), use a dated id such as `claude-sonnet-4-6`
instead; it resolves the same way but stays on that version.

**2. Add the model allowlist.** Inside `agents.defaults`, add a `models` object that registers each model with a short alias. OpenClaw only exposes models listed here:

```json
"agents": {
  "defaults": {
    "contextPruning": { "mode": "cache-ttl", "ttl": "1h" },
    "compaction": { "mode": "safeguard" },
    "thinkingDefault": "high",
    "timeoutSeconds": 7200,
    "heartbeat": { "every": "1h" },
    "maxConcurrent": 8,
    "subagents": { "runTimeoutSeconds": 3600 },
    "models": {
      "claude-max-proxy/claude-sonnet": { "alias": "sonnet" },
      "claude-max-proxy/claude-opus": { "alias": "opus" }
    }
  }
}
```

**3. Set the primary model and fallbacks.** Edit `/opt/openclaw-home/.env`:

```
OPENCLAW_MODEL_PRIMARY=claude-max-proxy/claude-opus
OPENCLAW_MODEL_FALLBACKS=["claude-max-proxy/claude-sonnet"]
```

Restart the gateway:

```bash
make restart
```

Verify both models are registered:

```bash
openclaw models list
```

You should see both `claude-max-proxy/claude-sonnet` and `claude-max-proxy/claude-opus`. Switch between them in Discord with `/model`, or from the CLI with the alias (`/model opus`, `/model sonnet`).

Verify the proxy container is running:

```bash
make status
```

The `claude-max-proxy` container should appear alongside `openclaw-gateway` and `openclaw-browser-viewer`.

### Extended thinking

OpenClaw's `thinkingDefault` is not forwarded to OpenAI-compatible providers, so the proxy needs its own configuration. Levels match Claude CLI's `--effort`: `off | low | medium | high | xhigh | max`.

Set the default in `/opt/openclaw-home/.env`:

```
DEFAULT_THINKING_BUDGET=high
```

Change it at runtime without restarting:

```bash
make think LEVEL=high
make think LEVEL=max
make think                  # show current
```

Or hit the admin endpoint directly:

```bash
curl -X POST http://localhost:3456/admin/thinking-budget \
  -H 'Content-Type: application/json' \
  -d '{"budget": "max"}'
```

Clients can also set the level per request:

- OpenAI style — `"reasoning_effort": "high"` in the request body
- Anthropic style — `"thinking": { "type": "enabled", "budget_tokens": 32000 }`
- Header — `X-Thinking-Budget: high`

#### Optional: wire up `/think` from Discord

To have Discord's `/think <level>` also update the proxy, install the bridge hook shipped with this repo:

```bash
mkdir -p ~/.openclaw/hooks/claude-max-proxy-think
cp hooks/claude-max-proxy-think/* ~/.openclaw/hooks/claude-max-proxy-think/
```

Enable it in `~/.openclaw/openclaw.json`:

```json
"hooks": {
  "internal": {
    "entries": {
      "claude-max-proxy-think": { "enabled": true }
    }
  }
}
```

Restart OpenClaw (`make restart`). Now `/think high` in Discord updates the proxy automatically.

## Add a New Repo Agent

```bash
make add-agent AGENT=<agent-id> REPO=<repo-path>
```

## Docker Stack (OpenClaw + Viewer)

Start:

```bash
make start
```

Logs:

```bash
make logs
make status
```

Stop:

```bash
make stop
```

Raw Docker Compose form:

```bash
docker compose -f docker-compose.openclaw.yml up -d
```

See:

- `docs/docker-openclaw-crewai.md` for compose details
- `.claude/docs/openclaw-integration.md` for the full Docker-only integration guide
