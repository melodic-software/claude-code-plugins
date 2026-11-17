#!/usr/bin/env bash
# Stop hook (opt-in: powershell_format_end_of_turn): the pre-commit lint entry run
# over the uncommitted changes. Nothing is rewritten.
#
#   powershell-format.sh --end-of-turn
#
# Findings exit 2 so the model fixes them before the turn ends; once a Stop hook
# has continued the turn (stop_hook_active) the row stays quiet, so it blocks at
# most once per turn. PowerShell is never formatted in session: one
# Invoke-Formatter run costs more than the per-batch ceiling allows, so the
# rewrite is the pre-commit format entry's job (git-hooks/format.sh), which also
# covers every author.

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED:-true}" == "true" ]] || exit 0
[[ "${1:-}" == --end-of-turn ]] || exit 0
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

IFS= read -r -d '' INPUT || :
[[ "$INPUT" =~ \"stop_hook_active\"[[:space:]]*:[[:space:]]*true ]] && exit 0
err="$("${BASH:-bash}" "$HOOK_DIR/../git-hooks/lint.sh" --worktree 2>&1 >/dev/null)" && exit 0
# A missing pwsh or PSScriptAnalyzer is a host problem: the SessionStart probe
# and /powershell-format:setup check report it, and blocking every turn end on it
# would not help the model. Only those lines are dropped; any finding printed
# beside them is still handed back.
report=""
while IFS= read -r line; do
  case "$line" in
    "FAIL: "*" missing. Install: "* | "To skip only while "*" is missing: "*) ;;
    *) report+="$line"$'\n' ;;
  esac
done <<<"$err"
# silent-skip-ok: only missing-tool lines remained, which the SessionStart probe and setup check report.
[[ -n "${report//[[:space:]]/}" ]] || exit 0
printf '%s' "$report" >&2
exit 2
