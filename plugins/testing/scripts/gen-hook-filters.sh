#!/usr/bin/env bash
# gen-hook-filters.sh: write hooks/hooks.json from the adapters' files: globs.
#
# The test-weaken (PreToolUse) hook starts only for paths an `if` row matches,
# and those rows must list exactly the test-file globs the scanner claims, so
# they are generated from one source: the union of every shipped adapter's
# files: list, deduplicated and sorted. An `if` holds one rule and names one
# tool, so each glob gets a Write row and an Edit row: an Edit(...) row does
# not match a Write call (the `if` probe, below). A glob with no slash matches
# the basename at any depth (gitignore syntax).
# The `if` probe: https://github.com/melodic-software/claude-code-plugins/blob/9a0d6f5cf47098fa73bb4b8bb41336be1945c70e/docs/specs/tautological-tests/probes.md#if-row-matching-and-hook-input-claude-code-21284-wsl2-2026-09-28
# (as of 2026-09-28; recheck when a Claude Code release note changes how a
# hook's `if` rule matches a tool call).
#
# No PostToolUse row: test-quality findings are report-only, so they come from
# /testing:audit on demand, never per edit (docs/conventions/check-placement).
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

json="$(jq -R . <<<"$globs" | jq -s '. as $globs |
  def cmd($gates; $script): {
    type: "command",
    command: "node",
    args: (["${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs"] + ($gates | map("--require-true", .))
      + ["${CLAUDE_PLUGIN_ROOT}/hooks/\($script)"])
  };
  def rows($script; $extra): [{
    matcher: "Write|Edit",
    hooks: [$globs[] as $g | ("Write", "Edit") | {if: "\(.)(\($g))"} as $if
      | cmd(["TEST_GUARDS_ENABLED"]; $script) + $if + $extra]
  }];
  # The node-notice row runs without node, so it is shell form; the prerequisites convention owns it,
  # including the matcher that skips compaction.
  def notice: [{matcher: "startup|resume|clear|fork", hooks: [{type: "command",
    command: "sh \"${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.sh\" node-notice /testing:check; ${PPID:+exit}; powershell -NoProfile -ExecutionPolicy Bypass -File \"${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.ps1\" node-notice /testing:check",
    timeout: 10, statusMessage: "Checking that node is on PATH..."}]}];
  {
    description: "Names what a Write or Edit to a test file removes: test blocks, assertions, a changed expected value or an added skip (opt-in: test_guards_enabled).",
    hooks: {
      PreToolUse: rows("test-weaken.sh"; {timeout: 10, statusMessage: "Checking the edit for removed assertions or skipped tests..."}),
      SessionStart: notice
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
