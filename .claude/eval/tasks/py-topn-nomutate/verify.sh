#!/usr/bin/env bash
# Runs in the workdir. The comprehensive test is hidden (not given to the agent).
set -e
PYTHONPATH="$PWD" python3 "$(dirname "$0")/hidden/test_topn.py"
