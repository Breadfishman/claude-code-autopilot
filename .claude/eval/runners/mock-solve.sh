#!/usr/bin/env bash
# Mock runner — simulates a PERFECT agent by applying the task's reference
# solution. Used to test the harness plumbing deterministically.
# args: <workdir> <task_dir> <metrics_file>
set -euo pipefail
workdir="$1"; task_dir="$2"; metrics="${3:-/dev/null}"
[ -d "$task_dir/solution" ] && cp -R "$task_dir/solution/." "$workdir/"
printf 'tokens=0\n' >"$metrics"
