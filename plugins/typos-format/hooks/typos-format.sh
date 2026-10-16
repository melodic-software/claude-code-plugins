#!/usr/bin/env bash
# typos-format hook entry for the one row that remains after spell-check
# findings moved to commit time (the git pre-commit entry in git-hooks/):
#
#   typos-format.sh --end-of-turn    the opt-in Stop row (typos_format_end_of_turn)
#
# Any other invocation exits 0 and does nothing.

set -uo pipefail

# The hook's own directory by parameter expansion rather than `dirname`, which
# costs a spawn on Windows Git Bash; the fallback covers a bare filename.
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.
# Kill switch before any source. The hooks.json rows ask exec-bash.mjs to apply
# the same switch before it spawns bash; a direct invocation reads this line.
# scripts/check-killswitch-hoist.sh pins it to hook::is_enabled.
[[ "${CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED:-true}" == "true" ]] || exit 0

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"

# The opt-in Stop row (its hooks.json gate is --require-true): the pre-commit
# entry run over the uncommitted changes. Its findings exit 2, so the model
# fixes them before the turn ends. Once a Stop hook has continued this turn
# (stop_hook_active), the row stays quiet, so it blocks at most once per turn.
# A host without typos already hears of it from the SessionStart probe, so here
# that is a silent pass, not a block.
if [[ "${1:-}" == --end-of-turn ]]; then
  hook::buffer_stdin_to INPUT || exit 0
  [[ "$INPUT" =~ \"stop_hook_active\"[[:space:]]*:[[:space:]]*true ]] && exit 0
  # silent-skip-ok: the SessionStart probe already told the user typos is missing (prerequisites.json, hook:typos-format.sh), and /typos-format:check reports it; blocking every turn end on a host problem would not help the model.
  command -v typos >/dev/null 2>&1 || exit 0
  "${BASH:-bash}" "$HOOK_DIR/../git-hooks/typos-check.sh" --worktree >/dev/null && exit 0
  exit 2
fi

exit 0
