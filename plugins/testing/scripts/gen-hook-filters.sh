#!/usr/bin/env bash
# gen-hook-filters.sh: write hooks/hooks.json from the adapters' files: globs.
#
# The test-weaken (PreToolUse) and test-scan (PostToolUse) hooks start only for
# paths an `if` row matches, and those rows must list exactly the test-file
# globs the scanner claims, so they are generated from one source, the same
# for both events: the union of every shipped adapter's files: list,
# deduplicated and sorted. An `if` holds one rule and names one tool, so each
# glob gets a Write row and an Edit row: an Edit(...) row does not match a
# Write call (probes.md). A glob with no slash matches the basename at any
# depth (gitignore syntax).
#
# Usage: gen-hook-filters.sh [--check]
#   (no arg)  rewrite hooks/hooks.json
#   --check   exit 1 when hooks/hooks.json differs from what would be written
# Exit: 0 written or in sync; 1 drift; 2 setup failed.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUDIT="$ROOT/skills/audit"
OUT="$ROOT/hooks/hooks.json"

globs="$(awk -f "$AUDIT/scripts/adapter-load.awk" "$AUDIT"/adapters/*.yaml |
  awk -F'\t' '$2 == "files" { print $3 }' | LC_ALL=C sort -u)" || exit 2
[[ -n "$globs" ]] || {
  echo "gen-hook-filters: no files: globs in $AUDIT/adapters" >&2
  exit 2
}

json="$(jq -R . <<<"$globs" | jq -s '. as $globs | def rows($script; $status): [{
    matcher: "Write|Edit",
    hooks: [$globs[] as $g | ("Write", "Edit") | {
      type: "command",
      command: "node",
      args: ["${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs", "--require-true", "TEST_GUARDS_ENABLED",
        "${CLAUDE_PLUGIN_ROOT}/hooks/\($script)"],
      if: "\(.)(\($g))",
      timeout: 10,
      statusMessage: $status
    }]
  }];
  {
    description: "Names what a Write or Edit to a test file removes, and scans the written file for tests that cannot fail (opt-in: test_guards_enabled).",
    hooks: {
      PreToolUse: rows("test-weaken.sh"; "Checking the edit for removed assertions or skipped tests..."),
      PostToolUse: rows("test-scan.sh"; "Scanning the test file for tests that cannot fail...")
    }
  }')" || exit 2

if [[ "${1:-}" == --check ]]; then
  if [[ "$json" != "$(cat "$OUT" 2>/dev/null)" ]]; then
    echo "gen-hook-filters: $OUT is out of date; run plugins/testing/scripts/gen-hook-filters.sh" >&2
    exit 1
  fi
  exit 0
fi
printf '%s\n' "$json" >"$OUT"
