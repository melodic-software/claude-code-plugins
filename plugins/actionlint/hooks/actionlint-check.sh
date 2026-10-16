#!/usr/bin/env bash
# Stop hook (opt-in, actionlint_end_of_turn): run the pre-commit entry over the
# uncommitted workflow changes when a turn ends.
#
#   actionlint-check.sh --end-of-turn
#
# actionlint only reports, so nothing runs per edit or per batch. This row is the
# one place a session sees its findings before commit: the entry
# (git-hooks/actionlint-check.sh --worktree) reports what actionlint finds on the
# lines changed since the last commit, and findings exit 2 so the model fixes
# them before the turn ends. Once a Stop hook has continued the turn
# (stop_hook_active) the row stays quiet, so it blocks at most once per turn.
# The launcher's --require-true gate keeps the script from starting while the
# option is off.

set -uo pipefail

[[ "${1:-}" == --end-of-turn ]] || exit 0
[[ "${CLAUDE_PLUGIN_OPTION_ACTIONLINT_ENABLED:-true}" == "true" ]] || exit 0
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

IFS= read -r -d '' INPUT || :
[[ "$INPUT" =~ \"stop_hook_active\"[[:space:]]*:[[:space:]]*true ]] && exit 0
"${BASH:-bash}" "$HOOK_DIR/../git-hooks/actionlint-check.sh" --worktree >/dev/null && exit 0
exit 2
