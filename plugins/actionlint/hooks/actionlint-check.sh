#!/usr/bin/env bash
# Stop hook (opt-in, actionlint_end_of_turn): run the lint entry over the
# uncommitted workflow changes when a turn ends.
#
#   actionlint-check.sh --end-of-turn

set -uo pipefail

[[ "${1:-}" == --end-of-turn ]] || exit 0
[[ "${CLAUDE_PLUGIN_OPTION_ACTIONLINT_ENABLED:-true}" == "true" ]] || exit 0
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

IFS= read -r -d '' INPUT || :
[[ "$INPUT" =~ \"stop_hook_active\"[[:space:]]*:[[:space:]]*true ]] && exit 0
err="$("${BASH:-bash}" "$HOOK_DIR/../git-hooks/lint.sh" --worktree 2>&1 >/dev/null)" && exit 0
# silent-skip-ok: the SessionStart probe already reports a missing actionlint (prerequisites.json) and the bundled checker does too; blocking every turn end on a host problem would not help the model.
[[ "$err" == "FAIL: "*" missing. Install: "* ]] && exit 0
printf '%s\n' "$err" >&2
exit 2
