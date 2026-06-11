# lib.sh — shared helpers for the eval harness (sourced, not executed).
#
# Task dependency convention: a task dir may declare host requirements in a
# `requires` file (one requirement per line, `#` comments allowed). A line may
# list alternatives separated by `|` (e.g. `uv|python3`): the requirement is
# met if ANY alternative is on PATH. Tasks whose requirements are unmet are
# skipped LOUDLY by the harness, so a broken environment can never masquerade
# as agent failures in the results.

# eval_dep_met <requirement> — succeed iff any `|`-separated alternative is on PATH.
eval_dep_met() {
  local alt
  IFS='|' read -ra _eval_alts <<<"$1"
  for alt in "${_eval_alts[@]}"; do
    command -v "$alt" >/dev/null 2>&1 && return 0
  done
  return 1
}

# eval_missing_deps <task_dir> — print each unmet requirement line, one per line.
eval_missing_deps() {
  local task_dir="$1" req
  [ -f "$task_dir/requires" ] || return 0
  while IFS= read -r req; do
    case "$req" in ''|\#*) continue ;; esac
    eval_dep_met "$req" || printf '%s\n' "$req"
  done <"$task_dir/requires"
}

# eval_python [args...] — run Python via the best toolchain on this host.
# Prefers uv (provisions an interpreter on demand); falls back to system
# python3. Single source of truth for every verify.sh and runner, and the
# runtime counterpart of the `uv|python3` requires line.
eval_python() {
  if command -v uv >/dev/null 2>&1; then
    uv run --quiet --no-project python "$@"
  elif command -v python3 >/dev/null 2>&1; then
    python3 "$@"
  else
    echo "eval: neither uv nor python3 is available on this host" >&2
    return 127
  fi
}

# eval_task_runnable <task_dir> — succeed iff all declared deps are present.
eval_task_runnable() { [ -z "$(eval_missing_deps "$1")" ]; }

# eval_filter_runnable <tasks_dir> <task ids...> — echo the runnable subset,
# logging a SKIP line to stderr for each task with unmet deps.
eval_filter_runnable() {
  local tasks_dir="$1" t miss; shift
  for t in "$@"; do
    miss="$(eval_missing_deps "$tasks_dir/$t" | tr '\n' ' ')"
    if [ -n "$miss" ]; then
      printf 'eval: SKIP task %-22s (missing on this host: %s)\n' "'$t'" "${miss% }" >&2
    else
      printf '%s\n' "$t"
    fi
  done
}
