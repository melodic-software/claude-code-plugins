#!/usr/bin/env bash
# Contract tests for the opt-in Stop row (powershell_format_end_of_turn), launched
# exactly as hooks.json registers it: off by default; on, an uncommitted finding
# exits 2 with the finding on stderr and nothing is rewritten; stop_hook_active
# keeps it from blocking twice in one turn; the plugin kill switch wins. The
# spawn budget case fences the cost every user pays per turn with the option
# off: the node launcher only.
# test-scope: plugins/powershell-format/hooks/hooks.json plugins/powershell-format/git-hooks/powershell-check.sh plugins/powershell-format/.claude-plugin/plugin.json
# shellcheck disable=SC2016  # literal PowerShell variable syntax: single quotes are intentional
set -uo pipefail
unset CLAUDECODE AI_AGENT GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_END_OF_TURN CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HOOK_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN/../.." && pwd)"
for tool in node jq pwsh git; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "SKIP: $tool not on PATH -- end-of-turn tests skipped"
    exit 0
  }
done

if ! pwsh -NoProfile -NonInteractive -Command 'if (Get-Module -ListAvailable -Name PSScriptAnalyzer) { exit 0 } else { exit 1 }' >/dev/null 2>&1; then
  echo "SKIP: PSScriptAnalyzer module not installed -- end-of-turn tests skipped"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL="$WORK/no-global" GIT_CONFIG_NOSYSTEM=1

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

# The Stop row's args from hooks.json, with the plugin root substituted.
mapfile -t ARGS < <(jq -r '.hooks.Stop[0].hooks[0].args[]' "$PLUGIN/hooks/hooks.json" | sed "s#\${CLAUDE_PLUGIN_ROOT}#$PLUGIN#g")
expect "the Stop row launches node with the end-of-turn gate" \
  "node --run-if-unset-or-true POWERSHELL_FORMAT_ENABLED --require-true POWERSHELL_FORMAT_END_OF_TURN --end-of-turn" \
  "$(jq -r '.hooks.Stop[0].hooks[0].command' "$PLUGIN/hooks/hooks.json") ${ARGS[1]} ${ARGS[2]} ${ARGS[3]} ${ARGS[4]} ${ARGS[6]}"

R="$WORK/repo"
git init -q -b main "$R"
git -C "$R" config user.name t
git -C "$R" config user.email t@example.invalid
printf "@{ IncludeRules = @('PSAvoidGlobalVars') }\n" >"$R/PSScriptAnalyzerSettings.psd1"
printf 'Get-Date\n' >"$R/a.ps1"
git -C "$R" add -A
git -C "$R" commit -q -m seed

stop() { # <stop_hook_active> [env...] -> "<rc>|<stderr>"
  local active="$1" err rc
  shift
  err="$(cd "$R" && printf '{"session_id":"s","hook_event_name":"Stop","stop_hook_active":%s,"cwd":"%s"}' "$active" "$R" |
    env "$@" node "${ARGS[@]}" 2>&1 >/dev/null)"
  rc=$?
  printf '%s|%s' "$rc" "$err"
}

FINDING="a.ps1:2: [Warning] PSAvoidGlobalVars: Found global variable 'global:foo'.
powershell-format: fix the findings above, or adjust the repository PSScriptAnalyzerSettings.psd1."
printf 'Get-Date\n$global:foo = 1\n' >"$R/a.ps1"
expect "off by default: an uncommitted finding does not block" "0|" "$(stop false)"
expect "on: an uncommitted finding on a changed line exits 2 with the finding" "2|$FINDING" \
  "$(stop false CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_END_OF_TURN=true)"
expect "on: nothing is rewritten" "$(printf 'Get-Date\n$global:foo = 1')" "$(cat "$R/a.ps1")"
expect "on: stop_hook_active means it already blocked this turn" "0|" \
  "$(stop true CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_END_OF_TURN=true)"
expect "on: the plugin kill switch wins" "0|" \
  "$(stop false CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_END_OF_TURN=true CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED=false)"
git -C "$R" checkout -q a.ps1
expect "on: a clean work tree passes" "0|" "$(stop false CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_END_OF_TURN=true)"

CENSUS="$REPO_ROOT/scripts/hook-census.sh"
if [[ -f "$CENSUS" ]] && command -v strace >/dev/null 2>&1; then
  out="$(bash "$CENSUS" powershell-format Stop powershell-format.sh \
    '{"session_id":"census","hook_event_name":"Stop","stop_hook_active":false,"cwd":"@DIR@"}' --check 'test ! -s "$HOOK_STDOUT"')"
  expect "spawn budget: with the option off a Stop costs only the node launcher" "spawns=1" "${out%% *}"
else
  echo "NOTE: strace or scripts/hook-census.sh absent; the spawn budget case did not run."
fi

echo "powershell-format end-of-turn: $PASS passed, $FAIL failed"
((FAIL == 0))
