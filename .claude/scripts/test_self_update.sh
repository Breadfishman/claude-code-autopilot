#!/usr/bin/env bash
# test_self_update.sh — E2E functional tests for self-update.sh.
# Covers the no-manifest guidance (must print a runnable command, never
# <owner>/<repo> placeholders) and the manifest replay path, offline via a
# stub curl that serves a fake installer. Exit non-zero on any fail.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SU="$SCRIPT_DIR/self-update.sh"
[ -f "$SU" ] || { echo "FATAL: $SU not found"; exit 1; }

PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
assert() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else no "$1   [cond: $2]"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "== no manifest: prints a runnable installer command =="
ROOT1="$TMP/bare-install"
mkdir -p "$ROOT1/.claude"
set +e
OUT1="$(bash "$SU" "$ROOT1" 2>&1)"
RC1=$?
set -e
assert "exits non-zero"                      '[ "$RC1" -ne 0 ]'
assert "mentions the missing manifest"       'grep -q "no manifest" <<<"$OUT1"'
assert "suggests a curl installer command"   'grep -q "curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh" <<<"$OUT1"'
assert "fills in --repo with a real repo"    'grep -q -- "--repo NorkzYT/claude-code-autopilot" <<<"$OUT1"'
assert "fills in --dest with this root"      'grep -q -- "--dest $ROOT1" <<<"$OUT1"'
assert "no <owner>/<repo> placeholders"      '! grep -q "<owner>" <<<"$OUT1"'
assert "plain install omits --with-openclaw" '! grep -q -- "--with-openclaw" <<<"$OUT1"'

echo "== no manifest on an OpenClaw install: suggests --with-openclaw =="
ROOT2="$TMP/openclaw-install"
mkdir -p "$ROOT2/.claude" "$ROOT2/docker/openclaw"
set +e
OUT2="$(bash "$SU" "$ROOT2" 2>&1)"
set -e
assert "openclaw markers add --with-openclaw" 'grep -q -- "--with-openclaw" <<<"$OUT2"'

echo "== no manifest: canonical repo overridable for forks =="
set +e
OUT3="$(CCA_CANONICAL_REPO=someone/forked-kit bash "$SU" "$ROOT1" 2>&1)"
set -e
assert "override changes suggested repo"     'grep -q -- "--repo someone/forked-kit" <<<"$OUT3"'

echo "== manifest replay: re-runs installer with recorded flags =="
ROOT4="$TMP/recorded-install"
mkdir -p "$ROOT4/.claude"
cat >"$ROOT4/.claude/install.manifest" <<'EOF'
# claude-code-autopilot install manifest (shell-sourceable).
CCA_REPO='NorkzYT/claude-code-autopilot'
CCA_REF='main'
CCA_DEST='/tmp/somewhere'
CCA_BOOTSTRAP_LINUX='1'
CCA_NO_EXTRAS='0'
CCA_WITH_OPENCLAW='1'
CCA_WITH_CREWAI='0'
EOF
# Stub curl: serve a fake installer that just echoes its argv, so the replay
# is observable without touching the network.
BIN="$TMP/bin"
mkdir -p "$BIN"
cat >"$BIN/curl" <<'EOF'
#!/usr/bin/env bash
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2;;
    *) shift;;
  esac
done
[ -n "$out" ] || exit 1
printf '#!/usr/bin/env bash\nprintf "FAKE-INSTALLER:%%s\\n" "$*"\n' >"$out"
EOF
chmod +x "$BIN/curl"
set +e
OUT4="$(PATH="$BIN:$PATH" bash "$SU" "$ROOT4" 2>&1)"
RC4=$?
set -e
assert "replay exits zero"                   '[ "$RC4" -eq 0 ]'
assert "replays --repo from manifest"        'grep -q -- "--repo NorkzYT/claude-code-autopilot" <<<"$OUT4"'
assert "replays --ref from manifest"         'grep -q -- "--ref main" <<<"$OUT4"'
assert "replays recorded --dest"             'grep -q -- "--dest /tmp/somewhere" <<<"$OUT4"'
assert "always passes --force"               'grep -q -- "--force" <<<"$OUT4"'
assert "replays --bootstrap-linux"           'grep -q -- "--bootstrap-linux" <<<"$OUT4"'
assert "replays --with-openclaw"             'grep -q -- "--with-openclaw" <<<"$OUT4"'
assert "omits flags recorded as 0"           '! grep -q -- "--with-crewai" <<<"$OUT4"'
assert "installer actually executed"         'grep -q "FAKE-INSTALLER:" <<<"$OUT4"'

echo "== manifest replay: empty CCA_DEST falls back to install root =="
ROOT5="$TMP/no-dest-install"
mkdir -p "$ROOT5/.claude"
sed "s|^CCA_DEST=.*|CCA_DEST=''|" "$ROOT4/.claude/install.manifest" >"$ROOT5/.claude/install.manifest"
set +e
OUT5="$(PATH="$BIN:$PATH" bash "$SU" "$ROOT5" 2>&1)"
set -e
assert "empty dest replaced by root"         'grep -q -- "--dest $ROOT5" <<<"$OUT5"'

echo "== malformed manifest: missing CCA_REPO is rejected =="
ROOT6="$TMP/broken-install"
mkdir -p "$ROOT6/.claude"
printf "CCA_REF='main'\n" >"$ROOT6/.claude/install.manifest"
set +e
OUT6="$(bash "$SU" "$ROOT6" 2>&1)"
RC6=$?
set -e
assert "missing CCA_REPO exits non-zero"     '[ "$RC6" -ne 0 ]'
assert "missing CCA_REPO names the problem"  'grep -q "missing CCA_REPO" <<<"$OUT6"'

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
