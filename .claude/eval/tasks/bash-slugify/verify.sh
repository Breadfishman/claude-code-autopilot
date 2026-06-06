#!/usr/bin/env bash
# Runs in the task workdir. Exit 0 = task passed.
set -e
check() {
  local got; got="$(bash slugify.sh "$1")"
  [ "$got" = "$2" ] || { echo "slugify('$1') = '$got', want '$2'"; exit 1; }
}
check "Hello World!" "hello-world"
check "  Trim  Me  " "trim-me"
check "Foo_Bar.Baz"  "foo-bar-baz"
echo "OK"
