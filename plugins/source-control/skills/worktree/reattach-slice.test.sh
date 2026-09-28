#!/usr/bin/env bash
# worktree action gates stay inside the compaction re-attach slice (#4255).
set -uo pipefail

HUB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/SKILL.md"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

slice="$(head -c 20000 "$HUB")"
tail=""
if [[ "$(wc -c <"$HUB" | tr -d ' ')" -gt 20000 ]]; then
  tail="$(tail -c +20001 "$HUB")"
fi

assert_gate() {
  local phrase="$1"
  if [[ "$slice" == *"$phrase"* && "$tail" != *"$phrase"* ]]; then
    ok "inside the re-attach slice: $phrase"
  else
    fail "not confined to the re-attach slice: $phrase"
  fi
}

assert_gate 'Pass this session'"'"'s id on every direct helper invocation.'
assert_gate 'Never remove a worktree, and never emit its `git branch -D`, while its work is stranded'
assert_gate 'never nested inside any repository'"'"'s tree'

echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
