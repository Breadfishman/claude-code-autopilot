#!/usr/bin/env bash
set -euo pipefail

# CrewAI setup for Claude Code Autopilot
# Usage: crewai_setup.sh [project_dir]

log()  { printf "\n==> %s\n" "$*"; }
warn() { printf "\n[WARN] %s\n" "$*" >&2; }
skip() { printf "    [SKIP] %s\n" "$*"; }
has()  { command -v "$1" >/dev/null 2>&1; }

sanitize_slug() {
  local raw="$1"
  local slug
  slug="$(echo "$raw" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  if [[ -z "$slug" ]]; then
    slug="business"
  fi
  echo "$slug"
}

sanitize_py_package() {
  local raw="$1"
  local pkg
  pkg="$(echo "$raw" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g; s/^_+//; s/_+$//; s/_+/_/g')"
  if [[ -z "$pkg" ]]; then
    pkg="engineering_crew"
  fi
  if [[ "$pkg" =~ ^[0-9] ]]; then
    pkg="crew_${pkg}"
  fi
  echo "$pkg"
}

python_version_check() {
  python3 - <<'PY'
import sys
major, minor = sys.version_info[:2]
# CrewAI supports modern Python versions, but older 3.9 and below can fail.
sys.exit(0 if (major, minor) >= (3, 10) else 1)
PY
}

render_template() {
  local src="$1"
  local dst="$2"
  local project_name="$3"
  local project_slug="$4"
  local py_package="$5"

  mkdir -p "$(dirname "$dst")"
  sed \
    -e "s|{{PROJECT_NAME}}|$project_name|g" \
    -e "s|{{PROJECT_SLUG}}|$project_slug|g" \
    -e "s|{{PY_PACKAGE}}|$py_package|g" \
    "$src" > "$dst"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${1:-$(pwd)}"
CLAUDE_DIR="${PROJECT_DIR}/.claude"
TEMPLATE_DIR="${CLAUDE_DIR}/templates/crewai"
CREWAI_DIR="${PROJECT_DIR}/.crewai"

if [[ ! -d "$PROJECT_DIR" ]]; then
  warn "Project directory not found: $PROJECT_DIR"
  exit 1
fi

if [[ ! -d "$TEMPLATE_DIR" ]]; then
  warn "CrewAI templates not found: $TEMPLATE_DIR"
  exit 1
fi

if ! has python3; then
  warn "python3 is required for CrewAI setup."
  exit 1
fi

if ! python_version_check; then
  warn "Python 3.10+ is required for CrewAI setup. Current: $(python3 --version 2>/dev/null || echo 'unknown')"
  exit 1
fi

PROJECT_BASENAME="$(basename "$PROJECT_DIR")"
PROJECT_SLUG="$(sanitize_slug "$PROJECT_BASENAME")"
PY_PACKAGE="$(sanitize_py_package "${PROJECT_SLUG}_crew")"

log "Setting up CrewAI workspace..."
mkdir -p "$CREWAI_DIR"

TEMPLATE_MAP=(
  "README.md.tmpl:README.md"
  ".env.example.tmpl:.env.example"
  ".gitignore.tmpl:.gitignore"
  "pyproject.toml.tmpl:pyproject.toml"
  "cliproxyapi/config.yaml.tmpl:cliproxyapi/config.yaml"
  "cliproxyapi/docker-compose.yml.tmpl:cliproxyapi/docker-compose.yml"
  "src/package/__init__.py.tmpl:src/${PY_PACKAGE}/__init__.py"
  "src/package/crew.py.tmpl:src/${PY_PACKAGE}/crew.py"
  "src/package/main.py.tmpl:src/${PY_PACKAGE}/main.py"
  "src/package/router.py.tmpl:src/${PY_PACKAGE}/router.py"
  "src/package/tools/__init__.py.tmpl:src/${PY_PACKAGE}/tools/__init__.py"
  "src/package/tools/code_executor.py.tmpl:src/${PY_PACKAGE}/tools/code_executor.py"
  "src/package/crews/__init__.py.tmpl:src/${PY_PACKAGE}/crews/__init__.py"
  "src/package/crews/research.py.tmpl:src/${PY_PACKAGE}/crews/research.py"
  "src/package/crews/creative.py.tmpl:src/${PY_PACKAGE}/crews/creative.py"
  "src/package/server.py.tmpl:src/${PY_PACKAGE}/server.py"
  "src/package/config/agents.yaml.tmpl:src/${PY_PACKAGE}/config/agents.yaml"
  "src/package/config/tasks.yaml.tmpl:src/${PY_PACKAGE}/config/tasks.yaml"
)

for mapping in "${TEMPLATE_MAP[@]}"; do
  src_rel="${mapping%%:*}"
  dst_rel="${mapping#*:}"
  src="${TEMPLATE_DIR}/${src_rel}"
  dst="${CREWAI_DIR}/${dst_rel}"

  if [[ ! -f "$src" ]]; then
    warn "Missing template file: $src"
    exit 1
  fi

  if [[ -f "$dst" ]]; then
    skip "$dst_rel"
    continue
  fi

  render_template "$src" "$dst" "$PROJECT_BASENAME" "$PROJECT_SLUG" "$PY_PACKAGE"
  log "Created ${dst_rel}"
done

mkdir -p "$CREWAI_DIR/cliproxyapi/auths" "$CREWAI_DIR/cliproxyapi/logs"
touch "$CREWAI_DIR/cliproxyapi/auths/.gitkeep" "$CREWAI_DIR/cliproxyapi/logs/.gitkeep"
echo "$PY_PACKAGE" > "$CREWAI_DIR/.package-name"

# Create private crews directory (gitignored — put your own crews here)
mkdir -p "$CREWAI_DIR/crews/private"
if [[ ! -f "$CREWAI_DIR/crews/private/.gitkeep" ]]; then
  touch "$CREWAI_DIR/crews/private/.gitkeep"
fi
if [[ ! -f "$CREWAI_DIR/crews/private/README.md" ]]; then
  cat > "$CREWAI_DIR/crews/private/README.md" << 'CREW_README'
# Private Crews

Drop your custom crew modules here. This directory is gitignored — nothing
you put here is ever committed to the public repo.

## How to add a crew

Create a `.py` file with at least two things:

```python
CREW_NAME = "my-crew"   # routing key used in **Type:** field

def run(task_description: str, **kwargs) -> str:
    # Build your crew here using CrewAI, call external APIs, etc.
    return "crew output"
```

The loader (`crews/__init__.py`) scans this directory at startup. Any module
with a `run()` function is registered under its `CREW_NAME`.

## Routing

In your task files (e.g. `bin/tasks.md`), set the type:

```markdown
## Task: my-task
**Status:** pending
**Type:** my-crew

Description of what to do.
```

The engineering loop will dispatch this task to your private crew instead of
running it through claude-max-proxy.
CREW_README
fi

if has uv; then
  log "Preparing CrewAI virtual environment with uv..."
  if (cd "$CREWAI_DIR" && uv sync); then
    log "CrewAI dependencies synced."
  else
    warn "uv sync failed. You can retry manually with:"
    warn "  cd .crewai && uv sync"
  fi
else
  warn "uv is not installed. Install uv and then run:"
  warn "  cd .crewai && uv sync"
fi

log "CrewAI setup complete."
echo ""
echo "  Scaffold location: .crewai/"
echo "  Package: $PY_PACKAGE"
echo ""
echo "  Next steps:"
echo "    1. cd .crewai"
echo "    2. cp .env.example .env"
echo "    3. Choose one mode:"
echo "       - Direct provider keys in .env, OR"
echo "       - CLIProxyAPI: bash .claude/scripts/crewai-cliproxyapi.sh up"
echo "    4. uv sync"
echo "    5. Plan a task:"
echo "       uv run python -m ${PY_PACKAGE}.main --task \"Add JWT auth to the API\""
echo ""
echo "  Engineering loop driver (routes coding → claude-max-proxy, other types → domain crews):"
echo "    bash .claude/scripts/engineering-loop.sh bin/tasks.md"
echo ""
echo "  Add private crews (gitignored — never committed):"
echo "    .crewai/crews/private/  <- drop your own .py crew modules here"
echo "    See .crewai/crews/private/README.md for the interface."
echo ""
