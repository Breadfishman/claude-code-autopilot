# Docker Stacks: OpenClaw and CrewAI

OpenClaw and CrewAI are intentionally split into separate compose files so users can run only what they need.

## Files

- `docker-compose.openclaw.yml`
- `docker-compose.crewai.yml`
- `docker/openclaw/Dockerfile`
- `docker/openclaw/entrypoint.sh`
- `docker/browser-viewer/Dockerfile`
- `docker/browser-viewer/entrypoint.sh`
- `docker/crewai/Dockerfile`
- `docker/crewai/entrypoint.sh`
- `docker/cliproxyapi/config.yaml` (optional proxy profile for CrewAI stack)
- `.env.example`

## Prerequisites

- Docker + Docker Compose plugin
- Host repos under `/opt/repos` (or set `HOST_REPOS_DIR`)
- Host OpenClaw state under `~/.openclaw` by default
- Optional: copy `.env.example` to `.env` for git identity, auth tokens, and port overrides
- For Claude primaries (default `claude-max-proxy/claude-opus`), keep `OPENCLAW_THINKING_DEFAULT=high` unless you intentionally want a lower reasoning budget

## OpenClaw Stack (Gateway + Browser Viewer)

Start:

```bash
make start
# or: docker compose -f docker-compose.openclaw.yml up -d
```

Logs/status:

```bash
make logs
make status
```

Viewer:

```bash
make viewer-url
```

Subscription auth inside Docker:

```bash
make auth-anthropic
make auth-openai
```

Stop:

```bash
make stop
```

## Mounting Repos

The OpenClaw stack binds:

- `${OPENCLAW_HOST_STATE_DIR:-$HOME/.openclaw}` (host) -> `/home/node/.openclaw` (container)
- `/opt/repos` (host) -> `/opt/repos` (container)

Override host path:

```bash
HOST_REPOS_DIR=/path/to/repos docker compose -f docker-compose.openclaw.yml up -d
```

## Browser Viewer and Manual Login

The gateway container runs Chromium on a virtual display. The `openclaw-browser-viewer` service exposes a noVNC UI so you can:

- watch browser automation in real time
- take control for manual login or 2FA
- leave the authenticated browser state in the persistent OpenClaw volume

Default viewer URL:

- `http://127.0.0.1:6080/vnc.html`

## CrewAI Stack (Only CrewAI)

Start runner:

```bash
docker compose -f docker-compose.crewai.yml up -d crewai-runner
```

Optional proxy profile:

```bash
docker compose -f docker-compose.crewai.yml --profile proxy up -d cliproxyapi
```

Run a repo workflow:

```bash
docker exec -it crewai-runner crewai-entrypoint run /opt/repos/<repo-name> --goal "Increase traction and paying customers"
```
