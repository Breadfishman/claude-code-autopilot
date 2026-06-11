#!/usr/bin/env bash
# Runs in the workdir. The comprehensive test is hidden (not given to the agent).
set -e
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib.sh"
PYTHONPATH="$PWD" eval_python "$(dirname "$0")/hidden/test_split.py"
