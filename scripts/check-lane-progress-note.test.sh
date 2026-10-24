#!/usr/bin/env bash
# Tests for scripts/check-lane-progress-note.sh.
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-lane-progress-note.sh"
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
fail=0

expect() {
  local want=$1 name=$2
  shift 2
  local got=0
  "$@" >/dev/null 2>&1 || got=$?
  if [ "$got" != "$want" ]; then
    echo "FAIL: $name: exit $got, want $want"
    fail=1
  else
    echo "ok: $name"
  fi
}

expect 0 "a tree with no note passes" env CHECK_DATA_ROOT="$dir" bash "$script" --check
touch "$dir/.lane-progress.md"
expect 1 "a tree that keeps the note fails" env CHECK_DATA_ROOT="$dir" bash "$script" --check
expect 2 "no --check flag is a usage error" env CHECK_DATA_ROOT="$dir" bash "$script"
exit "$fail"
