#!/usr/bin/env bash
set -e
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/lib.sh"
eval_python test_groupsum.py
