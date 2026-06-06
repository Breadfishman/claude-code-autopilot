#!/usr/bin/env bash
# Mock runner — simulates a FAILING agent that changes nothing. Used to test
# that the harness correctly records failures.
# args: <workdir> <task_dir> <metrics_file>
set -euo pipefail
metrics="${3:-/dev/null}"
printf 'tokens=0\n' >"$metrics"
