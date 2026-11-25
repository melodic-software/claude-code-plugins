#!/usr/bin/env bash
# test-scope: plugins/powershell-format/.claude-plugin/plugin.json plugins/powershell-format/hooks/hooks.json plugins/powershell-format/prerequisites.json plugins/powershell-format/git-hooks/psscriptanalyzer.ps1
# test-scope: plugins/powershell-format/git-hooks/format.sh

# shellcheck disable=SC2016  # literal PowerShell variable syntax: single quotes are intentional
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG CLAUDE_PLUGIN_DATA CLAUDE_PROJECT_DIR CLAUDECODE AI_AGENT
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

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

expect "hooks.json: no PostToolUse row" "0" "$(jq '[.hooks.PostToolUse // [] | .[]] | length' "$HOOKS_JSON")"
expect "hooks.json: no PostToolBatch row" "0" "$(jq '[.hooks.PostToolBatch // [] | .[]] | length' "$HOOKS_JSON")"
expect "hooks.json: no digest-reset SessionStart row" "0" "$(jq '.hooks.SessionStart // [] | length' "$HOOKS_JSON")"
# shellcheck disable=SC2016
EXPECTED_STOP='["${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs","--run-if-unset-or-true","POWERSHELL_FORMAT_ENABLED","--require-true","POWERSHELL_FORMAT_END_OF_TURN","${CLAUDE_PLUGIN_ROOT}/hooks/powershell-format.sh","--end-of-turn"]'
expect "hooks.json: the Stop row is gated on the end-of-turn option" "$EXPECTED_STOP" "$(jq -c '.hooks.Stop[0].hooks[0].args' "$HOOKS_JSON")"
expect "hooks.json: the end-of-turn option is declared, default false" "boolean false" \
  "$(jq -r '.userConfig.powershell_format_end_of_turn | "\(.type) \(.default)"' "$PLUGIN_ROOT/.claude-plugin/plugin.json")"

HOOKS_JSON="$HOOK_DIR/hooks.json"
PLUGIN_ROOT="${HOOK_DIR%/*}"
MANIFEST="$PLUGIN_ROOT/prerequisites.json"
if jq -e '(.requires | map(.id)) == ["pwsh", "node"]' "$MANIFEST" >/dev/null 2>&1; then
  ok "manifest: declares exactly pwsh and node"
else
  fail "manifest: expected tools pwsh and node: $(cat "$MANIFEST" 2>&1)"
fi
expect "manifest: pwsh is needed only where a settings file is" '["PSScriptAnalyzerSettings.psd1"]' \
  "$(jq -c '.requires[] | select(.id == "pwsh") | .when.config_any' "$MANIFEST")"

if [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* ]]; then
  echo "SKIP: the probe cases run git alone on PATH, which Git for Windows cannot"
else
  PROBE_DIR="$(mktemp -d)"
  trap 'rm -rf "${PROBE_DIR:?}"' EXIT
  ln -s "$(command -v git)" "$PROBE_DIR/git"
  PROBE_NODE="$(node -p process.execPath)"
  probe_says() {
    local r="$1" f
    shift
    git init -q "$r"
    for f in "$@"; do mkdir -p "$(dirname "$r/$f")" && : >"$r/$f"; done
    git -C "$r" add -- "$@"
    (cd "$r" && printf '{"session_id":"t"}' | env -i PATH="$PROBE_DIR" HOME="$r" CLAUDE_PROJECT_DIR="$r" \
      "$PROBE_NODE" "$PLUGIN_ROOT/lib/prerequisites.mjs" probe "$PLUGIN_ROOT") || echo "probe exited $?"
  }
  NOTICE="powershell-format: pwsh not on the hook PATH"
  case "$(probe_says "$PROBE_DIR/root" PSScriptAnalyzerSettings.psd1 build.ps1)" in
  *"$NOTICE"*) ok "probe: a settings file at the repository root reports a missing pwsh" ;;
  *) fail "probe: a root settings file did not report pwsh" ;;
  esac
  case "$(probe_says "$PROBE_DIR/nested" mod/PSScriptAnalyzerSettings.psd1)" in
  *"$NOTICE"*) ok "probe: a settings file tracked only in a subdirectory reports a missing pwsh" ;;
  *) fail "probe: a nested settings file did not report pwsh" ;;
  esac
  case "$(probe_says "$PROBE_DIR/none" mod/build.ps1)" in
  *"$NOTICE"* | *"probe exited"*) fail "probe: a repository with no settings file reported pwsh, or the probe failed" ;;
  *) ok "probe: a repository with no settings file stays quiet about pwsh" ;;
  esac
fi
if jq -e '.session_probe.run_if_unset_or_true == "POWERSHELL_FORMAT_ENABLED"' "$MANIFEST" >/dev/null &&
  jq -e '.hooks | has("SessionStart") | not' "$HOOKS_JSON" >/dev/null; then
  ok "manifest: session_probe is gated on POWERSHELL_FORMAT_ENABLED, and hooks.json carries no SessionStart row"
else
  fail "manifest: want session_probe gated on POWERSHELL_FORMAT_ENABLED and no SessionStart row in hooks.json"
fi

report_and_exit
