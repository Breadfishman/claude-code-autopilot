#!/usr/bin/env bash
# self-update.sh — re-run the claude-code-autopilot installer with the exact
# flags recorded at install time (.claude/install.manifest), so refreshing the
# kit is one repeatable command instead of a remembered curl invocation.
#
# Usage: self-update.sh [install-root]
#   install-root  directory containing .claude/ (default: this script's root)
#
# Also available as `make self-update` on OpenClaw installs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
MANIFEST="$ROOT/.claude/install.manifest"

if [[ ! -f "$MANIFEST" ]]; then
  echo "self-update: no manifest at $MANIFEST" >&2
  echo "self-update: re-run the curl installer once (it now records one), e.g.:" >&2
  echo "  curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/main/install.sh | bash -s -- --repo <owner>/<repo> --force ..." >&2
  exit 1
fi

CCA_REPO="" CCA_REF="main" CCA_DEST=""
CCA_BOOTSTRAP_LINUX="0" CCA_NO_EXTRAS="0" CCA_WITH_OPENCLAW="0" CCA_WITH_CREWAI="0"
# shellcheck source=/dev/null
. "$MANIFEST"
[[ -n "$CCA_REPO" ]] || { echo "self-update: manifest is missing CCA_REPO: $MANIFEST" >&2; exit 1; }

args=(--repo "$CCA_REPO" --ref "$CCA_REF" --dest "${CCA_DEST:-$ROOT}" --force)
[[ "$CCA_BOOTSTRAP_LINUX" == "1" ]] && args+=(--bootstrap-linux)
[[ "$CCA_NO_EXTRAS" == "1" ]] && args+=(--no-extras)
[[ "$CCA_WITH_OPENCLAW" == "1" ]] && args+=(--with-openclaw)
[[ "$CCA_WITH_CREWAI" == "1" ]] && args+=(--with-crewai)

INSTALLER_URL="https://raw.githubusercontent.com/${CCA_REPO}/${CCA_REF}/install.sh"
echo "self-update: ${CCA_REPO}@${CCA_REF} -> ${CCA_DEST:-$ROOT}"
echo "self-update: flags: ${args[*]}"

tmp_installer="$(mktemp)"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$INSTALLER_URL" -o "$tmp_installer"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$tmp_installer" "$INSTALLER_URL"
else
  echo "self-update: need curl or wget" >&2
  rm -f "$tmp_installer"
  exit 1
fi

# exec into a fresh shell: the installer is about to overwrite THIS script,
# and bash must not keep reading a file that changes underneath it. The
# wrapper also cleans up the downloaded installer.
exec bash -c 'bash "$1" "${@:2}"; rc=$?; rm -f "$1"; exit $rc' self-update "$tmp_installer" "${args[@]}"
