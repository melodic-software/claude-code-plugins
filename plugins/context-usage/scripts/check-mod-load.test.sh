#!/usr/bin/env bash
# test-scope: plugins/context-usage/prerequisites.json
# Tests for check-mod-load.sh against a fixture plugin whose floor is 2.1.287.
# 2.1.1000 and 2.1.9 are the cases a string compare gets wrong.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/p/scripts" "$WORK/bin"
cp "$HERE/check-mod-load.sh" "$WORK/p/scripts/"
CHECK="$WORK/p/scripts/check-mod-load.sh"
set_floor() {
  printf '{"requires":[\n{\n"id": "node",\n"detect": {"version": {"min": "9.9.9"}}\n},\n{\n"id": "claude",\n"detect": {"version": {\n"min": "%s"\n}}\n}\n]}\n' "$1" >"$WORK/p/prerequisites.json"
}
set_floor 2.1.287
fails=0
expect() { # <name> <want-exit> <want-output-fragment>
  if [[ "$code" == "$2" && "$out" == *"$3"* ]]; then
    echo "PASS: $1"
  else
    echo "FAIL: $1 (exit $code): $out" >&2
    fails=1
  fi
}
stub() {
  printf '#!/bin/sh\necho "%s (Claude Code)"\n' "$1" >"$WORK/bin/claude"
  chmod +x "$WORK/bin/claude"
  out="$(PATH="$WORK/bin:$PATH" bash "$CHECK")"
  code=$?
}

stub 2.1.287
expect "the floor itself passes" 0 $'mods-floor\tPASS\tclaude 2.1.287 meets the mods floor 2.1.287'
stub 2.1.286
expect "one below the floor fails" 1 $'mods-floor\tFAIL\tmods off: claude 2.1.286 is older than the mods floor 2.1.287'
stub 2.1.1000
expect "the floor compares numerically" 0 $'mods-floor\tPASS\tclaude 2.1.1000'
stub 2.1.9
expect "2.1.9 is below the floor 2.1.287" 1 $'mods-floor\tFAIL\tmods off: claude 2.1.9 is older than the mods floor 2.1.287'
stub 2.2.0
expect "2.2.0 is above the floor 2.1.287" 0 $'mods-floor\tPASS\tclaude 2.2.0 meets the mods floor 2.1.287'
set_floor 2.1.9
stub 2.1.287
expect "2.1.287 is above the floor 2.1.9" 0 $'mods-floor\tPASS\tclaude 2.1.287 meets the mods floor 2.1.9'
set_floor 2.1.287
stub 2.1.1000
expect "the session row names the status tool" 0 $'session\tINFO\tlook for mcp__context-usage__status'

rm -f "$WORK/bin/claude"
bin="$WORK/noclaude"
mkdir -p "$bin"
for t in bash cat dirname sed printf; do
  p="$(command -v "$t")" && [[ "$p" == /* ]] && ln -sf "$p" "$bin/$t"
done
out="$(PATH="$bin" "$bin/bash" "$CHECK")"
code=$?
expect "no claude fails" 1 $'mods-floor\tFAIL\tclaude did not report a version'

bash "$CHECK" --root /tmp >/dev/null 2>&1
code=$?
out=""
expect "any argument exits 2" 2 ""

exit "$fails"
