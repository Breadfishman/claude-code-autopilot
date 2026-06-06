#!/usr/bin/env bash
# test_eval.sh — E2E tests for the eval harness using deterministic mock runners.
# Proves the plumbing: full matrix runs, pass/fail recorded correctly, fixtures
# are never mutated, and the scoreboard aggregates. Exit non-zero on any fail.
set -uo pipefail

EVAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN="$EVAL_DIR/run-eval.sh"

PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
assert() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else no "$1   [cond: $2]"; fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
SOLVE="$TMP/solve.tsv"; NOOP="$TMP/noop.tsv"

seed_sum() { find "$EVAL_DIR/tasks" -path '*/seed/*' -type f -exec cat {} + | cksum; }
BEFORE="$(seed_sum)"

bash "$RUN" --runner mock-solve --out "$SOLVE" --quiet >/dev/null 2>&1
bash "$RUN" --runner mock-noop  --out "$NOOP"  --quiet >/dev/null 2>&1

NMODES="$(awk -F'\t' 'NF{n++} END{print n+0}' "$EVAL_DIR/modes/modes.tsv")"
NTASKS="$(ls -d "$EVAL_DIR"/tasks/*/ 2>/dev/null | wc -l | tr -d ' ')"
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
assert "py-evenodd passes under solve"       '[ "$(cell autopilot py-evenodd "$SOLVE")" = "1" ]'
assert "py-evenodd fails under noop"         '[ "$(cell autopilot py-evenodd "$NOOP")" = "0" ]'
assert "bash-slugify passes under solve"     '[ "$(cell minimal bash-slugify "$SOLVE")" = "1" ]'
assert "all modes appear in results"         '[ "$(tail -n +2 "$SOLVE" | cut -f1 | sort -u | wc -l | tr -d " ")" -eq "$NMODES" ]'
assert "fixtures NOT mutated by a run"       '[ "$(seed_sum)" = "$BEFORE" ]'
assert "unknown runner errors out"           '! bash "$RUN" --runner nope --out "$TMP/x.tsv" --quiet'
assert "--modes subset is respected"         '[ "$(bash "$RUN" --runner mock-solve --modes minimal --out "$TMP/m.tsv" --quiet >/dev/null 2>&1; rowcount "$TMP/m.tsv")" -eq "$NTASKS" ]'
assert "--tasks subset is respected"         '[ "$(bash "$RUN" --runner mock-solve --tasks py-evenodd --out "$TMP/t.tsv" --quiet >/dev/null 2>&1; rowcount "$TMP/t.tsv")" -eq "$NMODES" ]'
assert "scoreboard shows overall row"        '[ -n "$(bash "$RUN" --runner mock-solve --out "$TMP/sb.tsv" 2>/dev/null | grep overall)" ]'

echo
echo "==================================================="
printf "  RESULT: %d passed, %d failed\n" "$PASS" "$FAIL"
echo "==================================================="
[ "$FAIL" -eq 0 ]
