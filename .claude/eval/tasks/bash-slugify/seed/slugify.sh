#!/usr/bin/env bash
# BUG: only swaps spaces for hyphens — no lowercasing, no punctuation handling.
printf '%s\n' "${1// /-}"
