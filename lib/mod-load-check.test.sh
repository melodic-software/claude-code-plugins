#!/usr/bin/env bash
# test-scope: plugins/*/scripts/check-mod-load.sh
# test-scope: plugins/context-usage/prerequisites.json plugins/rate-limits/prerequisites.json
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fails=0
expect() {
  if [[ "$code" == "$2" && "$out" == *"$3"* ]]; then
    echo "PASS: $1"
  else
    echo "FAIL: $1 (exit $code): $out" >&2
    fails=1
  fi
}

shopt -s nullglob
carriers=("$REPO"/plugins/*/scripts/check-mod-load.sh)
shopt -u nullglob
if ((${#carriers[@]} == 0)); then
  echo "FAIL: no plugin carries scripts/check-mod-load.sh" >&2
  exit 1
fi

nobin="$WORK/noclaude"
mkdir -p "$nobin" "$WORK/bin"
for t in bash cat dirname sed printf; do
  p="$(command -v "$t")" && [[ "$p" == /* ]] && ln -sf "$p" "$nobin/$t"
done

for script in "${carriers[@]}"; do
  plugin="${script%/scripts/check-mod-load.sh}"
  plugin="${plugin##*/}"
  dir="$WORK/$plugin"
  mkdir -p "$dir/scripts" "$dir/lib"
  cp "$script" "$dir/scripts/"
  cp "$HERE/mod-load-check.sh" "$dir/lib/"
  CHECK="$dir/scripts/check-mod-load.sh"
  set_floor() {
    printf '{"requires":[\n{\n"id": "node",\n"detect": {"version": {"min": "9.9.9"}}\n},\n{\n"id": "claude",\n"detect": {"version": {\n"min": "%s"\n}}\n}\n]}\n' "$1" >"$dir/prerequisites.json"
  }
  stub() {
    printf '#!/bin/sh\necho "%s (Claude Code)"\n' "$1" >"$WORK/bin/claude"
    chmod +x "$WORK/bin/claude"
    out="$(PATH="$WORK/bin:$PATH" bash "$CHECK")"
    code=$?
  }

  set_floor 2.1.287
  stub 2.1.287
  expect "$plugin: the floor itself passes" 0 $'mods-floor\tPASS\tclaude 2.1.287 meets the mods floor 2.1.287'
  stub 2.1.286
  expect "$plugin: one below the floor fails" 1 $'mods-floor\tFAIL\tmods off: claude 2.1.286 is older than the mods floor 2.1.287, unsupported'
  stub 2.1.1000
  expect "$plugin: the floor compares numerically" 0 $'mods-floor\tPASS\tclaude 2.1.1000'
  stub 2.1.9
  expect "$plugin: 2.1.9 is below the floor 2.1.287" 1 $'mods-floor\tFAIL\tmods off: claude 2.1.9 is older than the mods floor 2.1.287'
  stub 2.2.0
  expect "$plugin: 2.2.0 is above the floor 2.1.287" 0 $'mods-floor\tPASS\tclaude 2.2.0 meets the mods floor 2.1.287'
  set_floor 2.1.9
  stub 2.1.287
  expect "$plugin: 2.1.287 is above the floor 2.1.9" 0 $'mods-floor\tPASS\tclaude 2.1.287 meets the mods floor 2.1.9'
  set_floor 2.1.287
  stub 2.1.1000
  expect "$plugin: the session row names its own status tool" 0 $'session\tINFO\tlook for mcp__'"$plugin"'__status'

  printf '{"requires":[]}\n' >"$dir/prerequisites.json"
  stub 2.1.287
  expect "$plugin: no floor fails" 1 $'mods-floor\tFAIL\tprerequisites.json declares no mods floor'
  set_floor 2.1.287

  out="$(PATH="$nobin" "$nobin/bash" "$CHECK")"
  code=$?
  expect "$plugin: no claude fails" 1 $'mods-floor\tFAIL\tclaude did not report a version'

  out="$(bash "$CHECK" --root /tmp 2>&1)"
  code=$?
  expect "$plugin: any argument exits 2" 2 "check-mod-load: takes no arguments"
done

exit "$fails"
