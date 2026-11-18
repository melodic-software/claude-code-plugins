#!/usr/bin/env bash
# test-scope: plugins/event-storming/reference/board-backends/markdown.md plugins/event-storming/skills/simulation/SKILL.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2

if ! command -v node >/dev/null 2>&1; then
  echo "board-md: node not found on PATH" >&2
  exit 2
fi

work="$(mktemp -d)" || exit 2
trap 'rm -rf "$work"' EXIT

node "$SCRIPT_DIR/board-md.test.mjs" "$SCRIPT_DIR" "$work"

echo "board-md: all cases passed"
