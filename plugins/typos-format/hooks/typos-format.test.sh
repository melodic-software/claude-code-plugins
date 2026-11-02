#!/usr/bin/env bash
# Contract test for typos-format's Claude Code hook rows after spell-check
# findings moved to commit time: the hooks.json row set (no per-edit
# PostToolUse row, no digest reset and no SessionStart row; the opt-in Stop row),
# the prerequisites manifest and its session_probe gate, and typos-format.sh's
# remaining entry points. The Stop
# row's behavior is typos-format-end-of-turn.test.sh; the pre-commit check is
# git-hooks/typos-check.test.sh.
# test-scope: plugins/typos-format/.claude-plugin/plugin.json plugins/typos-format/hooks/hooks.json plugins/typos-format/prerequisites.json

set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/typos-format.sh"
PLUGIN_ROOT="$(cd "$HOOK_DIR/.." && pwd)"
HOOKS_JSON="$HOOK_DIR/hooks.json"

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
command -v jq >/dev/null 2>&1 || {
  echo "SKIP: jq not on PATH -- typos-format row tests skipped"
  exit 0
}

# --- The row set ------------------------------------------------------------------
if [[ "$(jq -c '.hooks | keys' "$HOOKS_JSON")" == '["Stop"]' ]]; then
  ok "hooks.json: no per-edit PostToolUse row and no SessionStart row; only Stop"
else
  fail "hooks.json: want events [Stop], got $(jq -c '.hooks | keys' "$HOOKS_JSON")"
fi
# No row resets per-edit finding digests: nothing writes them now that findings
# arrive at commit time. harness-ops runs the prerequisites probe (session_probe below).
if [[ "$(jq '[.hooks[][] | select(.matcher == "compact|clear")] + [.. | strings | select(. == "--reset-digests")] | length' "$HOOKS_JSON")" == "0" ]]; then
  ok "hooks.json: no compact|clear row and no --reset-digests argument"
else
  fail "hooks.json: a compact|clear or --reset-digests row is still registered"
fi
if jq -e '([.hooks.Stop[].hooks[] | select(.command == "node" and .args == ["${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs", "--run-if-unset-or-true", "TYPOS_FORMAT_ENABLED", "--require-true", "TYPOS_FORMAT_END_OF_TURN", "${CLAUDE_PLUGIN_ROOT}/hooks/typos-format.sh", "--end-of-turn"])] | length == 1) and ([.hooks.Stop[].hooks[]] | length == 1)' "$HOOKS_JSON" >/dev/null; then
  ok "hooks.json: one Stop row runs --end-of-turn behind --require-true TYPOS_FORMAT_END_OF_TURN"
else
  fail "hooks.json: expected exactly one Stop row running --end-of-turn behind --require-true TYPOS_FORMAT_END_OF_TURN"
fi
if [[ "$(jq -c '.userConfig | keys' "$PLUGIN_ROOT/.claude-plugin/plugin.json")" == '["typos_format_enabled","typos_format_end_of_turn"]' ]]; then
  ok "plugin.json: the options are the kill switch and the end-of-turn opt-in"
else
  fail "plugin.json: unexpected options $(jq -c '.userConfig | keys' "$PLUGIN_ROOT/.claude-plugin/plugin.json")"
fi
if [[ "$(jq '.userConfig.typos_format_end_of_turn.default' "$PLUGIN_ROOT/.claude-plugin/plugin.json")" == false ]]; then
  ok "plugin.json: the end-of-turn check is off by default"
else
  fail "plugin.json: typos_format_end_of_turn must default to false"
fi

# --- The manifest lists the plugin's tools ------------------------------------------
MANIFEST="$PLUGIN_ROOT/prerequisites.json"
if jq -e '(.requires | map(.id)) == ["typos", "jq", "node"]' "$MANIFEST" >/dev/null 2>&1; then
  ok "manifest: declares exactly typos, jq and node"
else
  fail "manifest: expected tools typos, jq and node: $(cat "$MANIFEST" 2>/dev/null)"
fi
# harness-ops' prerequisites-fleet.mjs runs the probe behind the kill switch; its own test covers the gate.
if jq -e '.session_probe.run_if_unset_or_true == "TYPOS_FORMAT_ENABLED"' "$MANIFEST" >/dev/null; then
  ok "manifest: session_probe is gated on TYPOS_FORMAT_ENABLED"
else
  fail "manifest: want session_probe gated on TYPOS_FORMAT_ENABLED"
fi

# --- typos-format.sh's remaining entry points -------------------------------------
out="$(printf '{"session_id":"s","hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":"/tmp/x.md"}}' | bash "$HOOK" 2>&1)"
rc=$?
if [[ $rc -eq 0 && -z "$out" ]]; then
  ok "script: an invocation with no mode flag exits 0 silently (no per-edit path remains)"
else
  fail "script: no-flag invocation gave rc=$rc out=$out"
fi
if grep -q -- '--reset-digests' "$HOOK"; then
  fail "script: typos-format.sh still carries a --reset-digests branch"
else
  ok "script: no --reset-digests branch remains"
fi
out="$(printf '{"stop_hook_active":false}' | CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=false bash "$HOOK" --end-of-turn 2>&1)"
rc=$?
if [[ $rc -eq 0 && -z "$out" ]]; then
  ok "script: the kill switch exits 0 before any mode runs"
else
  fail "script: kill switch false gave rc=$rc out=$out"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
