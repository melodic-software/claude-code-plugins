#!/usr/bin/env bash
# Registration and prerequisite tests for the actionlint plugin's Claude Code
# hooks. actionlint only reports, so no hook runs per edit or per batch: the
# manifest registers no PostToolUse, PostToolBatch or SessionStart row and one
# opt-in Stop row; harness-ops runs the prerequisites probe (session_probe). The
# Stop row's behavior is tested in actionlint-end-of-turn.test.sh and the
# pre-commit entry's in git-hooks/actionlint-check.test.sh.
# test-scope: plugins/actionlint/hooks/hooks.json plugins/actionlint/.claude-plugin/plugin.json plugins/actionlint/lib/prerequisites.mjs plugins/actionlint/prerequisites.json
# test-scope: plugins/actionlint/lib/git-hooks/install.mjs
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE CLAUDE_PLUGIN_OPTION_ACTIONLINT_ENABLED

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${HOOK_DIR%/*}"
HOOKS_JSON="$HOOK_DIR/hooks.json"
MANIFEST="$PLUGIN_ROOT/prerequisites.json"
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"

for tool in jq node; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "SKIP: $tool not on PATH -- actionlint hook tests skipped"
    exit 0
  }
done

PASS=0
FAIL=0
expect() { # <label> <want> <got>
  if [[ "$2" == "$3" ]]; then
    echo "ok: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1: want [$2] got [$3]" >&2
    FAIL=$((FAIL + 1))
  fi
}

expect "hooks.json registers Stop only: no per-edit, per-batch or SessionStart row" \
  "Stop" "$(jq -r '.hooks | keys | join(",")' "$HOOKS_JSON")"
expect "the Stop row is gated on the end-of-turn option" "ACTIONLINT_END_OF_TURN" \
  "$(jq -r '.hooks.Stop[0].hooks[0].args | .[index("--require-true") + 1]' "$HOOKS_JSON")"
expect "the end-of-turn option defaults to false" "false" "$(jq -r '.userConfig.actionlint_end_of_turn.default' "$PLUGIN_JSON")"
expect "the plugin declares only the options a hook reads" "actionlint_enabled,actionlint_end_of_turn" \
  "$(jq -r '.userConfig | keys | join(",")' "$PLUGIN_JSON")"
expect "the git-hook entry is a report-only pre-commit entry" "pre-commit false" \
  "$(jq -r '.entries[0] | "\(.event) \(.rewrites)"' "$PLUGIN_ROOT/git-hooks/entries.json")"

# --- The manifest lists the plugin's tools ------------------------------------
expect "manifest: declares exactly actionlint and node" "actionlint,node" "$(jq -r '.requires | map(.id) | join(",")' "$MANIFEST")"

# --- SessionStart probe: run by harness-ops behind actionlint_enabled ---
# harness-ops' prerequisites-fleet.mjs runs this plugin's probe and skips it when the
# option is set to anything but true; that runner's own test covers the gate.
expect "prerequisites.json: session_probe is gated on actionlint_enabled" "ACTIONLINT_ENABLED" \
  "$(jq -r '.session_probe.run_if_unset_or_true' "$PLUGIN_ROOT/prerequisites.json" | tr -d '\r')"

echo "actionlint hooks: $PASS passed, $FAIL failed"
((FAIL == 0))
