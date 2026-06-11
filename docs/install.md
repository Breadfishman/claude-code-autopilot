# Install and Maintenance

This page covers install modes, updates, and common setup files.

## Install Options

### Full bootstrap (Linux)

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force --bootstrap-linux
```

### Kit only

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force
```

### Update an existing install

Run the same install command with `--force`.

Use `--with-openclaw` to configure the Docker-only OpenClaw stack and wrapper.
If you omit `--dest`, the OpenClaw install defaults to `/opt/openclaw-home`.
Use `--with-crewai` when you want to scaffold or refresh `.crewai/*` assets.

## Installer Flags

| Option | Description |
|--------|-------------|
| `--repo <owner/repo>` | Source repo (required) |
| `--ref <branch\|tag\|sha>` | Git ref (default: `main`) |
| `--dest <path>` | Destination (default: current directory, or `/opt/openclaw-home` with `--with-openclaw`) |
| `--force` | Overwrite existing `.claude/` (preserves logs) |
| `--bootstrap-linux` | Full bootstrap (devtools + extras) |
| `--no-extras` | Skip wshobson agents/commands |
| `--with-openclaw` | Configure Docker-only OpenClaw and install the host wrapper |
| `--with-crewai` | Run CrewAI setup and scaffold `.crewai/` |

## OpenClaw Environment File

The OpenClaw Docker stack uses `.env.example` as the canonical reference. Copy it to `.env` if you need to set:

- `HOST_REPOS_DIR`
- gateway and viewer ports
- git author and committer identity
- `OPENCLAW_MODEL_PRIMARY=claude-max-proxy/claude-opus`
- `OPENCLAW_THINKING_DEFAULT=high`
- `OPENCLAW_ANTHROPIC_SETUP_TOKEN`
- `ANTHROPIC_API_KEY` / `OPENAI_API_KEY`
- browser width and downloads directory

Discord bot tokens are not part of the global `.env` file. Configure Discord interactively per bot/channel with:

```bash
bash /opt/openclaw-home/.claude/bootstrap/openclaw_discord_setup.sh
```

By default, the stack automatically uses `~/.openclaw` on the host. Only set `OPENCLAW_HOST_STATE_DIR` if you want to override that default.

If you use the default Docker/OpenClaw install path, the files live under `/opt/openclaw-home`:

```bash
cp /opt/openclaw-home/.env.example /opt/openclaw-home/.env
cd /opt/openclaw-home
openclaw up
```

## Git Hygiene

Add these to your project `.gitignore` if needed:

```gitignore
.claude/logs/
.claude/context/*
!.claude/context/templates/
.claude/vendor/
```
