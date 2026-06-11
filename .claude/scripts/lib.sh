#!/usr/bin/env bash
# lib.sh — shared helpers for .claude/scripts/*. Source it, don't execute:
#   . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# env_file_get VAR FILE — print VAR's value from a dotenv-style FILE.
# Reads KEY=value lines; handles an `export ` prefix, surrounding single or
# double quotes, leading whitespace, and CRLF endings; skips comments and
# blank lines. Last assignment wins (docker compose semantics). Returns 1
# with no output when FILE is missing or VAR is not set in it.
env_file_get() {
  local var="$1" file="$2" line value found=1
  [[ -n "$var" && -f "$file" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line#export }"
    [[ "$line" == "$var="* ]] || continue
    value="${line#*=}"
    if [[ "$value" == \"*\" && ${#value} -ge 2 ]]; then
      value="${value#\"}" value="${value%\"}"
    elif [[ "$value" == \'*\' && ${#value} -ge 2 ]]; then
      value="${value#\'}" value="${value%\'}"
    fi
    found=0
  done <"$file"
  [[ "$found" -eq 0 ]] && printf '%s\n' "$value"
  return "$found"
}

# env_resolve VAR FILE DEFAULT — resolve VAR with the standard precedence:
# process environment (non-empty) > dotenv FILE > DEFAULT. Always prints a
# value (possibly an empty DEFAULT) and returns 0.
env_resolve() {
  local var="$1" file="$2" default="${3-}" value
  if [[ -n "${!var-}" ]]; then
    printf '%s\n' "${!var}"
  elif value="$(env_file_get "$var" "$file")"; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$default"
  fi
}
