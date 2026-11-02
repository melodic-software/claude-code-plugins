#!/usr/bin/env bash
# Wiring test for powershell-format's hooks.json: PowerShell is rewritten only at
# git pre-commit (one Invoke-Formatter run costs more than the 1 s per-batch
# ceiling), so there is no PostToolUse or PostToolBatch row; the opt-in Stop row
# is gated on the end-of-turn option; the SessionStart probe honors the kill
# switch and names the missing tool. The pre-commit entry and the Stop script are
# tested in git-hooks/powershell-check.test.sh and powershell-format-end-of-turn.test.sh.
# test-scope: plugins/powershell-format/.claude-plugin/plugin.json plugins/powershell-format/hooks/hooks.json plugins/powershell-format/prerequisites.json plugins/powershell-format/git-hooks/powershell-check.ps1

# shellcheck disable=SC2016  # literal PowerShell variable syntax: single quotes are intentional
set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG CLAUDE_PLUGIN_DATA CLAUDE_PROJECT_DIR CLAUDECODE AI_AGENT

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${HOOK_DIR%/*}"
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
expect() { # <label> <want> <got>
  if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1: want [$2] got [$3]"; fi
}

report_and_exit() {
  echo
  echo "PASS=$PASS FAIL=$FAIL"
  [[ $FAIL -eq 0 ]]
  exit $?
}

if ! command -v jq >/dev/null 2>&1; then
  fail "jq is not on PATH; the wiring cases read hooks.json with it"
  report_and_exit
fi

# --- hooks.json: no per-edit and no per-batch row, an opt-in Stop row ---------
# One Invoke-Formatter run costs more than the 1 s per-batch ceiling (README
# "Hook budget"), so PowerShell is rewritten at pre-commit only.
expect "hooks.json: no PostToolUse row" "0" "$(jq '[.hooks.PostToolUse // [] | .[]] | length' "$HOOKS_JSON")"
expect "hooks.json: no PostToolBatch row" "0" "$(jq '[.hooks.PostToolBatch // [] | .[]] | length' "$HOOKS_JSON")"
expect "hooks.json: no digest-reset SessionStart row" "0" "$(jq '.hooks.SessionStart // [] | length' "$HOOKS_JSON")"
# shellcheck disable=SC2016
EXPECTED_STOP='["${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs","--run-if-unset-or-true","POWERSHELL_FORMAT_ENABLED","--require-true","POWERSHELL_FORMAT_END_OF_TURN","${CLAUDE_PLUGIN_ROOT}/hooks/powershell-format.sh","--end-of-turn"]'
expect "hooks.json: the Stop row is gated on the end-of-turn option" "$EXPECTED_STOP" "$(jq -c '.hooks.Stop[0].hooks[0].args' "$HOOKS_JSON")"
expect "hooks.json: the end-of-turn option is declared, default false" "boolean false" \
  "$(jq -r '.userConfig.powershell_format_end_of_turn | "\(.type) \(.default)"' "$PLUGIN_ROOT/.claude-plugin/plugin.json")"

# --- SessionStart probe: bound to prerequisites.json, honors the kill switch ---
# The Stop script stays quiet without pwsh, so the SessionStart row is the only
# reporter. The manifest declares pwsh and node, never jq, which nothing runs (PSScriptAnalyzer is a
# module, not a PATH binary, so /powershell-format:check reports it instead), and
# the probe's notice must state each tool's name, check and install, verbatim.
# The probe runs the hooks.json row as the harness spawns it: `node` with the
# row's args, ${CLAUDE_PLUGIN_ROOT} expanded, from an empty cwd, on a PATH that
# holds the system tools and no pwsh. The gate is `--run-if-unset-or-true` in
# exec-bash.mjs, so a row without it prints the notice for a disabled plugin.
# A missing node fails the suite instead of skipping the cases: every hook row
# launches through it. These cases need no pwsh, so they run before the skip.
HOOKS_JSON="$HOOK_DIR/hooks.json"
PLUGIN_ROOT="${HOOK_DIR%/*}"
MANIFEST="$PLUGIN_ROOT/prerequisites.json"
if jq -e '(.requires | map(.id)) == ["pwsh", "node"]' "$MANIFEST" >/dev/null 2>&1; then
  ok "manifest: declares exactly pwsh and node"
else
  fail "manifest: expected tools pwsh and node: $(cat "$MANIFEST" 2>&1)"
fi
# harness-ops' prerequisites-fleet.mjs runs the probe behind the kill switch; its own test covers the gate.
if jq -e '.session_probe.run_if_unset_or_true == "POWERSHELL_FORMAT_ENABLED"' "$MANIFEST" >/dev/null &&
  jq -e '.hooks | has("SessionStart") | not' "$HOOKS_JSON" >/dev/null; then
  ok "manifest: session_probe is gated on POWERSHELL_FORMAT_ENABLED, and hooks.json carries no SessionStart row"
else
  fail "manifest: want session_probe gated on POWERSHELL_FORMAT_ENABLED and no SessionStart row in hooks.json"
fi

report_and_exit
