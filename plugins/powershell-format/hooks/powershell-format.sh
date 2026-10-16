#!/usr/bin/env bash
# Stop hook (opt-in: powershell_format_end_of_turn): the pre-commit entry run over
# the uncommitted changes, without rewriting.
#
#   powershell-format.sh --end-of-turn
#
# Findings exit 2 so the model fixes them before the turn ends; once a Stop hook
# has continued the turn (stop_hook_active) the row stays quiet, so it blocks at
# most once per turn. PowerShell is never rewritten in session: one
# Invoke-Formatter run costs more than the per-batch ceiling allows, so the
# rewrite is the pre-commit entry's job (git-hooks/powershell-check.sh), which also
# covers every author.

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED:-true}" == "true" ]] || exit 0
[[ "${1:-}" == --end-of-turn ]] || exit 0
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

IFS= read -r -d '' INPUT || :
[[ "$INPUT" =~ \"stop_hook_active\"[[:space:]]*:[[:space:]]*true ]] && exit 0
"${BASH:-bash}" "$HOOK_DIR/../git-hooks/powershell-check.sh" --worktree >/dev/null && exit 0
exit 2
