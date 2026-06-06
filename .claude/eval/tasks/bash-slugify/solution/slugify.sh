#!/usr/bin/env bash
s="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-')"
s="$(printf '%s' "$s" | sed -E 's/-+/-/g; s/^-//; s/-$//')"
printf '%s\n' "$s"
