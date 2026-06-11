# lib.sh — shared helpers for the eval harness (sourced, not executed).
#
# Task dependency convention: a task dir may declare host requirements in a
# `requires` file (one command per line, `#` comments allowed). Tasks whose
# commands are missing on this host are skipped LOUDLY by the harness, so a
# broken environment can never masquerade as agent failures in the results.

# eval_missing_deps <task_dir> — print each missing required command, one per line.
eval_missing_deps() {
  local task_dir="$1" cmd
  [ -f "$task_dir/requires" ] || return 0
  while IFS= read -r cmd; do
    case "$cmd" in ''|\#*) continue ;; esac
    command -v "$cmd" >/dev/null 2>&1 || printf '%s\n' "$cmd"
  done <"$task_dir/requires"
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
