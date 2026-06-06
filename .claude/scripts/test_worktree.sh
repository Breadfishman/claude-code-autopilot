#!/usr/bin/env bash
# test_worktree.sh — E2E functional tests for the `wt` worktree manager.
# Spins up a throwaway git repo, exercises every command + edge case against
# REAL git worktrees, and asserts isolation/correctness. Exit non-zero on any fail.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WT="$SCRIPT_DIR/../bin/wt"
[ -x "$WT" ] || { echo "FATAL: $WT not executable"; exit 1; }

PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
assert() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else no "$1   [cond: $2]"; fi; }

# --- fixture: a throwaway repo at $TMP/parent/myrepo, worktrees at $TMP/parent/.worktrees/myrepo
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/parent/myrepo"
WT_ROOT="$TMP/parent/.worktrees/myrepo"
REG="$WT_ROOT/.registry.tsv"
mkdir -p "$REPO"
cd "$REPO"
git init -q
git config user.email t@example.com
git config user.name tester
git symbolic-ref HEAD refs/heads/main
printf 'hello\n' >README.md
printf 'BASE=1\nPORT=3000\n' >.env.example
printf 'services:\n  web:\n    image: nginx\n' >docker-compose.yml
printf '{"name":"x"}\n' >package.json
git add -A
git commit -qm init

regoff() { awk -F'\t' -v s="$1" '$1==s{print $2}' "$REG" 2>/dev/null; }
regrows() { awk 'END{print NR+0}' "$REG" 2>/dev/null || echo 0; }

echo "== create =="
"$WT" new alpha >/dev/null 2>&1
assert "alpha worktree dir exists"           '[ -d "$WT_ROOT/alpha" ]'
assert "alpha branch agent/alpha created"     'git show-ref --verify -q refs/heads/agent/alpha'
assert "alpha .env has COMPOSE_PROJECT_NAME"  'grep -qx "COMPOSE_PROJECT_NAME=myrepo-alpha" "$WT_ROOT/alpha/.env"'
assert "alpha .env has WT_PORT_OFFSET=0"      'grep -qx "WT_PORT_OFFSET=0" "$WT_ROOT/alpha/.env"'
assert "alpha .env seeded from .env.example"  'grep -qx "BASE=1" "$WT_ROOT/alpha/.env"'
assert "alpha .worktree-info written"         '[ -f "$WT_ROOT/alpha/.worktree-info" ]'

echo "== second worktree gets distinct offset =="
"$WT" new beta >/dev/null 2>&1
assert "beta offset is 10"                    'grep -qx "WT_PORT_OFFSET=10" "$WT_ROOT/beta/.env"'
assert "beta project name distinct"           'grep -qx "COMPOSE_PROJECT_NAME=myrepo-beta" "$WT_ROOT/beta/.env"'
assert "registry has 2 rows"                  '[ "$(regrows)" -eq 2 ]'

echo "== idempotent re-create keeps offset =="
B="$(regoff alpha)"
"$WT" new alpha >/dev/null 2>&1
assert "re-create alpha keeps same offset"    '[ "$(regoff alpha)" = "$B" ]'
assert "registry still 2 rows after re-create" '[ "$(regrows)" -eq 2 ]'

echo "== working-tree isolation =="
echo "edit-from-alpha" >>"$WT_ROOT/alpha/README.md"
assert "main tree clean despite worktree edit" '[ -z "$(git -C "$REPO" status --porcelain)" ]'
assert "edit visible only in alpha worktree"   '[ -n "$(git -C "$WT_ROOT/alpha" status --porcelain)" ]'

echo "== list / info =="
assert "list shows alpha"                     '[ -n "$("$WT" list | grep "^alpha ")" ]'
assert "list shows beta"                      '[ -n "$("$WT" list | grep "^beta ")" ]'
assert "info alpha reports offset 0"          '[ -n "$("$WT" info alpha | grep "offset:  0")" ]'

echo "== input validation / error paths =="
assert "rejects slug with spaces/specials"    '! "$WT" new "bad slug!"'
assert "rejects empty slug"                   '! "$WT" new ""'
assert "rm of nonexistent fails"              '! "$WT" rm nope'
assert "info of nonexistent fails"            '! "$WT" info nope'
assert "errors when outside a git repo"       '( cd "$TMP" && ! "$WT" list )'
assert "unknown command fails"                '! "$WT" frobnicate'

echo "== remove (keep branch) + offset reclamation =="
"$WT" rm alpha --keep-branch --force >/dev/null 2>&1
assert "alpha worktree removed"               '[ ! -d "$WT_ROOT/alpha" ]'
assert "alpha branch kept (--keep-branch)"    'git -C "$REPO" show-ref --verify -q refs/heads/agent/alpha'
assert "registry dropped alpha row"           '[ -z "$(regoff alpha)" ]'
assert "git worktree list excludes alpha"     '! git -C "$REPO" worktree list | grep -q "/alpha"'

echo "== remove (delete branch) =="
"$WT" rm beta --force >/dev/null 2>&1
assert "beta branch deleted by default"       '! git -C "$REPO" show-ref --verify -q refs/heads/agent/beta'
assert "registry empty after removals"        '[ "$(regrows)" -eq 0 ]'

echo "== freed offset 0 is reused =="
"$WT" new gamma >/dev/null 2>&1
assert "gamma reclaims offset 0"              'grep -qx "WT_PORT_OFFSET=0" "$WT_ROOT/gamma/.env"'
"$WT" rm gamma --force >/dev/null 2>&1

echo "== prune removes stale entries =="
"$WT" new delta >/dev/null 2>&1
rm -rf "$WT_ROOT/delta"            # simulate a manually-deleted worktree
"$WT" prune >/dev/null 2>&1
assert "prune drops stale delta entry"        '[ -z "$(regoff delta)" ]'

echo "== concurrency: parallel creates get distinct offsets =="
"$WT" new c1 >/dev/null 2>&1 &
"$WT" new c2 >/dev/null 2>&1 &
"$WT" new c3 >/dev/null 2>&1 &
wait
O1="$(regoff c1)"; O2="$(regoff c2)"; O3="$(regoff c3)"
assert "all 3 parallel creates registered"    '[ -n "$O1" ] && [ -n "$O2" ] && [ -n "$O3" ]'
assert "parallel offsets are all distinct"    '[ "$O1" != "$O2" ] && [ "$O2" != "$O3" ] && [ "$O1" != "$O3" ]'
for s in c1 c2 c3; do "$WT" rm "$s" --force >/dev/null 2>&1; done

echo "== --no-bootstrap skips env wiring =="
"$WT" new bare --no-bootstrap >/dev/null 2>&1
assert "bare worktree exists"                 '[ -d "$WT_ROOT/bare" ]'
assert "bare worktree has no .env"            '[ ! -f "$WT_ROOT/bare/.env" ]'
"$WT" rm bare --force >/dev/null 2>&1

echo "== --base creates from a given ref =="
git -C "$REPO" branch feature-x >/dev/null 2>&1
git -C "$REPO" checkout -q feature-x
echo "on-feature" >>"$REPO/README.md"; git -C "$REPO" commit -aqm feat
git -C "$REPO" checkout -q main
"$WT" new fromfeat --base feature-x >/dev/null 2>&1
assert "worktree from --base has feature commit" 'grep -q "on-feature" "$WT_ROOT/fromfeat/README.md"'
"$WT" rm fromfeat --force >/dev/null 2>&1

echo
echo "==================================================="
printf "  RESULT: %d passed, %d failed\n" "$PASS" "$FAIL"
echo "==================================================="
[ "$FAIL" -eq 0 ]
