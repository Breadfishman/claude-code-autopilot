#!/usr/bin/env bash
# test_eval.sh — E2E tests for the eval harness using deterministic mock runners.
# Proves the plumbing: full matrix runs, pass/fail recorded correctly, fixtures
# are never mutated, and the scoreboard aggregates. Exit non-zero on any fail.
set -uo pipefail

EVAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN="$EVAL_DIR/run-eval.sh"
# shellcheck source=lib.sh
. "$EVAL_DIR/lib.sh"

PASS=0 FAIL=0 SKIP=0
ok() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
skip() { SKIP=$((SKIP + 1)); printf '  \033[33mSKIP\033[0m %s (%s)\n' "$1" "$2"; }
assert() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else no "$1   [cond: $2]"; fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
SOLVE="$TMP/solve.tsv"; NOOP="$TMP/noop.tsv"

seed_sum() { find "$EVAL_DIR/tasks" -path '*/seed/*' -type f -exec cat {} + | cksum; }
BEFORE="$(seed_sum)"

bash "$RUN" --runner mock-solve --out "$SOLVE" --quiet >/dev/null 2>&1
bash "$RUN" --runner mock-noop  --out "$NOOP"  --quiet >/dev/null 2>&1

NMODES="$(awk -F'\t' 'NF{n++} END{print n+0}' "$EVAL_DIR/modes/modes.tsv")"
# Count only tasks runnable on this host (same deps gating run-eval.sh applies).
NTASKS=0
for d in "$EVAL_DIR"/tasks/*/; do eval_task_runnable "$d" && NTASKS=$((NTASKS + 1)); done
EXPECT=$((NMODES * NTASKS))

cell()      { awk -F'\t' -v m="$1" -v t="$2" 'NR>1 && $1==m && $2==t{print $4; exit}' "$3"; }
passcount() { awk -F'\t' 'NR>1 && $4==1{c++} END{print c+0}' "$1"; }
rowcount()  { awk -F'\t' 'NR>1{c++} END{print c+0}' "$1"; }

assert "results header has 6 columns"        '[ "$(head -1 "$SOLVE" | awk -F"\t" "{print NF}")" -eq 6 ]'
assert "matrix size is modes*tasks (>0)"     '[ "$EXPECT" -gt 0 ]'
assert "mock-solve ran the full matrix"      '[ "$(rowcount "$SOLVE")" -eq "$EXPECT" ]'
assert "mock-noop ran the full matrix"       '[ "$(rowcount "$NOOP")" -eq "$EXPECT" ]'
assert "mock-solve passes every cell"        '[ "$(passcount "$SOLVE")" -eq "$EXPECT" ]'
assert "mock-noop fails every cell"          '[ "$(passcount "$NOOP")" -eq 0 ]'
if eval_task_runnable "$EVAL_DIR/tasks/py-evenodd"; then
  assert "py-evenodd passes under solve"       '[ "$(cell autopilot py-evenodd "$SOLVE")" = "1" ]'
  assert "py-evenodd fails under noop"         '[ "$(cell autopilot py-evenodd "$NOOP")" = "0" ]'
else
  skip "py-evenodd cell assertions" "python3 not on this host"
fi
assert "bash-slugify passes under solve"     '[ "$(cell minimal bash-slugify "$SOLVE")" = "1" ]'
assert "all modes appear in results"         '[ "$(tail -n +2 "$SOLVE" | cut -f1 | sort -u | wc -l | tr -d " ")" -eq "$NMODES" ]'
assert "fixtures NOT mutated by a run"       '[ "$(seed_sum)" = "$BEFORE" ]'
assert "unknown runner errors out"           '! bash "$RUN" --runner nope --out "$TMP/x.tsv" --quiet'
assert "--modes subset is respected"         '[ "$(bash "$RUN" --runner mock-solve --modes minimal --out "$TMP/m.tsv" --quiet >/dev/null 2>&1; rowcount "$TMP/m.tsv")" -eq "$NTASKS" ]'
assert "--tasks subset is respected"         '[ "$(bash "$RUN" --runner mock-solve --tasks bash-slugify --out "$TMP/t.tsv" --quiet >/dev/null 2>&1; rowcount "$TMP/t.tsv")" -eq "$NMODES" ]'
assert "bad --reps is rejected"              '! bash "$RUN" --runner mock-solve --reps abc --out "$TMP/r.tsv" --quiet'
assert "scoreboard shows overall row"        '[ -n "$(bash "$RUN" --runner mock-solve --out "$TMP/sb.tsv" 2>/dev/null | grep overall)" ]'

echo
echo "==================================================="
printf "  RESULT: %d passed, %d failed, %d skipped\n" "$PASS" "$FAIL" "$SKIP"
echo "==================================================="
[ "$FAIL" -eq 0 ]
