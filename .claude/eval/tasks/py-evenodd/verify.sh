#!/usr/bin/env bash
# Runs in the task workdir. Exit 0 = task passed.
set -e
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib.sh"
eval_python test_evenodd.py
