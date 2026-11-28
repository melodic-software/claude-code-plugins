#!/usr/bin/env bash
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

json="$(jq -nR '[inputs] as $globs |
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
  {
    description: "Names what a Write or Edit to a test file removes: test blocks, assertions, a changed expected value or an added skip (opt-in: test_guards_enabled).",
    hooks: {
      PreToolUse: rows("test-weaken.sh"; {timeout: 10, statusMessage: "Checking the edit for removed assertions or skipped tests..."})
    }
  }' <<<"$globs")" || exit 2

if [[ "${1:-}" == --check ]]; then
  if [[ "$json" != "$(cat "$OUT" 2>/dev/null)" ]]; then
    echo "gen-hook-filters: $OUT is out of date; run plugins/testing/scripts/gen-hook-filters.sh" >&2
    exit 1
  fi
  exit 0
fi
printf '%s\n' "$json" >"$OUT"
